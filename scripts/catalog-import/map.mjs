import { readFileSync } from "node:fs";
const brand = JSON.parse(
  readFileSync(
    new URL("../../website/content/brand.json", import.meta.url),
    "utf8",
  ),
);
export const cleanName = (value) =>
  String(value ?? "")
    .replace(/law(?:rence)pur/gi, "")
    .replace(/\s+/g, " ")
    .trim();
import { createHash } from "node:crypto";

import sanitizeHtml from "sanitize-html";

import he from "he";

export function paragraphs(html = "") {
  const clean = sanitizeHtml(String(html), {
    allowedTags: ["p", "br", "div", "li", "h1", "h2", "h3"],

    allowedAttributes: {},

    nonTextTags: [
      "script",

      "style",

      "iframe",

      "form",

      "svg",

      "noscript",

      "template",
    ],
  });

  return he

    .decode(
      clean

        .replace(/<br\s*\/?\s*>/gi, "\n")

        .replace(/<\/(?:p|div|li|h[123])>/gi, "\n\n")

        .replace(/<[^>]*>/g, ""),
    )

    .replace(/[ \t]+/g, " ")

    .replace(/ *\n */g, "\n")

    .replace(/\n{3,}/g, "\n\n")

    .trim();
}

const key = (v) =>
  String(v ?? "")
    .trim()

    .toUpperCase();

export function sourceIndex(products) {
  const skus = new Map(),
    barcodes = new Map(),
    handles = new Map();

  for (const p of products) {
    handles.set(p.handle, (handles.get(p.handle) ?? 0) + 1);

    for (const v of p.variants ?? [])
      for (const [field, map] of [
        ["sku", skus],

        ["barcode", barcodes],
      ]) {
        const value = key(v[field]);

        if (value) map.set(value, (map.get(value) ?? 0) + 1);
      }
  }

  return { skus, barcodes, handles };
}

function money(value, field) {
  if (
    value == null ||
    !/^\d+(?:\.\d{1,2})?$/.test(String(value)) ||
    Number(value) > 999999999999.99
  )
    throw Error("Missing or invalid " + field);

  return String(value);
}

const slug = (v) =>
  String(v)
    .normalize("NFKD")

    .toLowerCase()

    .replace(/[^a-z0-9]+/g, "-")

    .replace(/^-|-$/g, "");

