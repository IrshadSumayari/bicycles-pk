export const lingerieOptions = {
  product_type: [
    ["everyday", "Everyday bra"],
    ["t_shirt", "T-shirt bra"],
    ["bralette", "Bralette"],
    ["sports", "Sports bra"],
    ["nursing", "Nursing bra"],
    ["minimizer", "Minimizer bra"],
    ["push_up", "Push-up bra"],
    ["strapless", "Strapless bra"],
    ["brief", "Briefs"],
    ["thong", "Thong"],
    ["boyshort", "Boyshorts"],
    ["pyjama_set", "Pyjama set"],
    ["nightdress", "Nightdress"],
    ["robe", "Robe"],
    ["shapewear", "Shapewear"],
    ["camisole", "Camisole"],
    ["matching_set", "Matching set"],
  ],
  padding: [
    ["none", "Non-padded"],
    ["light", "Lightly padded"],
    ["padded", "Padded"],
    ["removable", "Removable pads"],
  ],
  wire: [
    ["wireless", "Wireless"],
    ["underwired", "Underwired"],
  ],
  coverage: [
    ["full", "Full coverage"],
    ["medium", "Medium coverage"],
    ["low", "Low coverage"],
  ],
} as const;
export type LingerieOptionKey = keyof typeof lingerieOptions;
export type LingerieAttributes = Partial<
  Record<LingerieOptionKey | "composition" | "sizing_system", string>
>;
export const lingerieFilterLabels = {
  product_type: "Product type",
  padding: "Padding",
  wire: "Wire / support",
  coverage: "Coverage",
  material: "Material",
  sizing_system: "Sizing system",
  band: "Band",
  cup: "Cup",
} as const;
export type LingerieFilterKey = keyof typeof lingerieFilterLabels;
export const lingerieFilterKeys = Object.keys(
  lingerieFilterLabels,
) as (keyof typeof lingerieFilterLabels)[];
export function lingerieValueLabel(key: string, value: string): string {
  const options = lingerieOptions[key as LingerieOptionKey] as
    readonly (readonly [string, string])[] | undefined;
  return options?.find(([code]) => code === value)?.[1] ?? value;
}
export function braMetadataError(
  band: string | undefined,
  cup: string | undefined,
  system: string | undefined,
): string | null {
  const b = band?.trim() ?? "",
    c = cup?.trim() ?? "";
  if (!b && !c) return null;
  if (!/^\d{2,3}$/.test(b) || !/^[A-Z]{1,3}$/.test(c))
    return "Enter both the supplier band (2–3 digits) and uppercase cup label, or leave both blank.";
  if (!system?.trim())
    return "Enter the supplier sizing system before adding band and cup labels.";
  return null;
}
