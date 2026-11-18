import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import type { ComponentProps } from "react";
export function FormField({
  label,
  id,
  help,
  ...props
}: ComponentProps<typeof Input> & { label: string; help?: string }) {
  return (
    <div className="space-y-2">
      <Label htmlFor={id}>{label}</Label>
      <Input id={id} {...props} />
      {help && <p className="text-bodytext text-xs">{help}</p>}
    </div>
  );
}
