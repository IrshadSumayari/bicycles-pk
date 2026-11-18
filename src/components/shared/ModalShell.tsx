import type { ComponentProps, ReactNode } from "react";
import { cn } from "@/lib/utils";
// Existing dialogs keep their modalUtils ref, key handling and focus restoration.
export function ModalShell({ className, ...props }: ComponentProps<"div">) {
  return (
    <div className={cn("modal border border-border", className)} {...props} />
  );
}
export function ModalSection({ children }: { children: ReactNode }) {
  return <div className="modal-body space-y-4">{children}</div>;
}
