import { ProductGuideEditor } from "./ProductGuideEditor";
import { BagDetailsEditor } from "./BagDetailsEditor";
import { isBagCategory } from "../../../shared/bags";
import { TryOnEditor, type RemovedTryOnFiles } from "./TryOnEditor";
import { readTryOn, tryOnError } from "../../../shared/tryOn";
import {
  readProductGuide,
  productGuideError,
} from "../../../shared/productGuide";
import { Input } from "@/components/ui/input";
import { useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useApp } from "../../context/SupabaseAppContext";
import { webCatalogService, type WebDetails } from "../../lib/services";
import { queryKeys } from "../../lib/queryClient";
import { slugify } from "../../lib/images";
import { getErrorMessage } from "../../lib/errors";
import { swalConfig } from "../../lib/sweetAlert";
import { ReportStatus } from "../reports/ReportStatus";
import { ImageManager } from "./ImageManager";
import type { Json } from "../../lib/database.types";

export function WebsitePanel({ styleId }: { styleId: string | null }) {
  const { state } = useApp();
  const allowed = ["admin", "manager"].includes(state.currentUser?.role ?? "");
  const details = useQuery({
    queryKey: queryKeys.webDetails(styleId ?? ""),
    queryFn: () => webCatalogService.details(styleId!),
    enabled: allowed && !!styleId,
  });
  const images = useQuery({
    queryKey: queryKeys.webImages(styleId ?? ""),
    queryFn: () => webCatalogService.listImages(styleId!),
    enabled: allowed && !!styleId,
  });
  if (!allowed) return null;
  if (!styleId)
    return (
      <p className="modal-body">
        Save this style first, then reopen it to add website details and images.
      </p>
    );
  if (!details.data || !images.data)
    return (
      <div className="modal-body">
        <ReportStatus
          loading={details.isPending || images.isPending}
          error={details.error ?? images.error}
          retry={() => {
            void details.refetch();
            void images.refetch();
          }}
        />
      </div>
    );
  return (
    <WebsiteForm
      key={styleId}
      initial={details.data}
      images={images.data}
      refresh={() => {
        void details.refetch();
        void images.refetch();
      }}
    />
  );
}

