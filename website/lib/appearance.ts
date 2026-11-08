export type AppearanceMode = "light" | "dark" | "system";
export function appearanceMode(value: string | null): AppearanceMode {
  return value === "light" || value === "dark" ? value : "system";
}
export function darkAppearance(
  mode: AppearanceMode,
  systemDark: boolean,
): boolean {
  return mode === "dark" || (mode === "system" && systemDark);
}
