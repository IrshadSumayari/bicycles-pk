import { SectionPage } from "@/components/section-page";
import { sectionById } from "../../../shared/bicycles";
export const revalidate = 60;
const section = sectionById("kids");
export const metadata = { title: section.label, description: section.description };
export default function Page() {
  return <SectionPage id="kids" />;
}
