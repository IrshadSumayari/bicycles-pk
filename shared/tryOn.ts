// 360° try-on data stored on a style (product_styles.try_on). Mirrors
// app_private.valid_try_on: paths always belong to the same style.
export type TryOn = {
  model_path?: string;
  garment_materials?: string[];
  colors?: Record<string, string>;
  // Angle photos per model skin tone, then per colour.
  models?: Partial<Record<ModelTone, Record<string, string[]>>>;
};
// Fixed tones, so a shopper's choice carries across every product.
export const modelTones = [
  { id: "fair", label: "Fair", swatch: "#f1d3bf" },
  { id: "wheatish", label: "Wheatish", swatch: "#d9a77f" },
  { id: "dusky", label: "Dusky", swatch: "#a8714f" },
  { id: "deep", label: "Deep", swatch: "#6e4630" },
] as const;
export type ModelTone = (typeof modelTones)[number]["id"];
const toneIds: readonly string[] = modelTones.map((t) => t.id);
export const tryOnLimits = {
  colors: 30,
  materials: 20,
  minFrames: 4,
  maxFrames: 72,
  modelBytes: 25 * 1024 * 1024,
} as const;
const object = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v);
const uuid = "[0-9a-f-]{36}";
const label = (k: string) => k.trim().length >= 1 && k.trim().length <= 60;
export function tryOnError(value: unknown, styleId: string): string | null {
  if (
    !object(value) ||
    Object.keys(value).some(
      (k) =>
        !["model_path", "garment_materials", "colors", "models"].includes(k),
    )
  )
    return "Use only a 3D model, garment materials, colours and model photos.";
  const prefix = "styles/" + styleId + "/";
  const own = (path: unknown, rest: RegExp) =>
    typeof path === "string" &&
    path.startsWith(prefix) &&
    rest.test(path.slice(prefix.length));
  if (
    "model_path" in value &&
    !own(value.model_path, new RegExp(`^${uuid}\\.glb$`))
  )
    return "Upload the 3D model again for this style.";
  if ("garment_materials" in value) {
    const m = value.garment_materials;
    if (
      !Array.isArray(m) ||
      m.length > tryOnLimits.materials ||
      m.some((n) => typeof n !== "string" || !n.trim() || n.trim().length > 80)
    )
      return "List up to 20 garment material names of at most 80 characters.";
  }
  if ("colors" in value) {
    const c = value.colors;
    if (
      !object(c) ||
      Object.keys(c).length > tryOnLimits.colors ||
      Object.entries(c).some(
        ([k, v]) =>
          !label(k) || typeof v !== "string" || !/^#[0-9a-fA-F]{6}$/.test(v),
      )
    )
      return "Give each colour a hex shade such as #c98a9b.";
  }
  if ("models" in value) {
    const m = value.models;
    if (!object(m) || Object.keys(m).some((k) => !toneIds.includes(k)))
      return "Choose a listed skin tone for each model.";
    const frame = new RegExp(`^spin/${uuid}\\.(webp|jpg)$`);
    for (const sets of Object.values(m))
      if (
        !object(sets) ||
        Object.keys(sets).length > tryOnLimits.colors ||
        Object.entries(sets).some(
          ([k, v]) =>
            !label(k) ||
            !Array.isArray(v) ||
            v.length < tryOnLimits.minFrames ||
            v.length > tryOnLimits.maxFrames ||
            v.some((f) => !own(f, frame)),
        )
      )
        return "Each model needs 4 to 72 photos per colour, uploaded for this style.";
  }
  return null;
}
export function readTryOn(value: unknown, styleId: string): TryOn {
  return tryOnError(value, styleId) === null ? (value as TryOn) : {};
}

// Common lingerie colour names, so swatches work before staff set exact shades.
const named: Record<string, string> = {
  black: "#1d1a1c",
  white: "#f6f3ef",
  ivory: "#f1e8d8",
  cream: "#efe3cc",
  champagne: "#e8d3b5",
  nude: "#d9b29a",
  beige: "#d8c0a3",
  skin: "#dcae94",
  tan: "#c49a74",
  mocha: "#8a6552",
  brown: "#6e4b3a",
  blush: "#efc4c4",
  pink: "#eba8bd",
  rose: "#c98a9b",
  "dusty rose": "#c4949a",
  peach: "#f2b99a",
  coral: "#ec7f6d",
  red: "#b3262f",
  wine: "#6d1f33",
  maroon: "#6a1d2b",
  burgundy: "#7a2034",
  mauve: "#a87c94",
  lilac: "#c6a9d6",
  lavender: "#b9a6dc",
  plum: "#6b3355",
  purple: "#6b3a8a",
  navy: "#1f2a4d",
  blue: "#3a62a8",
  "sky blue": "#8cbbe6",
  teal: "#1f7a7a",
  mint: "#a8dcc5",
  green: "#3f7a4f",
  olive: "#6f7343",
  yellow: "#efce5a",
  grey: "#8b8a8f",
  gray: "#8b8a8f",
  silver: "#c7c7cc",
  gold: "#c9a24b",
};
export function colorHex(name: string, custom?: Record<string, string>) {
  const key = name.trim().toLowerCase();
  const exact = Object.entries(custom ?? {}).find(
    ([k]) => k.trim().toLowerCase() === key,
  );
  if (exact) return exact[1];
  if (named[key]) return named[key];
  const word = Object.keys(named)
    .sort((a, b) => b.length - a.length)
    .find((k) => key.includes(k));
  return word ? named[word] : null;
}
const same = (a: string, b: string) =>
  a.trim().toLowerCase() === b.trim().toLowerCase();
// Tones with angle photos for a colour, in the fixed tone order.
export function tonesFor(tryOn: TryOn, color: string): ModelTone[] {
  return modelTones
    .map((t) => t.id)
    .filter((id) =>
      Object.entries(tryOn.models?.[id] ?? {}).some(
        ([k, v]) => same(k, color) && v.length > 0,
      ),
    );
}
// Angle photos of one model in a colour, matched without regard to case.
export function spinFor(tryOn: TryOn, color: string, tone: ModelTone) {
  return Object.entries(tryOn.models?.[tone] ?? {}).find(([k]) =>
    same(k, color),
  )?.[1];
}
export function hasModelPhotos(tryOn: TryOn) {
  return Object.values(tryOn.models ?? {}).some(
    (sets) => !!sets && Object.keys(sets).length > 0,
  );
}
// Materials that take the selected colour. Without a configured list, names
// that read like fabric are used, so skin, hair and eyes keep their colours.
const fabricWords =
  /garment|fabric|cloth|lace|bra|cup|strap|band|pant|brief|thong|panty|lingerie|satin|silk|mesh|textile/i;
export function isGarmentMaterial(name: string, configured?: string[]) {
  if (configured?.length)
    return configured.some(
      (m) => m.trim().toLowerCase() === name.trim().toLowerCase(),
    );
  return fabricWords.test(name);
}
