import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { catalog, safeCatalog } from "@/lib/catalog";
import { imageUrl } from "@/lib/helpers";
import type { Query } from "@/lib/helpers";
import { CollectionBrowser } from "@/components/collection-browser";
export const revalidate = 60;
type Props = {
  params: Promise<{ slug: string }>;
  searchParams: Promise<Query>;
};
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const collection = (await safeCatalog(catalog.collections, [])).find(
    (item) => item.slug === slug,
  );
  if (!collection)
    return { title: "Collection not found", robots: { index: false } };
  const image = imageUrl(collection.hero_image_path);
  return {
    title: collection.name,
    description: collection.description || undefined,
    alternates: { canonical: `/collections/${slug}` },
    openGraph: {
      title: collection.name,
      description: collection.description || undefined,
      images: image ? [image] : [],
    },
  };
}
export default async function CollectionPage({ params, searchParams }: Props) {
  const { slug } = await params;
  let collections;
  try {
    collections = await catalog.collections();
  } catch {
    return (
      <section className="section">
        <h1 className="text-3xl">Please visit again shortly</h1>
        <p>The collection is temporarily unavailable.</p>
      </section>
    );
  }
  const collection = collections.find((item) => item.slug === slug);
  if (!collection) notFound();
  return (
    <CollectionBrowser
      title={collection.name}
      description={collection.description}
      collection={slug}
      query={await searchParams}
      path={`/collections/${slug}`}
    />
  );
}
