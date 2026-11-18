import "server-only";
import pages from "@/content/pages/index.json";
import { sanitizeContent } from "./contentSanitizer";
export type ContentKind = "pages" | "policies";
export function contentHandles(kind: ContentKind) {
  return pages
    .filter((page) => page.kind === kind)
    .map((page) => ({ handle: page.handle }));
}
export function contentPage(kind: ContentKind, handle: string) {
  const page = pages.find(
    (page) => page.kind === kind && page.handle === handle,
  );
  return page ? { ...page, html: sanitizeContent(page.html) } : null;
}
