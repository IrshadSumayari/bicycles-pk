import { SearchPage } from "@/components/search-page";
import type { Query } from "@/lib/helpers";
export const metadata = {
  title: "Search",
  robots: { index: false, follow: true },
};
export default async function Page({
  searchParams,
}: {
  searchParams: Promise<Query>;
}) {
  return <SearchPage query={await searchParams} />;
}
