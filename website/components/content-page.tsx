import { notFound } from "next/navigation";
import { contentPage, type ContentKind } from "@/lib/content";

import { brand, storeAddress } from "@/lib/brand";
import { Button } from "./ui/button";
export async function ContentPage({
  kind,
  handle,
}: {
  kind: ContentKind;
  handle: string;
}) {
  const page = contentPage(kind, handle);
  if (!page) notFound();
  const html = page.html;
  return (
    <>
      <div className="page-heading">
        <h1>{page.title}</h1>
        <p>{brand.name}</p>
      </div>
      <article className={kind === "policies" ? "policy-page" : "content-page"}>
        <div
          className="rich-content"
          dangerouslySetInnerHTML={{ __html: html }}
        />
        {["contact", "store-location"].includes(handle) && (
          <section className="space-y-4 mt-6">
            <address className="not-italic">{storeAddress}</address>
            {brand.mapsUrl && (
              <Button asChild>
                <a
                  href={brand.mapsUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  Find us on Google Maps
                </a>
              </Button>
            )}
            {brand.email && (
              <p>
                <a href={`mailto:${brand.email}`}>{brand.email}</a>
              </p>
            )}
            {brand.phone && (
              <p>
                <a href={`tel:${brand.phone}`}>{brand.phone}</a>
              </p>
            )}
          </section>
        )}
      </article>
    </>
  );
}
