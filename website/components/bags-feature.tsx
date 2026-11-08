import Image from "next/image";
import Link from "next/link";
import { ArrowUpRight, ShoppingBag } from "lucide-react";
import { BagArt } from "./bag-art";
import { bagCatalog } from "@/lib/bag-catalog";
export async function BagsFeature() {
  const { photos } = await bagCatalog();
  const photo =
    photos["Tote Bags"] ?? photos["Shoulder Bags"] ?? Object.values(photos)[0];
  return (
    <aside className="lv-bags-feature">
      <div>
        <p className="lv-eyebrow">
          <ShoppingBag size={16} /> NEW: BAGS & HANDBAGS
        </p>
        <h2>
          The bag that goes
          <br />
          <em>everywhere you do.</em>
        </h2>
        <p>
          Totes, crossbodies, clutches and wallets, measured and described so
          you know exactly what fits.
        </p>
        <Link className="lv-button" href="/bags">
          Discover bags <ArrowUpRight size={17} />
        </Link>
      </div>
      {photo ? (
        <div className="lv-bags-feature-photo">
          <Image
            src={photo}
            alt=""
            fill
            sizes="(max-width:600px) 100vw, 40vw"
          />
        </div>
      ) : (
        <div className="lv-bags-feature-art">
          <BagArt kind="tote-bags" />
        </div>
      )}
    </aside>
  );
}
