import { expect, it } from "vitest";
import { parseTheme, defaultTheme, isDark, presets } from "./theme";
it("defaults safely on missing, broken and invalid persisted data", () => {
  for (const value of [null, "{", "null", "{}", '{"mode":"alien"}'])
    expect(parseTheme(value)).toEqual(defaultTheme);
});
it("accepts every supported preset and keeps device preferences", () => {
  for (const preset of presets) {
    const theme = { mode: "dark", preset, sidebar: "mini" };
    expect(parseTheme(JSON.stringify(theme))).toEqual(theme);
  }
});
it("System follows live media state and explicit choices override it", () => {
  expect(isDark("system", true)).toBe(true);
  expect(isDark("system", false)).toBe(false);
  expect(isDark("light", true)).toBe(false);
  expect(isDark("dark", false)).toBe(true);
});
