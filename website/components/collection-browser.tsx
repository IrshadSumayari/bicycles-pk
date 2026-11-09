import Link from "next/link";
import type { Facets } from "@/lib/types";
import { SearchX, ArrowUpRight } from "lucide-react";
import { ShopHeading } from "./shop-heading";
import { catalog, safeCatalog } from "@/lib/catalog";
import { filterQuery, parseFilters, type Query } from "@/lib/helpers";
import { ProductCard } from "./product-card";
import { FilterPanel } from "./filter-panel";
import { Input } from "./ui/input";
import { Button } from "./ui/button";
import {
  categoryHref,
  sectionById,
  sectionOfCategory,
  type SectionId,
} from "../../shared/bicycles";
export async function CollectionBrowser({
  title,
  description,
  collection,
  query,
  path,
  search = false,
}: {
  title: string;
  description?: string | null;
  collection?: string;
  query: Query;
  path: string;
  search?: boolean;
}) {
  const filters = parseFilters(query);
  // A section (from ?section= or the chosen category) lists all its categories.
  const section = filters.section
    ? sectionById(filters.section as SectionId)
    : sectionOfCategory(filters.category);
  const sectionCategories = filters.section
    ? section?.categories.map((c) => c.name)
    : undefined;
  const [catalogProducts, facets] = await Promise.all([
    safeCatalog<Awaited<ReturnType<typeof catalog.list>> | null>(
      () =>
        catalog.list({
          ...filters,
          ...(sectionCategories ? { categories: sectionCategories } : {}),
          collection,
          limit: 24,
          offset: (filters.page - 1) * 24,
        }),
      null,
    ),
    safeCatalog<Facets>(() => catalog.facets(collection ?? null), {
      sizes: [],
      colors: [],
      price_min: null,
      price_max: null,
    }),
  ]);
  const unavailable = catalogProducts === null;
  const products = unavailable ? [] : (catalogProducts ?? []);
  const activeFilters = [
    ["q", filters.q],
    ["size", filters.size],
    ["color", filters.color],
    ["category", filters.category],
    ["section", section && filters.section ? section.label : ""],
    ["price_min", filters.price_min],
    ["price_max", filters.price_max],
  ].filter(([, value]) => value !== "" && value !== undefined);
  const removeFilter = (key: string) => {
    const params = new URLSearchParams(filterQuery(filters, 1));
    params.delete(key);
    return path + (params.size ? "?" + params.toString() : "");
  };
  const count = Number(products[0]?.total_count ?? 0);
  const pageLink = (page: number) => `${path}?${filterQuery(filters, page)}`;
  const fields = (
    <>
      <label>
        Search
        <Input className="field" name="q" defaultValue={filters.q} />
      </label>
      <label>
        Frame / wheel size
        <select className="field" name="size" defaultValue={filters.size}>
          <option value="">All sizes</option>
          {[
            ...new Set([
              ...facets.sizes,
              ...(filters.size ? [filters.size] : []),
            ]),
          ].map((size) => (
            <option key={size}>{size}</option>
          ))}
        </select>
      </label>
      <label>
        Colour
        <select className="field" name="color" defaultValue={filters.color}>
          <option value="">All colours</option>
          {[
            ...new Set([
              ...facets.colors,
              ...(filters.color ? [filters.color] : []),
            ]),
          ].map((color) => (
            <option key={color}>{color}</option>
          ))}
        </select>
      </label>
      {filters.category && (
        <input type="hidden" name="category" value={filters.category} />
      )}
      {filters.section && (
        <input type="hidden" name="section" value={filters.section} />
      )}
      <label>
        Price from
        <Input
          className="field"
          type="number"
          name="price_min"
          min="0"
          step="0.01"
          defaultValue={filters.price_min}
          placeholder={facets.price_min?.toString()}
        />
      </label>
      <label>
        Price to
        <Input
          className="field"
          type="number"
          name="price_max"
          min="0"
          step="0.01"
          defaultValue={filters.price_max}
          placeholder={facets.price_max?.toString()}
        />
      </label>
      <input type="hidden" name="sort" value={filters.sort} />
      <Button type="submit">Apply filters</Button>
      <Link href={path}>Clear filters</Link>
    </>
  );
  return (
    <>
      <ShopHeading
        title={
          search
            ? filters.category || section?.label || "Find your ride."
            : title
        }
        eyebrow={
          search && section ? "BICYCLES.PK · " + section.label.toUpperCase() : "BICYCLES.PK"
        }
        description={
          search
            ? section?.description || "Search bicycles, accessories and parts."
            : description || "Bicycles, accessories and parts."
        }
      >
        {search && (
          <form className="search-form" action={path} role="search">
            {[...new URLSearchParams(filterQuery(filters, 1))]
              .filter(([key]) => key !== "q")
              .map(([key, value]) => (
                <input key={key} type="hidden" name={key} value={value} />
              ))}
            <Input
              name="q"
              defaultValue={filters.q}
              aria-label="Search our collections"
              placeholder="Try city bike, helmet or 20 inch"
            />
            <Button type="submit">Search</Button>
          </form>
        )}
      </ShopHeading>
      {section && (
        <nav className="lv-category-pills" aria-label={section.label + " categories"}>
          <Link
            href={"/search?section=" + section.id}
            aria-current={filters.section && !filters.category ? "page" : undefined}
          >
            All {section.label.toLowerCase()}
          </Link>
          {section.categories.slice(1).map((c) => (
            <Link
              key={c.slug}
              href={categoryHref(c.name)}
              aria-current={filters.category === c.name ? "page" : undefined}
            >
              {c.name}
            </Link>
          ))}
        </nav>
      )}
      {activeFilters.length > 0 && (
        <nav className="lv-filter-chips" aria-label="Active filters">
          {activeFilters.map(([key, value]) => (
            <Link
              key={key}
              href={removeFilter(String(key))}
              aria-label={"Remove " + key + " filter"}
            >
              {key === "q"
                ? "Search"
                : String(key).replaceAll("_", " ")}
              : {String(value)}
              <span aria-hidden="true"> ×</span>
            </Link>
          ))}
          <Link href={path}>Clear all</Link>
        </nav>
      )}
      <FilterPanel
        count={count}
        page={filters.page}
        sort={filters.sort}
        path={path}
        query={filterQuery(filters, 1)}
        filters={
          <form
            action={path}
            className="catalog-filter-fields"
            aria-label="Catalog filters"
          >
            {fields}
          </form>
        }
      >
        {products.length ? (
          <div className="product-grid">
            {products.map((product) => (
              <ProductCard key={product.style_id} product={product} />
            ))}
          </div>
        ) : (
          <div className="empty-state">
            <SearchX size={38} strokeWidth={1} />
            <p className="lv-eyebrow">A LITTLE PAUSE</p>
            <h2>
              {unavailable
                ? "The collection is taking a moment."
                : "Nothing here just yet."}
            </h2>
            <p>
              {unavailable
                ? "We couldn’t load the collection right now. Please try again shortly."
                : "Try a different search or remove a filter to discover more."}
            </p>
            <Link
              className="lv-button"
              href={unavailable ? pageLink(filters.page) : path}
            >
              {unavailable ? "Try again" : "Clear filters"}
              <ArrowUpRight size={16} />
            </Link>
            <Link className="lv-link" href="/collections">
              Explore the collections
            </Link>
          </div>
        )}
        {count > 0 && (
          <nav className="pagination" aria-label="Catalog pages">
            {filters.page > 1 && (
              <Link
                className="button secondary"
                href={pageLink(filters.page - 1)}
              >
                Previous page
              </Link>
            )}
            <span>Page {filters.page}</span>
            {filters.page * 24 < count && (
              <Link
                className="button secondary"
                href={pageLink(filters.page + 1)}
              >
                Next page
              </Link>
            )}
          </nav>
        )}
      </FilterPanel>
    </>
  );
}
