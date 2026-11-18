export function posHeaders(template, value) {
  const url = new URL(value);
  const local = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  if (
    url.username ||
    url.password ||
    url.pathname !== "/" ||
    url.search ||
    url.hash ||
    (url.protocol !== "https:" && !(local && url.protocol === "http:"))
  )
    throw new Error("Set VITE_SUPABASE_URL to the exact HTTPS Supabase origin");
  const socket = url.origin.replace(/^http/, "ws");
  return template
    .replaceAll("__SUPABASE_ORIGIN__", url.origin)
    .replaceAll("__SUPABASE_WEBSOCKET__", socket);
}
export function headerLines(rendered) {
  return rendered
    .split(/\r?\n/)
    .filter((l) => /^\s+[^:]+:/.test(l))
    .map((l) => {
      const i = l.indexOf(":");
      return [l.slice(0, i).trim(), l.slice(i + 1).trim()];
    });
}
