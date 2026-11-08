import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { randomUUID } from "node:crypto";
import { mapProduct, sourceIndex, mapCollection } from "./map.mjs";
import {
  options,
  login,
  pages,
  rpc,
  report,
  saveJson,
  backups,
} from "./runtime.mjs";
export async function importCatalog(o, client) {
  const started = Date.now(),
    products = JSON.parse(
      await readFile(path.join(o.source, "products.json"), "utf8"),
    ),
    collections = JSON.parse(
      await readFile(path.join(o.source, "collections.json"), "utf8"),
    );
  const index = sourceIndex(products),
    mapped = products.map((p) => mapProduct(p, index)),
    rows = [];
  const existing = await pages(
      client,
      "product_styles",
      "id,code,slug,name,kind",
    ),
    byCode = new Map(existing.map((s) => [s.code, s])),
    styleIds = new Map();
  const existingVariants = await pages(
      client,
      "product_variants",
      "style_id,sku",
    ),
    skus = new Map(existingVariants.map((v) => [v.sku, v.style_id]));
  let applied = 0,
    created = 0,
    updated = 0;
  for (const item of mapped) {
    const row = {
      code: item.code,
      handle: item.handle,
      variants: item.ok ? item.style.variants.length : item.variants,
      status: "problem",
      problem: item.problem ?? "",
    };
    rows.push(row);
    if (!item.ok) continue;
    if (applied >= o.limit) {
      row.status = "not_selected";
      continue;
    }
    try {
      let style = byCode.get(item.code);
      const existed = !!style;
      if (style && style.kind !== item.style.kind)
        throw Error(
          "Existing code has a different kind; owner review required",
        );
      if (!style && item.style.variants.some((v) => skus.has(v.sku)))
        throw Error("SKU already exists in the POS; owner review required");
      if (!o.apply) {
        row.status = style ? "would_update_web_only" : "would_create";
        row.problem = item.warnings.join("; ");
        applied++;
        if (style) styleIds.set(item.sourceId, style.id);
        continue;
      }
      if (!style) {
        try {
          const id = await rpc(client, "save_style", {
            p: { ...item.style, request_id: randomUUID() },
          });
          style = { id, code: item.code, kind: item.style.kind };
          created++;
        } catch (e) {
          // A timeout after commit must not issue a second create.
          const recovered = await client
            .from("product_styles")
            .select("id,code,kind")
            .eq("code", item.code)
            .maybeSingle();
          if (recovered.error || !recovered.data) throw e;
          if (recovered.data.kind !== item.style.kind) throw e;
          style = recovered.data;
        }
        byCode.set(item.code, style);
        item.style.variants.forEach((v) => skus.set(v.sku, style.id));
      } else updated++;
      await rpc(client, "save_style_web_details", {
        p_style: style.id,
        p: item.web,
        p_request_id: randomUUID(),
      });
      styleIds.set(item.sourceId, style.id);
      row.status = existed ? "updated_web_only" : "saved_unpublished";
      row.problem = item.warnings.join("; ");
      applied++;
    } catch (e) {
      row.status = "problem";
      row.problem = e.message;
    }
  }
  // Include previously imported products when resuming a limited batch.
  for (const item of mapped)
    if (item.ok && byCode.has(item.code))
      styleIds.set(item.sourceId, byCode.get(item.code).id);
  if (o.apply) {
    const savedCollections = await pages(
        client,
        "collections",
        "id,slug,published,description,hero_image_path,sort_order,starts_at,ends_at",
      ),
      bySlug = new Map(savedCollections.map((c) => [c.slug, c]));
    for (const source of collections) {
      const row = {
        code: "COLLECTION",
        handle: source.handle,
        variants: 0,
        status: "problem",
        problem: "",
      };
      rows.push(row);
      try {
        const c = mapCollection(source, styleIds);
        if (c.missing.length) {
          row.problem =
            c.missing.length +
            " members not imported; collection left unchanged";
          continue;
        }
        const old = bySlug.get(c.slug);
        const saved =
          old ??
          (await rpc(client, "save_collection", {
            p: {
              slug: c.slug,
              name: c.name,
              description: c.description,
              request_id: randomUUID(),
            },
          }));
        await rpc(client, "set_collection_styles", {
          p_collection: saved.id,
          p_style_ids: c.style_ids,
          p_request_id: randomUUID(),
        });
        row.status = "collection_saved";
      } catch (e) {
        row.problem = e.message;
      }
    }
  } else
    for (const c of collections) {
      try {
        mapCollection(
          c,
          new Map(products.map((p) => [String(p.id), "dry-run"])),
        );
      } catch (e) {
        rows.push({
          code: "COLLECTION",
          handle: c.handle,
          variants: 0,
          status: "problem",
          problem: e.message,
        });
      }
    }
  const summary = {
    mode: o.apply ? "apply" : "dry-run",
    products: products.length,
    variants: products.reduce((n, p) => n + p.variants.length, 0),
    collections: collections.length,
    mappable: mapped.filter((p) => p.ok).length,
    productProblems: mapped.filter((p) => !p.ok).length,
    selected: applied,
    created,
    updated,
    seconds: (Date.now() - started) / 1000,
  };
  const file = await report(rows, o.apply ? "apply" : "dry-run");
  await saveJson(path.join(backups, "latest-" + summary.mode + ".json"), {
    summary,
    rows,
  });
  console.log(JSON.stringify({ ...summary, report: file }, null, 2));
  return { mapped, styleIds, summary };
}
export async function main() {
  const o = options(),
    client = await login(o);
  try {
    await importCatalog(o, client);
  } finally {
    await client.auth.signOut();
  }
}
if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href
)
  main().catch((e) => {
    console.error(e.message);
    process.exitCode = 1;
  });
