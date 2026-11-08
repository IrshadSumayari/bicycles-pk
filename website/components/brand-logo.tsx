import { brand } from "@/lib/brand";
export function BrandLogo() {
  return (
    <span className="lv-wordmark" aria-label={brand.name}>
      Bicycles<span>.pk</span>
      <small>RIDE FURTHER. RIDE BETTER.</small>
    </span>
  );
}
