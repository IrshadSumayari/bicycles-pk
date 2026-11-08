import { CollectionBrowser } from "./collection-browser";
import type { Query } from "@/lib/helpers";
export function SearchPage({ query }: { query: Query }) {
  return (
    <CollectionBrowser title="Search" search query={query} path="/search" />
  );
}
