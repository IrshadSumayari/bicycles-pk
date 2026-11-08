import { ChevronRight } from "lucide-react";
export function PageHeader({ title }: { title: string }) {
  return (
    <div className="page-header flex items-center justify-between gap-4">
      <div>
        <h1 className="font-semibold text-xl">{title}</h1>
        <div className="flex items-center gap-2 text-bodytext text-xs mt-2">
          <span>Home</span>
          <ChevronRight size={14} />
          <span>{title}</span>
        </div>
      </div>
    </div>
  );
}
