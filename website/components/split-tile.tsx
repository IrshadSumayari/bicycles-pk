import Image from "next/image";
import Link from "next/link";
import { ArrowUpRight } from "lucide-react";
import type { ReactNode } from "react";
// Large rounded tile with its title over the photo and a round arrow, used
// in pairs ("Shop Bicycles" / "Shop Accessories").
export function SplitTile({
  title,
  href,
  image,
  icon,
  dark = false,
}: {
  title: string;
  href: string;
  image?: string | null;
  icon?: ReactNode;
  dark?: boolean;
}) {
  return (
    <Link
      href={href}
      className={"lv-split-tile" + (dark || !image ? " is-dark" : "")}
    >
      {image ? (
        <Image
          src={image}
          alt=""
          fill
          sizes="(max-width:760px) 100vw, 50vw"
        />
      ) : (
        <span className="lv-split-tile-art" aria-hidden="true">
          {icon}
        </span>
      )}
      <span className="lv-split-tile-title">{title}</span>
      <span className="lv-split-tile-arrow" aria-hidden="true">
        <ArrowUpRight size={20} />
      </span>
    </Link>
  );
}
