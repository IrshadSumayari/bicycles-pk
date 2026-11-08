import { Account } from "@/components/account";
import { returnPath } from "@/lib/account";
export default async function Page({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  return (
    <section className="section">
      <Account next={returnPath((await searchParams).next)} />
    </section>
  );
}
