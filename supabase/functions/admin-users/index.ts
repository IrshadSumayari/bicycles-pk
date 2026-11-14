// Supabase Edge Function: admin-only user management.
// The service role key lives here (server side), never in the browser.
//
// Deploy:  supabase functions deploy admin-users
// Actions: { action: 'create', email, password, name, username, role, active, avatar? }
//          { action: 'delete', userId }

import { createClient } from 'jsr:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const ROLES = ['admin', 'manager', 'cashier'];

// Assurance level of the caller's session. The token was already validated by
// auth.getUser() below, so reading its claims here is safe.
function sessionLevel(authorization: string): string {
  try {
    const payload = authorization.replace(/^Bearer\s+/i, '').split('.')[1] ?? '';
    const base64 = payload.replace(/-/g, '+').replace(/_/g, '/');
    return String(JSON.parse(atob(base64.padEnd(Math.ceil(base64.length / 4) * 4, '='))).aal ?? '');
  } catch {
    return '';
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // Identify the caller from their own JWT
  const authorization = req.headers.get('Authorization') ?? '';
  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user: callerUser } } = await caller.auth.getUser();
  if (!callerUser) return json({ error: 'Not signed in' }, 401);
  // Matches current_app_role(): an administrator's role needs an authenticator-verified session.
  if (sessionLevel(authorization) !== 'aal2') {
    return json({ error: 'Confirm your sign-in with your authenticator app first' }, 403);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: callerProfile } = await admin
    .from('users')
    .select('role, active')
    .eq('id', callerUser.id)
    .single();
  if (!callerProfile || callerProfile.role !== 'admin' || !callerProfile.active) {
    return json({ error: 'Only administrators can manage users' }, 403);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid request body' }, 400);
  }

  try {
    if (body.action === 'create') {
      const email = String(body.email ?? '').trim().toLowerCase();
      const password = String(body.password ?? '');
      const name = String(body.name ?? '').trim();
      const username = String(body.username ?? '').trim();
      const role = String(body.role ?? 'cashier');
      const active = body.active !== false;
      const avatar = body.avatar ? String(body.avatar) : null;

      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: 'Invalid email address' }, 400);
      if (password.length < 12) return json({ error: 'Password must be at least 12 characters long' }, 400);
      if (!name || !username) return json({ error: 'Name and username are required' }, 400);
      if (!ROLES.includes(role)) return json({ error: 'Invalid role' }, 400);
      if (avatar && !/^https:\/\//i.test(avatar)) return json({ error: 'Avatar must be an https URL' }, 400);

      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { name, username },
        // Routes the sign-up trigger to create a staff profile (not a customer account)
        app_metadata: { account_type: 'staff' },
      });
      if (createError) return json({ error: createError.message }, 400);

      // The auth trigger created the profile; apply the role the admin chose
      const { data: profile, error: profileError } = await admin
        .from('users')
        .update({ username, name, email, role, active, avatar })
        .eq('id', created.user.id)
        .select()
        .single();
      if (profileError) {
        await admin.auth.admin.deleteUser(created.user.id);
        return json({ error: profileError.message }, 400);
      }

      return json({ user: profile });
    }

    if (body.action === 'delete') {
      const userId = String(body.userId ?? '');
      if (!userId) return json({ error: 'userId is required' }, 400);
      if (userId === callerUser.id) return json({ error: 'You cannot delete your own account' }, 400);

      const { data: target } = await admin.from('users').select('role, active').eq('id', userId).single();
      if (target?.role === 'admin' && target.active) {
        const { count } = await admin
          .from('users')
          .select('id', { count: 'exact', head: true })
          .eq('role', 'admin')
          .eq('active', true);
        if ((count ?? 0) <= 1) return json({ error: 'At least one active administrator is required' }, 400);
      }

      // Deleting the auth user cascades to the profile row
      const { error } = await admin.auth.admin.deleteUser(userId);
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    return json({ error: 'Unknown action' }, 400);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'Unexpected error' }, 500);
  }
});
