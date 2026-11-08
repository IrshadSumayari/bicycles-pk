import { Badge } from "@/components/ui/badge";
import type { ReactNode } from "react";
export function StatusBadge({
  status,
  children,
}: {
  status: string;
  children?: ReactNode;
}) {
  const success = [
      "completed",
      "paid",
      "delivered",
      "ready",
      "ready_for_pickup",
      "closed",
      "confirmed",
    ],
    error = ["cancelled", "refunded", "needs_refund", "failed", "expired"],
    warning = [
      "pending",
      "pending_payment",
      "placed",
      "draft",
      "awaiting",
      "open",
      "credit",
    ];
  return (
    <Badge
      variant={
        success.includes(status)
          ? "lightSuccess"
          : error.includes(status)
            ? "lightError"
            : warning.includes(status)
              ? "lightWarning"
              : "lightPrimary"
      }
    >
      {children ?? status.replaceAll("_", " ")}
    </Badge>
  );
}
