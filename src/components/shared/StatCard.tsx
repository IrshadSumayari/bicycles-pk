import type { ReactNode } from "react";
import { CardBox } from "./CardBox";

export type StatTone = "primary" | "secondary" | "success" | "warning" | "error" | "info";

// Full class names so Tailwind keeps them; one entry per tone.
const TONES: Record<StatTone, { soft: string; strong: string }> = {
  primary: { soft: "bg-lightprimary text-primary", strong: "bg-primary" },
  secondary: { soft: "bg-lightsecondary text-secondary", strong: "bg-secondary" },
  success: { soft: "bg-lightsuccess text-success", strong: "bg-success" },
  warning: { soft: "bg-lightwarning text-warning", strong: "bg-warning" },
  error: { soft: "bg-lighterror text-error", strong: "bg-error" },
  info: { soft: "bg-lightinfo text-info", strong: "bg-info" },
};

// MatDash summary card: large value, muted label, soft icon badge and an accent bar.
// Bars start at zero unless a caller provides a measured ratio.
export function StatCard({
  label,
  value,
  icon,
  tone = "primary",
  progress,
  progressLabel,
}: {
  label: string;
  value: ReactNode;
  icon?: ReactNode;
  tone?: StatTone;
  progress?: number;
  progressLabel?: string;
}) {
  const colors = TONES[tone];
  const fill = progress !== undefined && Number.isFinite(progress) ? Math.min(100, Math.max(0, progress)) : 0;
  return (
    <CardBox className="h-full">
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <p className="text-2xl lg:text-[28px] font-semibold leading-tight text-link dark:text-white tabular-nums break-words">
            {value}
          </p>
          <p className="text-sm text-bodytext mt-1">{label}</p>
        </div>
        {icon && (
          <span
            className={`shrink-0 grid place-items-center h-12 w-12 rounded-full ${colors.soft}`}
            aria-hidden="true"
          >
            {icon}
          </span>
        )}
      </div>
      <div
        className={`mt-5 h-1 w-28 rounded-full overflow-hidden ${colors.soft}`}
        role={progress === undefined ? undefined : "progressbar"}
        title={progressLabel}
        aria-label={progressLabel ?? label}
        aria-valuenow={progress === undefined ? undefined : Math.round(fill)}
        aria-valuemin={progress === undefined ? undefined : 0}
        aria-valuemax={progress === undefined ? undefined : 100}
      >
        <div className={`h-full rounded-full transition-[width] duration-500 motion-reduce:transition-none ${colors.strong}`} style={{ width: `${fill}%` }} />
      </div>
    </CardBox>
  );
}
