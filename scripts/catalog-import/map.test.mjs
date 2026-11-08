import test from "node:test";
import assert from "node:assert/strict";
import {
  mapProduct,
  sourceIndex,
  paragraphs,
  mapCollection,
  parseFabricCut,
  cleanName,
} from "./map.mjs";
const product = (changes = {}) => ({
  id: 1,
  handle: "navy-shirt",
  title: "Navy shirt",
  product_type: "Shirt",
  vendor: "Owner",
  body_html: "<p>Cotton &amp; craft</p>",
  options: [
    { name: "SIZE", position: 1, values: ["M"] },
    { name: "Colour", position: 2, values: ["Navy"] },
  ],
  variants: [
    {
      id: 11,
      sku: "SHIRT-1",
      price: "4500.50",
      compare_at_price: "5000.00",
      option1: "M",
      option2: "Navy",
    },
  ],
  ...changes,
});
test("garment dimensions, metadata and compare-at; no stock/cost/publication", () => {
  const p = mapProduct(product());
  assert(p.ok);
  assert.equal(p.style.variants[0].size, "M");
  assert.equal(p.style.variants[0].color, "Navy");
  assert.equal(p.style.variants[0].compare_at_price, "5000.00");
  for (const key of ["cost", "opening_stock", "published"])
    assert(!JSON.stringify(p).includes('"' + key + '"'));
});
test("per-metre fabric and cuts map to shared metre stock", () => {
  const p = product({
    product_type: "Shirting Fabric",
    options: [{ name: "Length", position: 1, values: ["Per Meter"] }],
    variants: [{ id: 1, price: "800", option1: "Per Meter" }],
  });
  assert.equal(mapProduct(p).style.unit, "meter");
  p.options[0].values.push("Suit-3.5m");
  p.variants.push({ id: 2, price: "2800", option1: "Suit-3.5m" });
  const mapped = mapProduct(p);
  assert(mapped.ok);
  assert.equal(mapped.style.variants.length, 1);
  assert.deepEqual(mapped.web.fabric_cuts, [{ label: "Suit", meters: 3.5 }]);
});
test("duplicate and missing SKUs become stable handle/options identifiers", () => {
  const a = product(),
    b = product({ id: 2, handle: "white-shirt" }),
    i = sourceIndex([a, b]);
  assert.notEqual(
    mapProduct(a, i).style.variants[0].sku,
    mapProduct(b, i).style.variants[0].sku,
  );
  assert.equal(
    mapProduct(a, i).style.variants[0].sku,
    mapProduct(a, i).style.variants[0].sku,
  );
  a.variants[0].sku = "";
  assert(mapProduct(a).style.variants[0].sku.startsWith("NAVY-SHIRT-M-NAVY"));
});
test("missing price refuses whole product", () => {
  const p = product();
  delete p.variants[0].price;
  assert.equal(mapProduct(p).ok, false);
});
test("92-character handle keeps its URL", () => {
  const p = product({ handle: "a".repeat(92) });
  assert.equal(mapProduct(p).web.slug, p.handle);
});
test("HTML becomes decoded plain paragraphs without active content", () =>
  assert.equal(
    paragraphs(
      '<script>bad()</script><p>Owner &amp; text<br>line</p><p onclick="bad()">Next</p>',
    ),
    "Owner & text\nline\n\nNext",
  ));
test("varying Style is fit; conflicting fit and other varying options refused", () => {
  const p = product();
  p.options.push({ name: "Style", position: 3, values: ["Regular", "Other"] });
  p.variants[0].option3 = "Regular";
  assert.equal(mapProduct(p).style.variants[0].fit, "Regular");
  p.options.push({ name: "Fit", position: 4, values: ["Slim"] });
  assert.equal(mapProduct(p).ok, false);
  p.options = p.options.filter((o) => !["Style", "Fit"].includes(o.name));
  p.options.push({ name: "Odd", position: 3, values: ["A", "B"] });
  assert.equal(mapProduct(p).ok, false);
});
test("duplicate barcode omitted", () => {
  const a = product(),
    b = product({ id: 2, handle: "other" });
  a.variants[0].barcode = b.variants[0].barcode = "123";
  assert.equal(
    mapProduct(a, sourceIndex([a, b])).style.variants[0].barcode,
    undefined,
  );
});
test("collections report missing memberships", () =>
  assert.deepEqual(
    mapCollection(
      {
        handle: "shirts",
        title: "Shirts",
        productIds: [1, 2],
        membershipImported: true,
      },
      new Map([["1", "uuid"]]),
    ),
    {
      slug: "shirts",
      name: "Shirts",
      description: "",
      style_ids: ["uuid"],
      missing: [2],
    },
  ));

