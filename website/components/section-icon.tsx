import { Baby, Bike, HardHat, Trophy, Wrench, Zap, type LucideProps } from "lucide-react";
import type { SectionId } from "../../shared/bicycles";
const icons = {
  bicycles: Bike,
  kids: Baby,
  sports: Trophy,
  ebikes: Zap,
  accessories: HardHat,
  parts: Wrench,
} satisfies Record<SectionId, unknown>;
export function SectionIcon({ id, ...props }: { id: SectionId } & LucideProps) {
  const Icon = icons[id];
  return <Icon aria-hidden="true" {...props} />;
}
