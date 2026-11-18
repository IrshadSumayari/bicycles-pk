import type { ComponentProps } from "react";
import { Table } from "@/components/ui/table";
import { EmptyState } from "./EmptyState";
export function DataTable({
  children,
  empty,
  ...props
}: ComponentProps<"table"> & { empty?: string }) {
  return (
    <div className="overflow-x-auto rounded-tw border border-border bg-card">
      {empty ? (
        <EmptyState>{empty}</EmptyState>
      ) : (
        <Table {...props}>{children}</Table>
      )}
    </div>
  );
}
