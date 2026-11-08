import { Card } from "@/components/ui/card";
import type { ComponentProps, ReactNode } from "react";
import { cn } from "@/lib/utils";
export function CardBox({ className, ...props }: ComponentProps<typeof Card>) {
  return <Card className={cn("card p-6", className)} {...props} />;
}
export function TitleIconCard({
  title,
  icon,
  children,
}: {
  title: string;
  icon: ReactNode;
  children: ReactNode;
}) {
  return (
    <CardBox>
      <div className="flex items-center gap-3 mb-5">
        <span className="p-2 rounded-md bg-lightprimary text-primary">
          {icon}
        </span>
        <h2 className="font-semibold text-lg">{title}</h2>
      </div>
      {children}
    </CardBox>
  );
}
