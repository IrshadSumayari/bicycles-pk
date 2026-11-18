"use client";
import { useId, useState } from "react";
import { adultFit, kidsFit, matchProductSize } from "../../shared/fit";
type Mode = "adult" | "kids";
const toNumber = (text: string) => (text.trim() ? Number(text) : null);
// "What's my size?": rider height (and inseam) for adults, height or age for
// kids. On a product page it also names the matching size and can select it.
export function SizeFinder({
  initialMode = "adult",
  productSizes,
  onPick,
}: {
  initialMode?: Mode;
  productSizes?: readonly string[];
  onPick?: (size: string) => void;
}) {
  const id = useId();
  const [mode, setMode] = useState<Mode>(initialMode);
  const [height, setHeight] = useState("");
  const [inseam, setInseam] = useState("");
  const [age, setAge] = useState("");
  const adult = mode === "adult" ? adultFit(Number(height), toNumber(inseam)) : null;
  const kid = mode === "kids" ? kidsFit(toNumber(height), toNumber(age)) : null;
  const asked = mode === "adult" ? !!height.trim() : !!(height.trim() || age.trim());
  const match =
    productSizes && (adult || kid)
      ? matchProductSize(
          productSizes,
          adult
            ? {
                size: adult.size.size,
                frames: [adult.size.mtbFrame, adult.size.roadFrame],
              }
            : { wheel: kid!.wheel },
        )
      : null;
  const field = (
    label: string,
    value: string,
    set: (v: string) => void,
    unit: string,
    hint?: string,
  ) => (
    <label className="lv-finder-field">
      <span>
        {label}
        {hint && <small> {hint}</small>}
      </span>
      <span className="lv-finder-input">
        <input
          type="number"
          inputMode="decimal"
          min={0}
          value={value}
          onChange={(e) => set(e.target.value)}
        />
        <span aria-hidden="true">{unit}</span>
      </span>
    </label>
  );
  return (
    <div className="lv-finder">
      <div className="lv-finder-modes" role="group" aria-label="Rider">
        {(["adult", "kids"] as const).map((m) => (
          <button
            key={m}
            type="button"
            aria-pressed={mode === m}
            onClick={() => setMode(m)}
          >
            {m === "adult" ? "Adult" : "Kids"}
          </button>
        ))}
      </div>
      <div className="lv-finder-fields">
        {field("Rider height", height, setHeight, "cm")}
        {mode === "adult"
          ? field("Inside leg", inseam, setInseam, "cm", "(optional)")
          : field("Age", age, setAge, "years", "(if height unknown)")}
      </div>
      <div className="lv-finder-result" aria-live="polite" id={id}>
        {!asked ? (
          <p className="muted">
            {mode === "adult"
              ? "Enter the rider’s height to see a frame size."
              : "Enter the child’s height, or their age if you don’t know it."}
          </p>
        ) : adult ? (
          <>
            <p className="lv-finder-size">
              Size <strong>{adult.size.size}</strong>
            </p>
            <p>
              Mountain / hybrid frame {adult.size.mtbFrame} · Road / gravel{" "}
              {adult.size.roadFrame}
            </p>
            {adult.alternative && (
              <p className="muted">
                You’re close to {adult.alternative.size}. Pick the smaller size
                for easier handling or the larger one for a stretched-out
                position.
              </p>
            )}
            {adult.mtbFrameFromInseam && (
              <p className="muted">
                From your inside leg: about {adult.mtbFrameFromInseam}&quot;
                mountain / hybrid or {adult.roadFrameFromInseam} cm road frame.
              </p>
            )}
          </>
        ) : kid ? (
          <>
            <p className="lv-finder-size">
              Wheel <strong>{kid.wheel}</strong>
            </p>
            <p>
              Usually ages {kid.minAge}–{kid.maxAge}, height {kid.minHeight}–
              {kid.maxHeight} cm. Your child should reach the ground with the
              balls of both feet while seated.
            </p>
          </>
        ) : (
          <p className="muted">
            {mode === "adult"
              ? "Enter a height between 130 and 220 cm."
              : "That’s outside our kids sizes. Try the adult sizes."}
          </p>
        )}
        {productSizes && (adult || kid) && (
          <div className="lv-finder-match">
            {match ? (
              <>
                <p>
                  On this bike: <strong>{match}</strong>
                </p>
                {onPick && (
                  <button type="button" onClick={() => onPick(match)}>
                    Select {match}
                  </button>
                )}
              </>
            ) : (
              <p className="muted">
                This bike comes in {productSizes.filter(Boolean).join(", ")}.
                Ask us on WhatsApp and we’ll help you choose.
              </p>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
