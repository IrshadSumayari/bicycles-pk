import { expect, it } from "vitest";
import { ownerHref, sanitizeContent } from "./contentSanitizer";
it("discards scripts, widgets, forms, styles and event handlers", () => {
  const clean = sanitizeContent(
    '<script>alert(1)</script><style>body{color:red}</style><iframe>widget</iframe><form>private form<input /></form><p style="color:red" onclick="alert(1)">Owner text</p><img src="x" onerror="alert(1)" />',
  );
  expect(clean).toBe("<p>Owner text</p>");
});
it("rejects encoded script URLs and keeps safe semantic text", () => {
  expect(
    sanitizeContent(
      '<a href="jav&#x61;script:alert(1)">Text</a><h1>عنوان</h1><strong>Craft</strong>',
    ),
  ).toBe("<a>Text</a><h2>عنوان</h2><strong>Craft</strong>");
});
it("keeps own relative paths and normal HTTPS links without rewriting origins", () => {
  expect(ownerHref("/products/navy-suit?x=1")).toBe("/products/navy-suit?x=1");
  expect(ownerHref("https://example.com/pages/about-us")).toBe(
    "https://example.com/pages/about-us",
  );
  for (const bad of [
    "//example.com/path",
    "http://example.com",
    "data:text/html,bad",
    "mailto:old@example.com",
    "/\\example.com",
    "/path\nredirect",
  ])
    expect(ownerHref(bad)).toBe("");
  expect(
    sanitizeContent('<a href="https://example.com" target="_blank">Visit</a>'),
  ).toContain('rel="noopener noreferrer"');
});
