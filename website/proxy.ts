import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import type { Database } from "@database";
import { buildCsp } from "./lib/security";
import { accessGate } from "./lib/access-gate";
export async function proxy(request: NextRequest) {
  const nonce = Buffer.from(crypto.randomUUID()).toString("base64");
  const csp = buildCsp({
    nonce,
    supabase:
      process.env.NEXT_PUBLIC_SUPABASE_URL || "https://example.supabase.co",
    development: process.env.NODE_ENV === "development",
    payments: process.env.PAYMENT_CHECKOUT_ORIGINS,
    analyticsId: process.env.NEXT_PUBLIC_ANALYTICS_ID,
  });
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-nonce", nonce);
  requestHeaders.set("Content-Security-Policy", csp);
  const secure = (response: NextResponse) => {
    response.headers.set("Content-Security-Policy", csp);
    return response;
  };
  if (process.env.SITE_ACCESS_KEY) {
    const gate = await accessGate(request, process.env.SITE_ACCESS_KEY, nonce);
    if (gate) return secure(gate);
  }
  let response = NextResponse.next({ request: { headers: requestHeaders } });
  const protectedRoute =
    /^\/(account(?:\/|$)|checkout(?:\/|$))/.test(request.nextUrl.pathname);
  if (!protectedRoute) return secure(response);
  if (
    !process.env.NEXT_PUBLIC_SUPABASE_URL ||
    !process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  ) {
    if (request.nextUrl.pathname === "/account/sign-in") {
      response.headers.set("Cache-Control", "private, no-store");
      return secure(response);
    }
    const target = request.nextUrl.clone();
    target.pathname = "/account/sign-in";
    target.search = "";
    target.searchParams.set(
      "next",
      request.nextUrl.pathname + request.nextUrl.search,
    );
    const redirect = NextResponse.redirect(target);
    redirect.headers.set("Cache-Control", "private, no-store");
    return secure(redirect);
  }
  const client = createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll(values) {
          values.forEach(({ name, value }) => request.cookies.set(name, value));
          requestHeaders.set("cookie", request.headers.get("cookie") ?? "");
          response = NextResponse.next({
            request: { headers: requestHeaders },
          });
          values.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options),
          );
        },
      },
    },
  );
  const {
    data: { user },
  } = await client.auth.getUser();
  if (!user && request.nextUrl.pathname !== "/account/sign-in") {
    const target = request.nextUrl.clone();
    target.pathname = "/account/sign-in";
    target.search = "";
    target.searchParams.set(
      "next",
      request.nextUrl.pathname + request.nextUrl.search,
    );
    const redirect = NextResponse.redirect(target);
    response.cookies.getAll().forEach((c) => redirect.cookies.set(c));
    redirect.headers.set("Cache-Control", "private, no-store");
    return secure(redirect);
  }
  response.headers.set("Cache-Control", "private, no-store");
  return secure(response);
}
export const config = {
  matcher: [
    "/((?!_next/static|_next/image|brand/|favicon.ico|robots.txt|sitemap.xml).*)",
  ],
};
