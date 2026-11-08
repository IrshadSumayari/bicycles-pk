import type { MeasurementKey } from "../../shared/productGuide";
import { measurementLabels } from "../../shared/productGuide";
export function MeasurementIllustration({ kind }: { kind: MeasurementKey }) {
  const y = { underbust: 101, bust: 77, waist: 139, hips: 184 }[kind];
  return (
    <svg
      viewBox="0 0 240 240"
      role="img"
      aria-label={measurementLabels[kind] + ": tape level around the body"}
      className="lv-measurement-art"
    >
      <title>{measurementLabels[kind] + " measurement position"}</title>
      <path
        d="M93 27 Q120 42 147 27 L170 43 Q160 70 157 94 Q148 124 150 143 Q170 169 173 207 L147 220 Q120 210 93 220 L67 207 Q70 169 90 143 Q92 124 83 94 Q80 70 70 43 Z"
        fill="var(--lv-soft)"
        stroke="currentColor"
        strokeWidth="1.5"
      />
      <path
        d="M93 27 Q120 60 147 27 M90 143 Q120 150 150 143"
        fill="none"
        stroke="currentColor"
        opacity=".3"
      />
      <ellipse
        cx="120"
        cy={y}
        rx={kind === "hips" ? 53 : kind === "waist" ? 30 : 42}
        ry="10"
        fill="none"
        stroke="var(--lv-rose, #b76785)"
        strokeWidth="4"
        strokeDasharray="5 3"
      />
      <path d={`M184 ${y}h28m-5-5 5 5-5 5`} fill="none" stroke="currentColor" />
    </svg>
  );
}
