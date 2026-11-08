import {
  BRA_BANDS,
  BRA_CUPS,
  braSizes,
  LETTER_SIZES,
  setSizes,
  type LingerieKind,
} from "../../lib/lingerieCatalog";
import { useState } from "react";

function Choices({
  legend,
  values,
  selected,
  onToggle,
}: {
  legend: string;
  values: string[];
  selected: string[];
  onToggle: (value: string) => void;
}) {
  return (
    <fieldset className="mb-3">
      <legend className="text-sm font-medium mb-2">{legend}</legend>
      <div className="flex flex-wrap gap-2">
        {values.map((value) => (
          <button
            type="button"
            key={value}
            aria-pressed={selected.includes(value)}
            onClick={() => onToggle(value)}
            className={`btn btn-sm ${selected.includes(value) ? "btn-primary" : "btn-secondary"}`}
          >
            {value}
          </button>
        ))}
      </div>
    </fieldset>
  );
}

// Size shortcuts for the kind of lingerie being added. Unknown kind shows
// everything. Sets pair bra sizes with panty sizes ("34B / M").
export function LingerieSizeBuilder({
  onAdd,
  kind,
}: {
  onAdd: (sizes: string[]) => void;
  kind: LingerieKind | null;
}) {
  const [bands, setBands] = useState<string[]>([]);
  const [cups, setCups] = useState<string[]>([]);
  const [bottoms, setBottoms] = useState<string[]>([]);
  const toggle = (values: string[], value: string) =>
    values.includes(value)
      ? values.filter((v) => v !== value)
      : [...values, value];
  const showBra = !kind || kind === "bra" || kind === "set";
  const bras = braSizes(bands, cups);

  if (kind === "set") {
    const sizes = setSizes(bras, bottoms);
    return (
      <details open className="rounded-xl border border-border bg-card p-4">
        <summary className="cursor-pointer font-medium text-link">
          Bra &amp; panty set sizes
        </summary>
        <p className="text-sm text-bodytext my-3">
          Pick the bra sizes and the panty sizes in this set. Each pair becomes
          one size, e.g. <strong>34B / M</strong>, with its own SKU and stock.
          Remove any pairs you don&apos;t stock from the selected sizes below.
        </p>
        <Choices legend="Bra band" values={BRA_BANDS} selected={bands} onToggle={(v) => setBands(toggle(bands, v))} />
        <Choices legend="Bra cup" values={BRA_CUPS} selected={cups} onToggle={(v) => setCups(toggle(cups, v))} />
        <Choices legend="Panty size" values={LETTER_SIZES} selected={bottoms} onToggle={(v) => setBottoms(toggle(bottoms, v))} />
        {(bands.length > 0) !== (cups.length > 0) && (
          <p role="status" className="text-sm text-warning mb-2">
            Choose both a band and a cup for the bra size.
          </p>
        )}
        <button
          type="button"
          className="btn btn-secondary btn-sm"
          disabled={!sizes.length || (bands.length > 0) !== (cups.length > 0)}
          onClick={() => onAdd(sizes)}
        >
          Use {sizes.length} set size{sizes.length === 1 ? "" : "s"}
          {sizes.length > 0 && sizes.length <= 4 ? `: ${sizes.join(", ")}` : ""}
        </button>
      </details>
    );
  }

  return (
    <details open={!!kind} className="rounded-xl border border-border bg-card p-4">
      <summary className="cursor-pointer font-medium text-link">
        LadyVogue size shortcuts
      </summary>
      <p className="text-sm text-bodytext my-3">
        Use the sizes printed on your supplier labels. Band/cup labels are not
        converted between sizing systems. Custom sizes can be entered below.
      </p>
      {showBra && (
        <>
          <Choices legend="Bra band" values={BRA_BANDS} selected={bands} onToggle={(v) => setBands(toggle(bands, v))} />
          <Choices legend="Cup" values={BRA_CUPS} selected={cups} onToggle={(v) => setCups(toggle(cups, v))} />
          <button
            type="button"
            className="btn btn-secondary btn-sm"
            disabled={!bras.length}
            onClick={() => onAdd(bras)}
          >
            Use {bras.length} bra sizes
          </button>
        </>
      )}
      <fieldset className={showBra ? "mt-4" : ""}>
        <legend className="text-sm font-medium mb-2">
          {kind === "bra" ? "Letter sizes (bralettes, sports bras)" : kind ? "Letter sizes" : "Panties, nightwear and other letter sizes"}
        </legend>
        <div className="flex flex-wrap gap-2">
          {LETTER_SIZES.map((size) => (
            <button
              type="button"
              key={size}
              className="btn btn-secondary btn-sm"
              onClick={() => onAdd([size])}
            >
              Add {size}
            </button>
          ))}
        </div>
      </fieldset>
    </details>
  );
}
