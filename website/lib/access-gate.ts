import { NextResponse, type NextRequest } from "next/server";
// Private-site gate: when SITE_ACCESS_KEY is set (production Vercel project
// only), the site asks for the key once and remembers it in a cookie for
// 24 hours, then asks again. The cookie holds a hash, so changing the key
// signs everyone out.
export const ACCESS_COOKIE = "lv_access";
export const ACCESS_PATH = "/_access";
const MAX_AGE = 60 * 60 * 24;
export async function accessToken(key: string) {
  const bytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode("bicycles-access:" + key),
  );
  return Buffer.from(bytes).toString("hex");
}
function safeNext(value: unknown) {
  return typeof value === "string" &&
    value.startsWith("/") &&
    !value.startsWith("//") &&
    !value.startsWith("/\\")
    ? value
    : "/";
}
const escape = (value: string) =>
  value.replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ]!,
  );
function page(nonce: string, next: string, wrong: boolean) {
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>Private preview</title><style nonce="${nonce}">
body{margin:0;min-height:100vh;display:grid;place-items:center;background:#faf7f5;color:#1f1a17;font:16px/1.5 system-ui,sans-serif;padding:16px;box-sizing:border-box}
form{width:100%;max-width:340px;display:grid;gap:12px}h1{font-size:20px;margin:0}p{margin:0;color:#6b625c}
input,button{font:inherit;padding:10px 12px;border-radius:8px;border:1px solid #d6cdc6}button{background:#1f1a17;color:#fff;border:0;cursor:pointer}
.e{color:#b3261e}
@media (prefers-color-scheme:dark){body{background:#171412;color:#f3eee9}p{color:#a89f98}input{background:#221e1b;color:inherit;border-color:#3a332e}button{background:#f3eee9;color:#171412}.e{color:#f2b8b5}}
</style></head><body><form method="post" action="${ACCESS_PATH}"><h1>Bicycles.pk</h1><p>This site is private. Enter the access key to continue.</p>${wrong ? '<p class="e" role="alert">That key is not correct.</p>' : ""}<input type="hidden" name="next" value="${escape(next)}"><input name="key" type="password" autocomplete="current-password" aria-label="Access key" placeholder="Access key" required autofocus><button type="submit">Enter</button></form></body></html>`;
  return new NextResponse(html, {
    status: 401,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "private, no-store",
      "X-Robots-Tag": "noindex, nofollow",
    },
  });
}
// Returns a response to send instead of the page, or null to let it through.
export async function accessGate(
  request: NextRequest,
  key: string,
  nonce: string,
): Promise<NextResponse | null> {
  const expected = await accessToken(key);
  if (request.cookies.get(ACCESS_COOKIE)?.value === expected) return null;
  const { pathname, search } = request.nextUrl;
  if (pathname === ACCESS_PATH && request.method === "POST") {
    const form = await request.formData().catch(() => null);
    const next = safeNext(form?.get("next"));
    const given = form?.get("key");
    if (typeof given !== "string" || (await accessToken(given)) !== expected)
      return page(nonce, next, true);
    const target = request.nextUrl.clone();
    const [path, query = ""] = next.split("?");
    target.pathname = path;
    target.search = query;
    const redirect = NextResponse.redirect(target, 303);
    redirect.cookies.set(ACCESS_COOKIE, expected, {
      httpOnly: true,
      secure: process.env.NODE_ENV !== "development",
      sameSite: "lax",
      path: "/",
      maxAge: MAX_AGE,
    });
    redirect.headers.set("Cache-Control", "private, no-store");
    return redirect;
  }
  return page(nonce, pathname === ACCESS_PATH ? "/" : pathname + search, false);
}
