import { Inbox } from "lucide-react";
import type { ReactNode } from "react";
export function EmptyState({ children }: { children: ReactNode }) {
  return (
    <div className="p-8 text-center text-bodytext">
      <Inbox size={32} className="mx-auto mb-3 text-primary" />
      {children}
    </div>
  );
}
