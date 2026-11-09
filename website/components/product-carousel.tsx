"use client";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { useRef, type ReactNode } from "react";
// Horizontal, swipeable row with previous/next buttons for pointer users.
export function ProductCarousel({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
  const track = useRef<HTMLDivElement>(null);
  const scroll = (direction: 1 | -1) => {
    const el = track.current;
    if (el)
      el.scrollBy({ left: direction * el.clientWidth * 0.8, behavior: "smooth" });
  };
  return (
    <div className="lv-carousel">
      <div
        ref={track}
        className="lv-carousel-track"
        role="region"
        aria-label={label}
        tabIndex={0}
      >
        {children}
      </div>
      <div className="lv-carousel-controls">
        <button type="button" aria-label={"Previous " + label} onClick={() => scroll(-1)}>
          <ChevronLeft size={20} />
        </button>
        <button type="button" aria-label={"Next " + label} onClick={() => scroll(1)}>
          <ChevronRight size={20} />
        </button>
      </div>
    </div>
  );
}
