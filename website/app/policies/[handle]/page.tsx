import { contentHandles, contentPage } from "@/lib/content";
import { ContentPage } from "@/components/content-page";
export const dynamicParams = false;
export function generateStaticParams() {
  return contentHandles("policies");
}
export async function generateMetadata({
  params,
}: {
  params: Promise<{ handle: string }>;
}) {
  const { handle } = await params;
  return {
    title: contentPage("policies", handle)?.title,
    alternates: { canonical: `/policies/${handle}` },
  };
}
export default async function Page({
  params,
}: {
  params: Promise<{ handle: string }>;
}) {
  return <ContentPage kind="policies" handle={(await params).handle} />;
}
