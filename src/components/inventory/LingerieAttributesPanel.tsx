import { Input } from "@/components/ui/input";
import {
  lingerieOptions,
  lingerieFilterLabels,
  type LingerieAttributes,
  type LingerieOptionKey,
} from "../../../shared/lingerie";
import {
  LINGERIE_FIELDS,
  LINGERIE_TYPES,
  type LingerieKind,
} from "../../lib/lingerieCatalog";
// Shows only the details that apply to the kind of product. A field that
// already has a saved value always stays visible so it can be seen or cleared.
export function LingerieAttributesPanel({
  value,
  onChange,
  kind,
}: {
  value: LingerieAttributes;
  onChange: (next: LingerieAttributes) => void;
  kind: LingerieKind | null;
}) {
  function update(key: keyof LingerieAttributes, text: string) {
    const next = { ...value };
    if (text) next[key] = text;
    else delete next[key];
    onChange(next);
  }
  const shows = (key: keyof LingerieAttributes) =>
    !kind || LINGERIE_FIELDS[kind].includes(key) || !!value[key];
  const choices = (key: LingerieOptionKey) =>
    lingerieOptions[key].filter(
      ([code]) =>
        key !== "product_type" ||
        !kind ||
        LINGERIE_TYPES[kind].includes(code) ||
        value.product_type === code,
    );
  const title =
    kind === "set"
      ? "Bra & panty set details"
      : kind === "bra"
        ? "Bra details"
        : kind === "bottom"
          ? "Panty details"
          : "Lingerie product details";
  return (
    <section
      aria-label={title}
      className="rounded-xl border border-border p-4 space-y-4"
    >
      <h3 className="font-semibold">{title}</h3>
      <p className="text-sm text-bodytext">
        Use supplier-confirmed details. Leave unknown values blank. Existing
        size labels and stock variants stay unchanged.
      </p>
      <div className="grid sm:grid-cols-2 gap-4">
        {(Object.keys(lingerieOptions) as LingerieOptionKey[]).filter(shows).map((key) => (
          <label className="block text-sm space-y-1" key={key}>
            {lingerieFilterLabels[key]}
            <select
              className="select block w-full"
              value={value[key] ?? ""}
              onChange={(e) => update(key, e.target.value)}
            >
              <option value="">Not specified</option>
              {choices(key).map(([code, label]) => (
                <option key={code} value={code}>
                  {label}
                </option>
              ))}
            </select>
          </label>
        ))}
        {shows("sizing_system") && <label className="block text-sm space-y-1">
          Supplier sizing system
          <Input
            className="input"
            maxLength={60}
            placeholder="e.g. UK, EU, US, or supplier chart name"
            value={value.sizing_system ?? ""}
            onChange={(e) => update("sizing_system", e.target.value)}
          />
        </label>}
        <label className="block text-sm space-y-1">
          Material composition
          <Input
            className="input"
            maxLength={500}
            placeholder="Copy confirmed fibre percentages from the label"
            value={value.composition ?? ""}
            onChange={(e) => update("composition", e.target.value)}
          />
        </label>
      </div>
      {shows("sizing_system") && <p className="text-sm text-bodytext">
        For bras, enter band and cup labels on each variant only when verified
        against this sizing system. DD and E remain separate labels; no
        automatic conversion is applied.
      </p>}
    </section>
  );
}
