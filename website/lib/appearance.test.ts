import { expect, it } from "vitest";
import { appearanceMode, darkAppearance } from "./appearance";
it("accepts saved appearance choices and falls back to the system", () => {
  expect(appearanceMode("light")).toBe("light");
  expect(appearanceMode("dark")).toBe("dark");
  for (const value of [null, "system", "bad"])
    expect(appearanceMode(value)).toBe("system");
});
it("follows system changes only when the system setting is selected", () => {
  expect(darkAppearance("system", true)).toBe(true);
  expect(darkAppearance("system", false)).toBe(false);
  expect(darkAppearance("dark", false)).toBe(true);
  expect(darkAppearance("light", true)).toBe(false);
});
