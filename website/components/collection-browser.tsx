import Link from "next/link";
import {
  lingerieFilterKeys,
  lingerieFilterLabels,
  lingerieValueLabel,
} from "../../shared/lingerie";
import type { Facets } from "@/lib/types";
import { SearchX, ArrowUpRight } from "lucide-react";
import { ShopHeading } from "./shop-heading";
import { catalog, safeCatalog } from "@/lib/catalog";
import { filterQuery, parseFilters, type Query } from "@/lib/helpers";
import { ProductCard } from "./product-card";
import { FilterPanel } from "./filter-panel";
import { Input } from "./ui/input";
import { Button } from "./ui/button";
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
  const [catalogProducts, facets] = await Promise.all([
    safeCatalog<Awaited<ReturnType<typeof catalog.list>> | null>(
      () =>
        catalog.list({
          ...filters,
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
  const unavailable =
    catalogProducts === null ||
    (lingerieFilterKeys.some((key) => filters[key]) &&
      facets.lingerie_filters_version !== 1);
  const products = unavailable ? [] : (catalogProducts ?? []);
  const activeFilters = [
    ["q", filters.q],
    ["size", filters.size],
    ["color", filters.color],
    ["category", filters.category],
    ["price_min", filters.price_min],
    ["price_max", filters.price_max],
    ...lingerieFilterKeys.map((key) => [key, filters[key]]),
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
        Size
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
        Color
        <select className="field" name="color" defaultValue={filters.color}>
          <option value="">All colors</option>
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
      {lingerieFilterKeys.some(
        (key) => facets[key]?.length || filters[key],
      ) && (
        <fieldset className="col-span-full min-w-0 space-y-4">
          <legend className="font-semibold mb-3">Product details</legend>
          {lingerieFilterKeys.map((key) => {
            const options = [
              ...new Set([
                ...(facets[key] ?? []),
                ...(filters[key] ? [filters[key]!] : []),
              ]),
            ];
            if (!options.length) return null;
            return (
              <label key={key}>
                {lingerieFilterLabels[key]}
                <select
                  className="field"
                  name={key}
                  defaultValue={filters[key] ?? ""}
                >
                  <option value="">All</option>
                  {options.map((value) => (
                    <option key={value} value={value}>
                      {lingerieValueLabel(key, value)}
                    </option>
                  ))}
                </select>
              </label>
            );
          })}
          <p className="muted text-sm">
            Band and cup labels follow the supplier sizing system. No conversion
            is applied.
          </p>
        </fieldset>
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
        title={search ? "Find your favourites." : title}
        eyebrow={search ? "A LITTLE SOMETHING FOR YOU" : "THE LADYVOGUE EDIT"}
        description={
          search
            ? "Discover your next everyday essential."
            : description || "Thoughtful little luxuries for every day."
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
              placeholder="Try bras, satin or nightwear"
            />
            <Button type="submit">Search</Button>
          </form>
        )}
      </ShopHeading>
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
                : (lingerieFilterLabels[
                    key as keyof typeof lingerieFilterLabels
                  ] ?? String(key).replaceAll("_", " "))}
              : {lingerieValueLabel(String(key), String(value))}
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
