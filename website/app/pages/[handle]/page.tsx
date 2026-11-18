import { contentHandles, contentPage } from "@/lib/content";
import { ContentPage } from "@/components/content-page";
export const dynamicParams = false;
export function generateStaticParams() {
  return contentHandles("pages");
}
export async function generateMetadata({
  params,
}: {
  params: Promise<{ handle: string }>;
}) {
  const { handle } = await params;
  return {
    title: contentPage("pages", handle)?.title,
    alternates: { canonical: `/pages/${handle}` },
  };
}
export default async function Page({
  params,
}: {
  params: Promise<{ handle: string }>;
}) {
  return <ContentPage kind="pages" handle={(await params).handle} />;
}
