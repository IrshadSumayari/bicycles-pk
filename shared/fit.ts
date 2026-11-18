// Bike sizing used by the size guide and the "What's my size?" helper.
// General guidance only; each product lists its own sizes.

export type AdultSize = {
  size: string;
  minHeight: number;
  maxHeight: number;
  mtbFrame: string;
  roadFrame: string;
};
export const adultSizes: readonly AdultSize[] = [
  { size: "XS", minHeight: 148, maxHeight: 158, mtbFrame: '13–14"', roadFrame: "47–49 cm" },
  { size: "S", minHeight: 158, maxHeight: 168, mtbFrame: '15–16"', roadFrame: "50–52 cm" },
  { size: "M", minHeight: 168, maxHeight: 178, mtbFrame: '17–18"', roadFrame: "53–55 cm" },
  { size: "L", minHeight: 178, maxHeight: 188, mtbFrame: '19–20"', roadFrame: "56–58 cm" },
  { size: "XL", minHeight: 188, maxHeight: 198, mtbFrame: '21–22"', roadFrame: "59–61 cm" },
];

export type KidsSize = {
  wheel: string;
  minAge: number;
  maxAge: number;
  minHeight: number;
  maxHeight: number;
};
export const kidsSizes: readonly KidsSize[] = [
  { wheel: '10–12"', minAge: 2, maxAge: 4, minHeight: 85, maxHeight: 100 },
  { wheel: '14"', minAge: 3, maxAge: 5, minHeight: 95, maxHeight: 110 },
  { wheel: '16"', minAge: 4, maxAge: 6, minHeight: 105, maxHeight: 120 },
  { wheel: '20"', minAge: 6, maxAge: 9, minHeight: 115, maxHeight: 135 },
  { wheel: '24"', minAge: 8, maxAge: 12, minHeight: 130, maxHeight: 150 },
];

// Within this many cm of a size boundary, both sizes are suggested.
const BETWEEN_CM = 2;

export type AdultFit = {
  size: AdultSize;
  alternative: AdultSize | null;
  // From inseam: mountain/hybrid frame in inches, road frame in cm.
  mtbFrameFromInseam: number | null;
  roadFrameFromInseam: number | null;
};

export function adultFit(heightCm: number, inseamCm?: number | null): AdultFit | null {
  if (!Number.isFinite(heightCm) || heightCm < 130 || heightCm > 220) return null;
  const first = adultSizes[0], last = adultSizes[adultSizes.length - 1];
  const size =
    heightCm < first.minHeight ? first
    : heightCm >= last.maxHeight ? last
    : adultSizes.find((s) => heightCm >= s.minHeight && heightCm < s.maxHeight)!;
  const i = adultSizes.indexOf(size);
  const alternative =
    heightCm - size.minHeight < BETWEEN_CM && i > 0 ? adultSizes[i - 1]
    : size.maxHeight - heightCm <= BETWEEN_CM && i < adultSizes.length - 1 ? adultSizes[i + 1]
    : null;
  const inseam = inseamCm && Number.isFinite(inseamCm) && inseamCm >= 50 && inseamCm <= 110 ? inseamCm : null;
  return {
    size,
    alternative,
    mtbFrameFromInseam: inseam ? Math.round(inseam * 0.226 * 2) / 2 : null,
    roadFrameFromInseam: inseam ? Math.round(inseam * 0.67) : null,
  };
}

// By height when given (closest to the middle of the range), otherwise by age.
export function kidsFit(heightCm?: number | null, ageYears?: number | null): KidsSize | null {
  const height = heightCm && Number.isFinite(heightCm) ? heightCm : null;
  const age = ageYears && Number.isFinite(ageYears) ? ageYears : null;
  const pick = (value: number, min: (s: KidsSize) => number, max: (s: KidsSize) => number) => {
    const fits = kidsSizes.filter((s) => value >= min(s) && value <= max(s));
    if (!fits.length) return null;
    return fits.reduce((best, s) =>
      Math.abs(value - (min(s) + max(s)) / 2) < Math.abs(value - (min(best) + max(best)) / 2) ? s : best,
    );
  };
  if (height) return pick(height, (s) => s.minHeight, (s) => s.maxHeight);
  if (age) return pick(age, (s) => s.minAge, (s) => s.maxAge);
  return null;
}

const numbers = (text: string) => (text.match(/\d+(\.\d+)?/g) ?? []).map(Number);

// Which of a product's sizes matches a recommendation: the size letter, the
// frame size in inches or cm, or the wheel size.
export function matchProductSize(
  productSizes: readonly string[],
  fit: { size?: string; frames?: readonly string[]; wheel?: string },
): string | null {
  const clean = productSizes.filter(Boolean);
  if (fit.size) {
    const exact = clean.find((s) => s.trim().toUpperCase() === fit.size!.toUpperCase());
    if (exact) return exact;
  }
  // "53–55 cm" means 53, 54 or 55.
  const span = (text: string) => {
    const [a, b] = numbers(text);
    if (b === undefined || b <= a || b - a > 10) return numbers(text);
    return Array.from({ length: Math.floor(b - a) + 1 }, (_, i) => a + i);
  };
  const wanted = [...(fit.frames ?? []), ...(fit.wheel ? [fit.wheel] : [])].flatMap(span);
  if (!wanted.length) return null;
  return clean.find((s) => numbers(s).some((n) => wanted.includes(n))) ?? null;
}
