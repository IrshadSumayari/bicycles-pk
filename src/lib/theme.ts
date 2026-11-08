export const presets = [
  "BLUE_THEME",
  "AQUA_THEME",
  "PURPLE_THEME",
  "GREEN_THEME",
  "CYAN_THEME",
  "ORANGE_THEME",
] as const;
export type ThemeSettings = {
  mode: "light" | "dark" | "system";
  preset: (typeof presets)[number];
  sidebar: "full" | "mini";
};
export const defaultTheme: ThemeSettings = {
  mode: "system",
  preset: "BLUE_THEME",
  sidebar: "full",
};
export function parseTheme(raw: string | null): ThemeSettings {
  try {
    const value: unknown = JSON.parse(raw ?? "null");
    if (!value || typeof value !== "object") return { ...defaultTheme };
    const v = value as Record<string, unknown>;
    if (
      !["light", "dark", "system"].includes(String(v.mode)) ||
      !presets.includes(v.preset as ThemeSettings["preset"]) ||
      !["full", "mini"].includes(String(v.sidebar))
    )
      return { ...defaultTheme };
    return v as ThemeSettings;
  } catch {
    return { ...defaultTheme };
  }
}
export function isDark(mode: ThemeSettings["mode"], systemDark: boolean) {
  return mode === "dark" || (mode === "system" && systemDark);
}