test("all source cut formats and typo", () => {
  for (const [text, label, meters] of [
    ["Suit-3.5m", "Suit", 3.5],
    ["Shalwar Kameez 4.5", "Shalwar Kameez", 4.5],
    ["Trouser 1.5m", "Trouser", 1.5],
    ["Wait Coat-1m", "Waist Coat", 1],
    ["Half Meter", "Half Meter", 0.5],
  ])
    assert.deepEqual(parseFabricCut(text), { label, meters });
  for (const text of ["Odd", "Suit-0.3m", "Suit-21m"])
    assert.throws(() => parseFabricCut(text));
});
test("derive absent per-metre price and reject disagreement or rounding", () => {
  const fabric = (variants) =>
    product({
      product_type: "Fabric",
      options: [
        { name: "Length", position: 1, values: variants.map((v) => v.option1) },
      ],
      variants,
    });
  const variants = [
    { id: 1, price: "350", option1: "Suit-3.5m" },
    { id: 2, price: "450", option1: "Shalwar Kameez 4.5" },
  ];
  assert.equal(mapProduct(fabric(variants)).style.variants[0].price, "100.00");
  assert.equal(
    mapProduct(fabric([{ ...variants[0], price: "351" }, variants[1]])).ok,
    false,
  );
  assert.equal(
    mapProduct(fabric([{ id: 3, price: "1", option1: "Suit-3m" }])).ok,
    false,
  );
});
test("explicit rate tolerates at most one rupee mismatch", () => {
  const p = product({
    product_type: "Fabric",
    options: [
      { name: "Length", position: 1, values: ["Per Meter", "Suit-3.5m"] },
    ],
    variants: [
      { id: 1, price: "100", option1: "Per Meter" },
      { id: 2, price: "351", option1: "Suit-3.5m" },
    ],
  });
  assert(mapProduct(p).ok);
  p.variants[1].price = "351.01";
  assert(!mapProduct(p).ok);
});
test("Length is authoritative when source category is mislabeled; Style remains a garment", () => {
  const p = product({
    product_type: "Ties",
    options: [{ name: "Length", position: 1, values: ["Per Meter"] }],
    variants: [{ id: 1, price: "100", option1: "Per Meter" }],
  });
  assert.equal(mapProduct(p).style.kind, "fabric");
  assert.equal(
    mapProduct(product({ product_type: "Suiting Fabric" })).style.kind,
    "garment",
  );
});
test("same cut label at different lengths is preserved with unambiguous labels", () => {
  const p = product({
    product_type: "Fabric",
    options: [
      {
        name: "Length",
        position: 1,
        values: ["Per Meter", "Suit-3.5m", "Suit-4.5m"],
      },
    ],
    variants: [
      { id: 1, price: "100", option1: "Per Meter" },
      { id: 2, price: "350", option1: "Suit-3.5m" },
      { id: 3, price: "450", option1: "Suit-4.5m" },
    ],
  });
  assert.deepEqual(mapProduct(p).web.fabric_cuts, [
    { label: "Suit (3.5 m)", meters: 3.5 },
    { label: "Suit (4.5 m)", meters: 4.5 },
  ]);
});

test("uses central brand and omits source copy and image URLs", () => {
  const previous = ["Law", "rencepur"].join("");
  const p = mapProduct(
    product({
      title: previous + " Navy shirt",
      vendor: previous,
      body_html: "Old descriptive copy",
      images: [{ src: "https://cdn.example/photo.jpg" }],
    }),
  );
  assert.equal(p.style.name, "Navy shirt");
  assert.equal(p.style.brand, "LadyVogue");
  assert.equal(p.style.description, "");
  assert.equal(p.web.web_description, "");
  assert.deepEqual(p.images, []);
  assert.equal(cleanName(previous.toUpperCase() + " Regular"), "Regular");
  const c = mapCollection(
    {
      handle: "fabrics",
      title: previous + " Fabrics",
      description: "Old collection copy",
      membershipImported: true,
      productIds: [],
    },
    new Map(),
  );
  assert.equal(c.name, "Fabrics");
  assert.equal(c.description, "");
});
test("photo import implementation is gone and the old flag fails before any login/write", async () => {
  const { existsSync } = await import("node:fs");
  const { options } = await import("./runtime.mjs");
  assert.equal(existsSync(new URL("./images.mjs", import.meta.url)), false);
  assert.throws(() => options(["--images"]), /disabled/);
});
