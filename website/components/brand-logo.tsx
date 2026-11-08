import { brand } from "@/lib/brand";
export function BrandLogo() {
  return (
    <span className="lv-wordmark" aria-label={brand.name}>
      Lady<span>Vogue</span>
      <small>EVERYDAY, BEAUTIFULLY.</small>
    </span>
  );
}
