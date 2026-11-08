import { lazy, Suspense, useEffect, useState } from "react";
import type { ComponentType } from "react";
import type { Props } from "react-apexcharts";
import type { ApexOptions } from "apexcharts";
import { Skeleton } from "@/components/ui/skeleton";
import { useTheme } from "@/context/ThemeContext";
// react-apexcharts 1.x is CommonJS, so the component can arrive wrapped in a second `default`.
type ChartModule = { default: ComponentType<Props> | { default: ComponentType<Props> } };
const Apex = lazy(() =>
  import("react-apexcharts").then((module: ChartModule) => ({
    default: "default" in module.default ? module.default.default : module.default,
  })),
);
export function Chart({ options, ...props }: Props) {
  const { dark, theme } = useTheme();
  const [, redraw] = useState(0);
  useEffect(() => {
    const frame = requestAnimationFrame(() => redraw((n) => n + 1));
    return () => cancelAnimationFrame(frame);
  }, [dark, theme.preset]);
  const css = getComputedStyle(document.documentElement),
    color = (name: string) => css.getPropertyValue("--" + name).trim();
  const merged: ApexOptions = {
    ...options,
    colors: [
      color("primary"),
      color("secondary"),
      color("success"),
      color("warning"),
      color("error"),
    ],
    chart: {
      ...options?.chart,
      background: "transparent",
      fontFamily: "Manrope Variable, sans-serif",
      toolbar: { show: false },
      animations: { enabled: false },
      foreColor: color("link"),
    },
    theme: { mode: dark ? "dark" : "light" },
    grid: { borderColor: color("border") },
    tooltip: { ...options?.tooltip, theme: dark ? "dark" : "light" },
    legend: { ...options?.legend, labels: { colors: color("link") } },
  };
  return (
    <div className="dashboard-chart">
      <Suspense fallback={<Skeleton className="h-72 w-full rounded-tw" />}>
        <Apex key={theme.preset + dark} {...props} options={merged} />
      </Suspense>
    </div>
  );
}
