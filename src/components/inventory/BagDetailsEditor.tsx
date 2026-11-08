import {
  BAG_DETAIL_MAX,
  bagDetailFields,
  combineBagDetails,
  parseBagDetails,
} from "../../../shared/bags";
import type { ProductGuide } from "../../../shared/productGuide";
import { Input } from "../ui/input";
import { useState } from "react";

const hints: Record<string, string> = {
  width: "e.g. 30 cm",
  height: "e.g. 22 cm",
  depth: "e.g. 12 cm",
  strap_drop: "e.g. 55 cm, adjustable",
  closure: "e.g. Magnetic snap, Zip",
  compartments: "e.g. 1 zip pocket, 2 slip pockets",
  fits: "e.g. Phone, wallet, A4 folder",
};

// Measured bag details for the storefront. They are kept as labelled lines in
// the product guide's fit text, alongside any free notes.
export function BagDetailsEditor({
  value,
  onChange,
}: {
  value: ProductGuide;
  onChange: (v: ProductGuide) => void;
}) {
  // Edited locally so spaces typed at the end of a field are not trimmed away
  // before the next character arrives.
  const [{ details, notes }, setDraft] = useState(() =>
    parseBagDetails(value.fit),
  );
  const update = (next: typeof details, nextNotes = notes) => {
    setDraft({ details: next, notes: nextNotes });
    const fit = combineBagDetails(next, nextNotes);
    const updated: ProductGuide = { ...value, fit };
    if (!fit) delete updated.fit;
    onChange(updated);
  };
  return (
    <section
      className="rounded-xl border border-border p-4 space-y-4"
      aria-label="Bag details"
    >
      <h3 className="font-semibold">Bag details</h3>
      <p className="text-sm text-bodytext">
        Measure the bag itself (outside edges, in centimetres). Strap drop is
        from the top of the strap to the top of the bag. Leave unknown details
        blank.
      </p>
      <div className="grid sm:grid-cols-3 gap-3">
        {bagDetailFields.map(([key, label]) => (
          <label
            key={key}
            className={
              "block space-y-1 " +
              (["compartments", "fits"].includes(key) ? "sm:col-span-3" : "")
            }
          >
            {label}
            <Input
              className="input block w-full"
              maxLength={BAG_DETAIL_MAX}
              placeholder={hints[key]}
              value={details[key] ?? ""}
              onChange={(e) => update({ ...details, [key]: e.target.value })}
            />
          </label>
        ))}
      </div>
      <label className="block space-y-1">
        Other notes
        <textarea
          className="textarea block w-full"
          rows={2}
          maxLength={800}
          value={notes}
          onChange={(e) => update(details, e.target.value)}
        />
      </label>
      {(["included", "care"] as const).map((k) => (
        <label className="block space-y-1" key={k}>
          {k === "included"
            ? "What’s included (e.g. dust bag, detachable strap)"
            : "Care instructions"}
          <textarea
            className="textarea block w-full"
            rows={2}
            maxLength={2000}
            value={value[k] ?? ""}
            onChange={(e) => onChange({ ...value, [k]: e.target.value })}
          />
        </label>
      ))}
    </section>
  );
}