export function mapProduct(p, index = sourceIndex([p])) {
  const handle = p.handle,
    code = key(handle),
    warnings = [];

  try {
    if (
      !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(handle ?? "") ||
      handle.length > 120 ||
      index.handles.get(handle) !== 1
    )
      throw Error("Invalid, duplicate or over-120-character handle");

    if (!cleanName(p.title) || cleanName(p.title).length > 150)
      throw Error("Missing title or web title exceeds 150 characters");

    if (!p.variants?.length) throw Error("No variants");

    const options = p.options ?? [],
      length = options.find((o) => o.name.trim().toLowerCase() === "length"),
      fabric = !!length;

    let sourceVariants = p.variants,
      fabricCuts = [];

    if (fabric) {
      if (!length || options.some((o) => o !== length && o.values.length > 1))
        throw Error("Fabric requires one Length dimension");

      const per = p.variants.filter((v) =>
        /^per\s+met(?:er|re)$/i.test(
          String(v["option" + length.position]).trim(),
        ),
      );

      if (per.length > 1) throw Error("Multiple Per Meter variants");

      const cuts = p.variants
        .filter((v) => !per.includes(v))
        .map((v) => ({ v, ...parseFabricCut(v["option" + length.position]) }));

      let rate = per.length
        ? Number(money(per[0].price, "per-metre price"))
        : null;

      if (rate === null) {
        const rates = cuts.map(
          (c) => Number(money(c.v.price, "cut price")) / c.meters,
        );

        if (
          !rates.length ||
          rates.some(
            (n) =>
              Math.abs(n * 100 - Math.round(n * 100)) > 0.000001 ||
              Math.abs(n - rates[0]) > 0.000001,
          )
        )
          throw Error("Cannot derive an exact common per-metre price");

        rate = Math.round(rates[0] * 100) / 100;
      }

      if (
        cuts.some(
          (c) =>
            Math.abs(Number(money(c.v.price, "cut price")) - c.meters * rate) >
            1.000001,
        )
      )
        throw Error("Cut price differs from metres × per-metre price");

      fabricCuts = cuts.map(({ label, meters }) => ({ label, meters }));

      // Preserve distinct lengths with the same garment label, including typo-normalised labels.
      const repeated = new Set(
        fabricCuts
          .filter(
            (c) =>
              fabricCuts.filter((other) => other.label === c.label).length > 1,
          )
          .map((c) => c.label),
      );
      fabricCuts = fabricCuts.map((c) =>
        repeated.has(c.label)
          ? { ...c, label: `${c.label} (${c.meters} m)` }
          : c,
      );
      if (
        fabricCuts.some((c) => c.label.length > 40) ||
        fabricCuts.length > 12 ||
        new Set(fabricCuts.map((c) => c.label)).size !== fabricCuts.length
      )
        throw Error("More than 12 cuts or duplicate cut labels");

      sourceVariants = [
        {
          ...(per[0] ?? cuts[0].v),
          price: rate.toFixed(2),
          compare_at_price: per[0]?.compare_at_price ?? null,

          ["option" + length.position]: "Per Meter",
        },
      ];
    } else if (length)
      throw Error("Length option on non-fabric needs owner mapping");

    const dimensions = new Map(),
      ignored = [];

    for (const o of options) {
      const name = o.name.trim().toLowerCase(),
        dimension = {
          size: "size",

          color: "color",

          colour: "color",

          fit: "fit",

          ...(name === "style" && o.values.length > 1 ? { style: "fit" } : {}),
        }[name];

      if (dimension) {
        if ([...dimensions.values()].includes(dimension))
          throw Error("Duplicate dimension " + dimension);

        dimensions.set(o.position, dimension);
      } else if (name !== "length") {
        if (o.values.length !== 1)
          throw Error("Varying unsupported option: " + o.name);

        ignored.push(o.name);
      }
    }

    if (ignored.length)
      warnings.push("Constant options omitted: " + ignored.join(", "));

    const seen = new Set();

    const variants = sourceVariants.map((v) => {
      const row = {
        sku: "",

        price: money(v.price, "price"),

        compare_at_price:
          v.compare_at_price == null
            ? null
            : money(v.compare_at_price, "compare-at price"),

        size: null,

        color: null,

        fit: null,

        active: true,
      };

      for (const [position, dimension] of dimensions) {
        const value = v["option" + position];

        if (value == null || !String(value).trim())
          throw Error("Missing " + dimension + " for variant " + v.id);

        row[dimension] = cleanName(value);
        if (!row[dimension])
          throw Error("Missing cleaned variant " + dimension);
      }

      const tuple = [row.size, row.color, row.fit].map(key).join("|");

      if (seen.has(tuple))
        throw Error(
          "Options collapse into duplicate POS size/color/fit combinations",
        );

      seen.add(tuple);

      const original = key(v.sku),
        optionText = options

          .map((o) => v["option" + o.position])

          .filter(Boolean)

          .join("-");

      row.sku =
        original && index.skus.get(original) === 1
          ? original
          : key(
              slug(handle + "-" + optionText).slice(0, 190) +
                "-" +
                createHash("sha256")
                  .update(handle + "|" + optionText + "|" + v.id)

                  .digest("hex")

                  .slice(0, 10),
            );

      const barcode = key(v.barcode);

      if (barcode && index.barcodes.get(barcode) === 1) row.barcode = barcode;
      else if (barcode)
        warnings.push("Duplicate barcode omitted for variant " + v.id);

      return row;
    });

    const description = "";

    if (description.length > 5000)
      throw Error("Description exceeds 5000 characters; owner edit required");

    if (new Set(p.variants.map((v) => v.taxable !== false)).size > 1)
      throw Error("Mixed tax flags cannot be represented by one POS style");

    return {
      ok: true,

      handle,

      code,

      sourceId: String(p.id),

      warnings,

      style: {
        code,

        name: cleanName(p.title),

        kind: fabric ? "fabric" : "garment",

        unit: fabric ? "meter" : "piece",

        category: p.product_type || null,

        brand: brand.name,

        description,

        taxable: p.variants.every((v) => v.taxable !== false),

        variants,
      },

      web: {
        ...(fabric ? { fabric_cuts: fabricCuts } : {}),

        slug: handle,

        web_title: cleanName(p.title),

        web_description: description,
      },

      images: [],
    };
  } catch (e) {
    return {
      ok: false,

      handle,

      code,

      sourceId: String(p.id),

      variants: p.variants?.length ?? 0,

      problem: e.message,
    };
  }
}

export function mapCollection(c, styles) {
  if (
    !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(c.handle ?? "") ||
    !cleanName(c.title) ||
    c.membershipImported !== true
  )
    throw Error("Collection handle/title/membership is not authoritative");

  return {
    slug: c.handle,

    name: cleanName(c.title),

    description: "",

    style_ids: c.productIds.map((id) => styles.get(String(id))).filter(Boolean),

    missing: c.productIds.filter((id) => !styles.has(String(id))),
  };
}

export function parseFabricCut(value) {
  const text = String(value ?? "")
    .trim()
    .replace(/Wait Coat/gi, "Waist Coat");

  if (/^half meter:?$/i.test(text)) return { label: "Half Meter", meters: 0.5 };

  const match = text.match(/^(.+?)(?:\s*-\s*|\s+)(\d+(?:\.\d+)?)\s*m?$/i);

  if (!match) throw Error("Unrecognised fabric cut: " + text);

  const label = match[1].trim(),
    meters = Number(match[2]);

  if (
    !label ||
    label.length > 40 ||
    meters < 0.25 ||
    meters > 20 ||
    !Number.isInteger(meters * 4)
  )
    throw Error("Invalid fabric cut: " + text);

  return { label, meters };
}
