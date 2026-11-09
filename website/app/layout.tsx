import { brand, storeJsonLd } from "@/lib/brand";
import { jsonScript } from "@/lib/helpers";
import type { Metadata } from "next";
import localFont from "next/font/local";
import { headers } from "next/headers";
import { ConsentBanner } from "@/components/consent-banner";
import { Header } from "@/components/header";
import { Footer } from "@/components/footer";
import { StoreProvider } from "@/components/store-provider";
import { catalog, safeCatalog } from "@/lib/catalog";
import { buildNavigation } from "@/lib/navigation";
import { siteUrl } from "@/lib/helpers";
import "./globals.css";
import "../styles/storefront.css";
import "../styles/landing.css";
import "../styles/listing.css";
import "../styles/pdp.css";
import "../styles/shopping.css";
import "../styles/mobile.css";
import "../styles/account.css";
import "../styles/fit-guidance.css";
const poppins = localFont({
  src: [
    { path: "../public/brand/poppins-400.woff2", weight: "400" },
    { path: "../public/brand/poppins-500.woff2", weight: "500" },
    { path: "../public/brand/poppins-600.woff2", weight: "600" },
    { path: "../public/brand/poppins-700.woff2", weight: "700" },
  ],
  variable: "--font-poppins",
  display: "swap",
});
const montserrat = localFont({
  src: "../node_modules/@fontsource-variable/montserrat/files/montserrat-latin-wght-normal.woff2",
  variable: "--font-montserrat",
  display: "swap",
  weight: "100 900",
});
export const metadata: Metadata = {
  robots: { index: false, follow: false },
  metadataBase: new URL(siteUrl()),
  title: {
    default: `${brand.name} | Bicycles, Kids Bikes, Sports Bikes & Accessories in Pakistan`,
    template: `%s | ${brand.name}`,
  },
  description: `Shop city bikes, kids bicycles, sports bikes, e-bikes, accessories and parts at ${brand.name}, Pakistan.`,
  icons: { icon: "/brand/bicycles-icon.svg" },
  openGraph: {
    siteName: brand.name,
    title: brand.name,
    description: brand.tagline,
  },
};
export default async function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const nonce = (await headers()).get("x-nonce") ?? "";
  const navigation = buildNavigation(
    await safeCatalog(catalog.collections, []),
  );
  return (
    <html
      lang="en"
      data-scroll-behavior="smooth"
      className={`${poppins.variable} ${montserrat.variable}`}
      suppressHydrationWarning
    >
      <body>
        <script
          nonce={nonce}
          dangerouslySetInnerHTML={{
            __html: `try{var m=localStorage.getItem('storefront-appearance');var d=m==='dark'||(m!=='light'&&matchMedia('(prefers-color-scheme: dark)').matches);document.documentElement.classList.toggle('dark',d);document.documentElement.style.colorScheme=d?'dark':'light'}catch(e){}`,
          }}
        />
        <script
          nonce={nonce}
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: jsonScript(storeJsonLd(siteUrl())),
          }}
        />
        <StoreProvider>
          <Header nav={navigation.map((item) => ({ ...item, children: [] }))} />
          <main id="MainContent">{children}</main>
          <Footer navigation={navigation} />
          <ConsentBanner nonce={nonce} />
        </StoreProvider>
      </body>
    </html>
  );
}
