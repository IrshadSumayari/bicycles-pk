import sanitizeHtml from "sanitize-html";

export function ownerHref(href: string): string {
  if (href.startsWith("#")) return href;
  if (
    href.startsWith("/") &&
    !href.startsWith("//") &&
    !href.includes("\\") &&
    !/[\u0000-\u0020]/.test(href)
  )
    return href;
  try {
    const url = new URL(href);
    return url.protocol === "https:" && !url.username && !url.password
      ? url.href
      : "";
  } catch {
    return "";
  }
}
export function sanitizeContent(html: string): string {
  return sanitizeHtml(html, {
    allowedTags: [
      "div",
      "span",
      "p",
      "br",
      "h2",
      "h3",
      "h4",
      "h5",
      "h6",
      "ul",
      "ol",
      "li",
      "strong",
      "b",
      "em",
      "i",
      "u",
      "s",
      "small",
      "sup",
      "sub",
      "blockquote",
      "hr",
      "a",
      "table",
      "thead",
      "tbody",
      "tfoot",
      "tr",
      "td",
      "th",
      "details",
      "summary",
    ],
    allowedAttributes: {
      a: ["href", "title", "target", "rel"],
      td: ["colspan", "rowspan"],
      th: ["colspan", "rowspan", "scope"],
    },
    allowedSchemes: ["https"],
    allowProtocolRelative: false,
    nonTextTags: [
      "script",
      "style",
      "iframe",
      "object",
      "svg",
      "form",
      "button",
      "select",
      "video",
      "audio",
      "template",
      "noscript",
      "textarea",
    ],
    transformTags: {
      h1: "h2",
      a: (_tag, attrs) => ({
        tagName: "a",
        attribs: {
          href: ownerHref(attrs.href ?? ""),
          ...(attrs.title ? { title: attrs.title } : {}),
          ...(attrs.target === "_blank"
            ? { target: "_blank", rel: "noopener noreferrer" }
            : {}),
        },
      }),
    },
  });
}
