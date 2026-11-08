import settings from "../content/brand.json";
type Brand = {
  name: string;
  shortName: string;
  tagline: string;
  address: { line1: string; city: string; country: string };
  mapsUrl: string;
  email: string | null;
  phone: string | null;
  whatsapp: string | null;
  social: Record<string, string>;
};
export const brand: Brand = settings;
export const storeAddress = [
  brand.address.line1,
  brand.address.city,
  brand.address.country,
].filter(Boolean).join(", ");
export function storeJsonLd(url: string) {
  return {
    "@context": "https://schema.org",
    "@type": "ClothingStore",
    name: brand.name,
    url,
    image: new URL("/brand/ladyvogue-icon.svg", url).href,
    address: {
      "@type": "PostalAddress",
      streetAddress: brand.address.line1,
      addressLocality: brand.address.city,
      addressCountry: "PK",
    },
    ...(brand.phone ? { telephone: brand.phone } : {}),
    ...(brand.email ? { email: brand.email } : {}),
    ...(Object.keys(brand.social).length
      ? { sameAs: Object.values(brand.social) }
      : {}),
  };
}
