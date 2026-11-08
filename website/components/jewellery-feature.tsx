import Image from "next/image";
import Link from "next/link";
import { ArrowUpRight, Sparkles } from "lucide-react";
import { JewelleryArt } from "./jewellery-art";
import { jewelleryPhotos } from "@/lib/jewellery-photos";
export async function JewelleryFeature() {
  const photos = await jewelleryPhotos();
  const photo = photos.Rings ?? Object.values(photos)[0];
  return (
    <aside className="lv-jewellery-feature">
      {photo ? (
        <div className="lv-jewellery-feature-photo">
          <Image
            src={photo}
            alt=""
            fill
            sizes="(max-width:600px) 100vw, 40vw"
          />
        </div>
      ) : (
        <div className="lv-jewellery-feature-art">
          <JewelleryArt kind="rings" />
        </div>
      )}
      <div>
        <p className="lv-eyebrow">
          <Sparkles size={16} /> THE FINISHING TOUCH
        </p>
        <h2>
          A little sparkle.
          <br />
          <em>A lot of you.</em>
        </h2>
        <p>
          Earrings, rings and little details to make your everyday feel your
          own.
        </p>
        <Link className="lv-button" href="/jewellery">
          Discover jewellery <ArrowUpRight size={17} />
        </Link>
      </div>
    </aside>
  );
}