type Details = Awaited<ReturnType<typeof webCatalogService.details>>;
function WebsiteForm({
  initial,
  images,
  refresh,
}: {
  initial: Details;
  images: Awaited<ReturnType<typeof webCatalogService.listImages>>;
  refresh: () => void;
}) {
  const { state } = useApp();
  const [slug, setSlug] = useState(initial.slug ?? slugify(initial.name));
  const [title, setTitle] = useState(initial.web_title ?? "");
  const [description, setDescription] = useState(initial.web_description ?? "");
  const [guide, setGuide] = useState(() =>
    readProductGuide(initial.product_guide),
  );
  const [tryOn, setTryOn] = useState(() =>
    readTryOn(initial.try_on, initial.id),
  );
  const removed = useRef<RemovedTryOnFiles>({ models: [], frames: [] });
  const [variants, setVariants] = useState(
    initial.variants.map((v) => ({ variant_id: v.id, published: v.published })),
  );
  const [published, setPublished] = useState(initial.published);
  const [busy, setBusy] = useState(false);
  const [problems, setProblems] = useState<string[]>([]);
  const action = useRef<{ fingerprint: string; id: string } | null>(null);
  const valid =
    (!slug || /^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug)) && slug.length <= 120;
  const preview = useQuery({
    queryKey: queryKeys.webPreview(initial.slug ?? slug),
    queryFn: () => webCatalogService.preview(initial.slug ?? slug),
    enabled: published && !!(initial.slug ?? slug),
  });
  async function saveDetails() {
    const details: WebDetails = {
      slug: slug || null,
      web_title: title,
      web_description: description,
      product_guide: guide,
      try_on: tryOn,
      variants,
    };
    const fingerprint = JSON.stringify(details);
    if (action.current?.fingerprint !== fingerprint)
      action.current = { fingerprint, id: crypto.randomUUID() };
    await webCatalogService.saveWebDetails(
      initial.id,
      details,
      action.current.id,
    );
    action.current = null;
    // Saved details no longer point at removed files, so they can be deleted.
    // A failed deletion leaves only an unused file; it is retried next save.
    const { models, frames } = removed.current;
    removed.current = { models: [], frames: [] };
    for (const path of models)
      await webCatalogService.deleteTryOnModel(path).catch(() => {
        removed.current.models.push(path);
      });
    for (const path of frames)
      await webCatalogService.deleteObject(path).catch(() => {
        removed.current.frames.push(path);
      });
    refresh();
  }
  async function save(publish?: boolean) {
    if (busy) return;
    setBusy(true);
    setProblems([]);
    try {
      if (publish === false) {
        await webCatalogService.publish(initial.id, false, false);
        setPublished(false);
        refresh();
        return;
      }
      if (!valid) {
        setProblems([
          "Use a web address of at most 120 lowercase letters, numbers and hyphens",
        ]);
        return;
      }
      const guideError = productGuideError(guide);
      if (guideError) {
        setProblems([guideError]);
        return;
      }
      const tryOnProblem = tryOnError(tryOn, initial.id);
      if (tryOnProblem) {
        setProblems([tryOnProblem]);
        return;
      }
      await saveDetails();
      if (publish) {
        const found = await webCatalogService.publish(initial.id, true, true);
        if (found.length) {
          setProblems(found);
          return;
        }
        await webCatalogService.publish(initial.id, true, false);
        setPublished(true);
        refresh();
      }
      swalConfig.success(
        publish ? "Published on website" : "Website details saved",
      );
    } catch (error) {
      swalConfig.error(getErrorMessage(error));
    } finally {
      setBusy(false);
    }
  }
  const live =
    preview.data &&
    typeof preview.data === "object" &&
    !Array.isArray(preview.data)
      ? preview.data
      : null;
  const liveImages: Json[] =
    live && Array.isArray(live.images) ? live.images : [];
  const first = liveImages[0];
  const livePath =
    first &&
    typeof first === "object" &&
    !Array.isArray(first) &&
    typeof first.storage_path === "string"
      ? first.storage_path
      : null;
  const onlineVariants = initial.variants.filter(
    (v) =>
      v.active &&
      variants.find((flag) => flag.variant_id === v.id)?.published &&
      v.price > 0,
  );
  const prices = onlineVariants.map((v) => v.price);
  const available = onlineVariants.map((v) => ({
    available: v.stock
      .filter(
        (b) =>
          b.location?.active &&
          ["shop_floor", "stockroom", "online"].includes(b.location.kind),
      )
      .reduce((n, b) => n + b.on_hand - b.reserved, 0),
    min: v.min_stock,
  }));
  const band =
    !initial.track_inventory ||
    available.some((v) => v.available > Math.max(2, v.min))
      ? "in_stock"
      : available.some((v) => v.available > 0)
        ? "low_stock"
        : "out_of_stock";
  const path = published ? livePath : images[0]?.storage_path;
  const money = (n: number) => `${state.settings.currency} ${n.toFixed(2)}`;
  return (
    <div className="modal-body space-y-6">
      <h3 className="text-xl font-semibold">Website</h3>
      <p className="text-sm text-bodytext">
        Website changes save separately. Save price, name or variant changes in
        Details before editing the website.
      </p>
      <label className="flex gap-2 items-center">
        <Input
          type="checkbox"
          checked={published}
          disabled={busy}
          onChange={(event) => void save(event.target.checked)}
        />
        Published on website
      </label>
      {!!problems.length && (
        <div role="alert" className="bg-lightwarning p-4 rounded-xl">
          <p>Before publishing:</p>
          <ul className="list-disc pl-5">
            {problems.map((problem) => (
              <li key={problem}>{problem}</li>
            ))}
          </ul>
        </div>
      )}
      <fieldset disabled={busy} className="space-y-3">
        {isBagCategory(initial.category?.name) ? (
          <BagDetailsEditor value={guide} onChange={setGuide} />
        ) : (
          <ProductGuideEditor value={guide} onChange={setGuide} />
        )}
        {/* The 360° model is for worn garments; bags only show it if one was already added. */}
        {(!isBagCategory(initial.category?.name) || initial.try_on) && <TryOnEditor
          styleId={initial.id}
          colors={[
            ...new Set(
              initial.variants.flatMap((v) => (v.color ? [v.color] : [])),
            ),
          ]}
          value={tryOn}
          onChange={setTryOn}
          onRemove={(files) => {
            removed.current.models.push(...files.models);
            removed.current.frames.push(...files.frames);
          }}
        />}
        <label className="block">
          Web address
          <Input
            className="input block"
            value={slug}
            maxLength={120}
            onChange={(event) => setSlug(event.target.value)}
            aria-invalid={!valid}
          />
        </label>
        {!valid && (
          <p className="text-error">
            Use lowercase letters, numbers and single hyphens, up to 120
            characters.
          </p>
        )}
        <label className="block">
          Web title
          <Input
            className="input block"
            value={title}
            maxLength={150}
            onChange={(event) => setTitle(event.target.value)}
            placeholder={initial.name}
          />
        </label>
        <label className="block">
          Web description
          <textarea
            aria-label="Web description"
            className="textarea block"
            rows={4}
            maxLength={5000}
            value={description}
            onChange={(event) => setDescription(event.target.value)}
          />
        </label>
        <p className="text-sm text-bodytext">
          {description.length} / 5000 characters
        </p>
        <div className="space-y-2">
          {initial.variants.map((v) => (
            <label className="flex items-center gap-2" key={v.id}>
              <Input
                type="checkbox"
                checked={
                  variants.find((flag) => flag.variant_id === v.id)
                    ?.published ?? false
                }
                onChange={(event) =>
                  setVariants(
                    variants.map((flag) =>
                      flag.variant_id === v.id
                        ? { ...flag, published: event.target.checked }
                        : flag,
                    ),
                  )
                }
              />
              Show online: {v.sku} {v.size} {v.color}
            </label>
          ))}
        </div>
        <button
          type="button"
          className="btn btn-primary btn-md"
          disabled={!valid}
          onClick={() => void save()}
        >
          Save website details
        </button>
      </fieldset>
      <ImageManager
        styleId={initial.id}
        initial={images}
        colors={[
          ...new Set(
            initial.variants.flatMap((v) => (v.color ? [v.color] : [])),
          ),
        ]}
        onSaved={refresh}
      />
      <section
        className="card p-4 max-w-sm space-y-2"
        aria-label="Website preview"
      >
        <h3 className="font-semibold">Website preview</h3>
        {published && (
          <ReportStatus
            loading={preview.isPending}
            error={preview.error}
            retry={() => void preview.refetch()}
          />
        )}
        {path && (
          <img
            className="w-full h-48 object-cover rounded-lg"
            src={webCatalogService.publicUrl(path)}
            alt={title || initial.name}
          />
        )}
        <p>
          {published && typeof live?.title === "string"
            ? live.title
            : title || initial.name}
        </p>
        <p>
          {published && typeof live?.min_price === "number"
            ? `${money(live.min_price)} – ${money(Number(live.max_price))}`
            : prices.length
              ? `${money(Math.min(...prices))} – ${money(Math.max(...prices))}`
              : "Add a priced online variant"}
        </p>
        <p>
          {published && typeof live?.stock_level === "string"
            ? live.stock_level
            : band}
        </p>
        {published && !preview.isPending && !preview.data && (
          <p className="text-warning">
            This style is hidden from the public catalog. Check that the style
            and a priced online variant are active.
          </p>
        )}
      </section>
    </div>
  );
}
