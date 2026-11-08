"use client";
import { useEffect, useState } from "react";
import type { ReturnPhoto } from "../../shared/returns";
export function ReturnPhotos({
  photos,
  onView,
  onUpload,
}: {
  photos: ReturnPhoto[];
  onView: (path: string) => Promise<string>;
  onUpload?: (file: File, id?: string) => Promise<void>;
}) {
  const [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [photo, setPhoto] = useState<{ id: string; url: string } | null>(null);
  useEffect(() => {
    if (!photo) return;
    const timer = setTimeout(() => setPhoto(null), 55_000);
    return () => clearTimeout(timer);
  }, [photo]);
  async function view(p: ReturnPhoto) {
    setBusy(true);
    setError("");
    try {
      setPhoto({ id: p.id, url: await onView(p.storage_path) });
    } catch {
      setError("Photo could not be opened. Refresh and try again.");
    } finally {
      setBusy(false);
    }
  }
  async function upload(file: File | undefined, id?: string) {
    if (!file || !onUpload) return;
    setBusy(true);
    setError("");
    try {
      await onUpload(file, id);
    } catch (e) {
      setError(
        e instanceof Error ? e.message : "Photo upload failed. Try again.",
      );
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="space-y-3" aria-label="Private product photos">
      <h3>Product photos</h3>
      <p className="text-sm">
        Photos are private to you and authorized staff. Show the product and
        issue only; avoid faces, bodies, payment details and address labels.
      </p>
      <div className="flex flex-wrap gap-3">
        {photos.map((p, i) => (
          <div key={p.id}>
            {p.uploaded ? (
              <button
                type="button"
                className="underline"
                disabled={busy}
                onClick={() => void view(p)}
              >
                View photo {i + 1}
              </button>
            ) : onUpload ? (
              <label className="block text-sm">
                Retry photo {i + 1}
                <input
                  type="file"
                  accept="image/jpeg,image/png,image/webp"
                  disabled={busy}
                  onChange={(e) => {
                    void upload(e.target.files?.[0], p.id);
                    e.target.value = "";
                  }}
                />
              </label>
            ) : (
              <p>Photo {i + 1}: upload incomplete</p>
            )}
          </div>
        ))}
      </div>
      {onUpload && photos.length < 3 && (
        <label className="block text-sm">
          Add product photo ({photos.length}/3 slots used)
          <input
            className="block w-full"
            type="file"
            accept="image/jpeg,image/png,image/webp"
            disabled={busy}
            onChange={(e) => {
              void upload(e.target.files?.[0]);
              e.target.value = "";
            }}
          />
        </label>
      )}
      {onUpload && (
        <p className="text-sm">
          Optional: up to three photos. JPEG, PNG or WebP, 10 MB maximum before
          resizing. Uploaded evidence cannot be replaced; contact support if a
          photo needs removal.
        </p>
      )}
      {busy && <p role="status">Working with photo…</p>}
      {error && <p role="alert">{error}</p>}
      {photo && (
        <div>
          <button
            type="button"
            className="underline"
            onClick={() => setPhoto(null)}
          >
            Hide photo
          </button>
          {/* Private, short-lived storage URL must not pass through a public image optimizer. */}

          {/* eslint-disable-next-line @next/next/no-img-element -- Private signed URLs must bypass the public optimizer. */}
          <img
            src={photo.url}
            alt="Product evidence for this return request"
            referrerPolicy="no-referrer"
            style={{ maxWidth: "100%", maxHeight: 360, objectFit: "contain" }}
            onError={() => {
              setPhoto(null);
              setError("Photo link expired or unavailable. Open it again.");
            }}
          />
        </div>
      )}
    </section>
  );
}
