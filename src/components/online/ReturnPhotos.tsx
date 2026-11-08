import { useEffect, useState } from "react";
import type { ReturnPhoto } from "../../../shared/returns";

// Staff can view evidence; uploads belong to the customer's website flow.
export function ReturnPhotos({
  photos,
  onView,
}: {
  photos: ReturnPhoto[];
  onView: (path: string) => Promise<string>;
}) {
  const [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [photo, setPhoto] = useState<string | null>(null);
  useEffect(() => {
    if (!photo) return;
    const timer = setTimeout(() => setPhoto(null), 55_000);
    return () => clearTimeout(timer);
  }, [photo]);
  async function view(path: string) {
    setBusy(true);
    setError("");
    try {
      setPhoto(await onView(path));
    } catch {
      setError("Photo could not be opened. Refresh and try again.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="space-y-3" aria-label="Private product photos">
      <h3>Product photos</h3>
      <p className="text-sm">
        Evidence is private to the customer and authorized staff.
      </p>
      <div className="flex flex-wrap gap-3">
        {photos.map((p, i) =>
          p.uploaded ? (
            <button
              key={p.id}
              type="button"
              className="underline"
              disabled={busy}
              onClick={() => void view(p.storage_path)}
            >
              View photo {i + 1}
            </button>
          ) : (
            <p key={p.id}>Photo {i + 1}: upload incomplete</p>
          ),
        )}
      </div>
      {busy && <p role="status">Opening photo…</p>}
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
          <img
            src={photo}
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
