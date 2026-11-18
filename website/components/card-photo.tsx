"use client";
import Image from "next/image";
import { useEffect, useState } from "react";
import { imageUrl } from "@/lib/helpers";

// At most this many angles on a card; larger spin sets are sampled evenly.
const CARD_ANGLES = 8;
// Time each angle stays on screen while the shopper hovers a card.
const ANGLE_MS = 1400;
const SIZES = "(max-width:640px) 46vw,(max-width:1100px) 30vw,25vw";

function sample(paths: string[]) {
  if (paths.length <= CARD_ANGLES) return paths;
  return Array.from(
    { length: CARD_ANGLES },
    (_, i) => paths[Math.floor((i * paths.length) / CARD_ANGLES)],
  );
}

// On hover the card fades to the next angle photo (side, back…) and keeps
// turning slowly; it fades back to the main photo when the pointer leaves.
export function CardPhoto({
  path,
  angles,
  alt,
}: {
  path: string | null;
  angles: string[] | null | undefined;
  alt: string;
}) {
  const src = imageUrl(path);
  const frames = sample(angles ?? [])
    .map((p) => imageUrl(p))
    .filter((u): u is string => !!u);
  // The first angle normally matches the main photo, so hovering starts on
  // the second one.
  const start = frames.length > 1 && frames[0] === src ? 1 : 0;
  const [hovering, setHovering] = useState(false);
  // Angle photos are only requested after the first hover.
  const [loaded, setLoaded] = useState(false);
  const [active, setActive] = useState(start);
  const turns = frames.length > 1;
  useEffect(() => {
    if (!hovering || frames.length < 2) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const timer = setInterval(
      () => setActive((i) => (i + 1) % frames.length),
      ANGLE_MS,
    );
    return () => clearInterval(timer);
  }, [hovering, frames.length]);
  if (!src) return null;
  return (
    <span
      className="lv-card-photo"
      onPointerEnter={(e) => {
        if (!turns || e.pointerType === "touch") return;
        setLoaded(true);
        setActive(start);
        setHovering(true);
      }}
      onPointerLeave={() => setHovering(false)}
    >
      <Image src={src} alt={alt} fill sizes={SIZES} />
      {loaded &&
        frames.map((frame, i) => (
          <Image
            key={frame + i}
            src={frame}
            alt=""
            fill
            sizes={SIZES}
            loading="eager"
            className="lv-card-angle"
            data-active={(hovering && i === active) || undefined}
          />
        ))}
      {hovering && (
        <span className="lv-card-angle-dots" aria-hidden="true">
          {frames.map((frame, i) => (
            <i key={frame + i} data-active={i === active || undefined} />
          ))}
        </span>
      )}
    </span>
  );
}
