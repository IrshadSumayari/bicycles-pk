import {Input}from'@/components/ui/input';
import { useRef, useState } from 'react';
import { webCatalogService, type ProductImage } from '../../lib/services';
import { resizeImage } from '../../lib/images';
import { getErrorMessage } from '../../lib/errors';
import { swalConfig } from '../../lib/sweetAlert';

export function ImageManager({
  styleId,
  initial,
  colors,
  onSaved,
}: {
  styleId: string;
  initial: ProductImage[];
  colors: string[];
  onSaved: () => void;
}) {
  const [images, setImages] = useState(initial);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState('');
  const [request, setRequest] = useState(() => crypto.randomUUID());
  const pendingDelete = useRef<string[]>([]);
  function change(next: ProductImage[]) {
    setImages(next);
    setRequest(crypto.randomUUID());
  }
  async function save() {
    setBusy(true);
    try {
      await webCatalogService.saveImages(
        styleId,
        images.map((image, index) => ({ ...image, sort_order: index })),
        request,
      );
      // Metadata is removed first, so a failed object deletion never leaves a
      // broken image on the live website. Retrying this action uses the same ID.
      for (const path of [...pendingDelete.current]) {
        await webCatalogService.deleteObject(path);
        pendingDelete.current = pendingDelete.current.filter(
          (item) => item !== path,
        );
      }
      setRequest(crypto.randomUUID());
      onSaved();
      swalConfig.success('Images saved');
    } catch (error) {
      swalConfig.error(getErrorMessage(error));
    } finally {
      setBusy(false);
    }
  }
  async function upload(files: FileList | null) {
    if (!files) return;
    const selectedFiles = [...files];
    setBusy(true);
    const next = [...images];
    const errors: string[] = [];
    for (const [index, file] of selectedFiles.entries()) {
      setProgress(`${index + 1} of ${selectedFiles.length}`);
      try {
        const path = await webCatalogService.uploadImage(
          styleId,
          await resizeImage(file),
        );
        next.push({
          storage_path: path,
          alt: '',
          variant_color: null,
          sort_order: next.length,
        });
        change([...next]);
      } catch (error) {
        errors.push(`${file.name}: ${getErrorMessage(error)}`);
      }
    }
    setBusy(false);
    setProgress('');
    if (errors.length) swalConfig.error(errors.join('\n'));
  }
  function move(index: number, delta: number) {
    const next = [...images];
    [next[index], next[index + delta]] = [next[index + delta], next[index]];
    change(next);
  }
  return (
    <section className="space-y-3" aria-label="Website images">
      <h3 className="font-semibold">Images</h3>
      <p className="text-sm text-bodytext">
        Choose images up to 10 MB. Uploads are resized before saving. Save
        images before publishing; deleting a thumbnail and saving also deletes
        its file.
      </p>
      <label className="block">
        Upload website images
        <Input
          className="input block"
          type="file"
          accept="image/*"
          multiple
          disabled={busy}
          onChange={(event) => {
            void upload(event.target.files);
            event.target.value = '';
          }}
        />
      </label>
      <p aria-live="polite">{progress}</p>
      <fieldset disabled={busy} className="space-y-3">
        {images.map((image, index) => (
          <div
            className="border rounded-xl p-3 flex flex-wrap gap-3 items-center"
            key={image.storage_path}
          >
            <img
              src={webCatalogService.publicUrl(image.storage_path)}
              alt={image.alt || 'Product image'}
              className="w-20 h-24 object-cover rounded-lg"
            />
            <label className="flex-1 min-w-40">
              Alt text
              <Input
                className="input block"
                value={image.alt ?? ''}
                onChange={(event) =>
                  change(
                    images.map((item, i) =>
                      i === index ? { ...item, alt: event.target.value } : item,
                    ),
                  )
                }
              />
            </label>
            <label>
              Image color
              <select
                className="select block"
                value={image.variant_color ?? ''}
                onChange={(event) =>
                  change(
                    images.map((item, i) =>
                      i === index
                        ? { ...item, variant_color: event.target.value || null }
                        : item,
                    ),
                  )
                }
              >
                <option value="">All colors</option>
                {[
                  ...new Set([
                    ...colors,
                    ...(image.variant_color ? [image.variant_color] : []),
                  ]),
                ].map((color) => (
                  <option key={color}>{color}</option>
                ))}
              </select>
            </label>
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              disabled={index === 0}
              onClick={() => move(index, -1)}
              aria-label={`Move image ${index + 1} up`}
            >
              Up
            </button>
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              disabled={index === images.length - 1}
              onClick={() => move(index, 1)}
              aria-label={`Move image ${index + 1} down`}
            >
              Down
            </button>
            <button
              type="button"
              className="btn btn-secondary btn-sm text-error"
              onClick={() => {
                pendingDelete.current.push(image.storage_path);
                change(images.filter((_, i) => i !== index));
              }}
            >
              Delete image {index + 1}
            </button>
          </div>
        ))}
      </fieldset>
      <button
        type="button"
        className="btn btn-primary btn-md"
        disabled={busy}
        onClick={() => void save()}
      >
        {busy ? 'Working…' : 'Save images'}
      </button>
    </section>
  );
}
