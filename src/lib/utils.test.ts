import { expect, it } from "vitest";
import { cn } from "./utils";
it("merges conditional classes and resolves utility conflicts", () => {
  expect(cn("px-2 text-sm", false, { "font-bold": true }, "px-6")).toBe(
    "text-sm font-bold px-6",
  );
});
