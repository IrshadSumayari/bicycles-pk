import { useState } from "react";
import {
  colorHex,
  modelTones,
  tryOnLimits,
  type ModelTone,
  type TryOn,
} from "../../../shared/tryOn";
import { Input } from "../ui/input";
import { webCatalogService } from "../../lib/services";
import { resizeImage } from "../../lib/images";
import { getErrorMessage } from "../../lib/errors";
import { swalConfig } from "../../lib/sweetAlert";

// Files a shopper may still see stay until the website details are saved;
// the parent deletes these after a successful save.
export type RemovedTryOnFiles = { models: string[]; frames: string[] };
const toneLabel = (tone: ModelTone) =>
  modelTones.find((t) => t.id === tone)?.label ?? tone;

export function TryOnEditor({
  styleId,
  colors,
  value,
  onChange,
  onRemove,
}: {
  styleId: string;
  colors: string[];
  value: TryOn;
  onChange: (v: TryOn) => void;
  onRemove: (files: RemovedTryOnFiles) => void;
}) {
  const [progress, setProgress] = useState("");
  const busy = !!progress;
  async function uploadModel(file: File | undefined) {
    if (!file) return;
    setProgress("Uploading 3D model…");
    try {
      const path = await webCatalogService.uploadTryOnModel(styleId, file);
      if (value.model_path) onRemove({ models: [value.model_path], frames: [] });
      onChange({ ...value, model_path: path });
    } catch (error) {
      swalConfig.error(getErrorMessage(error));
    } finally {
      setProgress("");
    }
  }
  // Replaces (or with null removes) one model's photos in a colour; a tone
  // left without photos is dropped.
  function setPhotos(tone: ModelTone, color: string, paths: string[] | null) {
    const models = { ...value.models };
    const sets = { ...models[tone] };
    if (paths) sets[color] = paths;
    else delete sets[color];
    if (Object.keys(sets).length) models[tone] = sets;
    else delete models[tone];
    const next: TryOn = { ...value, models };
    if (!Object.keys(models).length) delete next.models;
    onChange(next);
  }
  async function uploadSpin(
    tone: ModelTone,
    color: string,
    files: FileList | null,
  ) {
    const list = [...(files ?? [])].sort((a, b) =>
      a.name.localeCompare(b.name, undefined, { numeric: true }),
    );
    if (!list.length) return;
    if (
      list.length < tryOnLimits.minFrames ||
      list.length > tryOnLimits.maxFrames
    ) {
      swalConfig.error(
        `Choose ${tryOnLimits.minFrames} to ${tryOnLimits.maxFrames} angle photos, named in turning order (front, side, back…).`,
      );
      return;
    }
    const paths: string[] = [];
    try {
      for (const [index, file] of list.entries()) {
        setProgress(
          `${color}, ${toneLabel(tone)} model: photo ${index + 1} of ${list.length}`,
        );
        paths.push(
          await webCatalogService.uploadSpinFrame(
            styleId,
            await resizeImage(file, 1200),
          ),
        );
      }
      const old = value.models?.[tone]?.[color];
      if (old) onRemove({ models: [], frames: old });
      setPhotos(tone, color, paths);
    } catch (error) {
      // An incomplete set is never shown; its uploaded photos are discarded.
      onRemove({ models: [], frames: paths });
      swalConfig.error(getErrorMessage(error));
    } finally {
      setProgress("");
    }
  }
  function setShade(color: string, hex: string | null) {
    const next = { ...value.colors };
    if (hex) next[color] = hex;
    else delete next[color];
    onChange({ ...value, colors: next });
  }
  function clearSpin(tone: ModelTone, color: string) {
    onRemove({ models: [], frames: value.models?.[tone]?.[color] ?? [] });
    setPhotos(tone, color, null);
  }
  return (
    <section
      className="rounded-xl border border-border p-4 space-y-4"
      aria-label="360° model"
    >
      <h3 className="font-semibold">360° model</h3>
      <p className="text-sm text-bodytext">
        Upload angle photos of the model wearing each colour (front, ¾, side,
        back, other side…), named in turning order. Add a model for any skin
        tones you have photos of; shoppers choose the model they relate to, and
        their choice is remembered. Shoppers drag to turn the model on the
        product page, and product cards turn on hover. A 3D model
        is used for colours without photos. With neither, no 360° view is
        shown. Use only images and models you have the rights to. Save website
        details to apply changes.
      </p>
      <fieldset disabled={busy} className="space-y-3">
        <label className="block">
          3D model (.glb, up to 25 MB)
          <Input
            className="input block"
            type="file"
            accept=".glb,model/gltf-binary"
            onChange={(event) => {
              void uploadModel(event.target.files?.[0]);
              event.target.value = "";
            }}
          />
        </label>
        {value.model_path && (
          <div className="flex flex-wrap gap-3 items-center">
            <span className="text-sm">3D model uploaded</span>
            <button
              type="button"
              className="btn btn-secondary btn-sm text-error"
              onClick={() => {
                onRemove({ models: [value.model_path!], frames: [] });
                const next = { ...value };
                delete next.model_path;
                onChange(next);
              }}
            >
              Remove 3D model
            </button>
          </div>
        )}
        <label className="block">
          Garment material names (optional, comma separated)
          <Input
            className="input block"
            value={(value.garment_materials ?? []).join(", ")}
            placeholder="Leave blank to recolour materials named lace, fabric, bra, brief…"
            onChange={(event) => {
              const names = event.target.value
                .split(",")
                .map((n) => n.trim())
                .filter(Boolean);
              const next = { ...value };
              if (names.length) next.garment_materials = names;
              else delete next.garment_materials;
              onChange(next);
            }}
          />
        </label>
        {!colors.length && (
          <p className="text-sm text-bodytext">
            Add colours to the variants to set shades and model photos.
          </p>
        )}
        {colors.map((color) => {
          const custom = value.colors?.[color];
          return (
            <div key={color} className="border rounded-xl p-3 space-y-3">
              <div className="flex flex-wrap gap-3 items-center">
                <strong className="min-w-24">{color}</strong>
                <label className="flex gap-2 items-center">
                  Shade
                  <input
                    type="color"
                    aria-label={`Shade for ${color}`}
                    value={custom ?? colorHex(color) ?? "#c98a9b"}
                    onChange={(event) => setShade(color, event.target.value)}
                  />
                </label>
                {custom && (
                  <button
                    type="button"
                    className="btn btn-secondary btn-sm"
                    onClick={() => setShade(color, null)}
                  >
                    Use default shade
                  </button>
                )}
              </div>
              <p className="text-sm text-bodytext">
                Angle photos per model ({tryOnLimits.minFrames}–
                {tryOnLimits.maxFrames} photos, named in order)
              </p>
              {modelTones.map((tone) => {
                const frames = value.models?.[tone.id]?.[color];
                return (
                  <div
                    key={tone.id}
                    className="flex flex-wrap gap-3 items-center"
                  >
                    <span className="flex gap-2 items-center min-w-28">
                      <span
                        aria-hidden="true"
                        className="inline-block size-5 rounded-full border border-border"
                        style={{ background: tone.swatch }}
                      />
                      {tone.label}
                    </span>
                    <Input
                      className="input block flex-1 min-w-48"
                      type="file"
                      accept="image/*"
                      multiple
                      aria-label={`${tone.label} model photos in ${color}`}
                      onChange={(event) => {
                        void uploadSpin(tone.id, color, event.target.files);
                        event.target.value = "";
                      }}
                    />
                    {frames && (
                      <>
                        <span className="text-sm">{frames.length} photos</span>
                        <button
                          type="button"
                          className="btn btn-secondary btn-sm text-error"
                          aria-label={`Remove ${tone.label} model photos in ${color}`}
                          onClick={() => clearSpin(tone.id, color)}
                        >
                          Remove
                        </button>
                      </>
                    )}
                  </div>
                );
              })}
            </div>
          );
        })}
      </fieldset>
      <p aria-live="polite">{progress}</p>
    </section>
  );
}
