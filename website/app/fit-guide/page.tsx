import Link from "next/link";
import { ArrowRight, Ruler } from "lucide-react";
import { MeasurementIllustration } from "@/components/measurement-illustration";
import type { MeasurementKey } from "../../../shared/productGuide";
export const metadata = { title: "Find your fit" };
const steps: { kind: MeasurementKey; title: string; text: string }[] = [
  {
    kind: "underbust",
    title: "01 / Underbust",
    text: "Wrap a soft tape around your ribcage directly below your bust. Keep it level and comfortably snug. Record the measurement and unit; this is not automatically your bra band size.",
  },
  {
    kind: "bust",
    title: "02 / Bust",
    text: "Measure around the fullest part of your bust. Keep the tape level across your back without pressing into your body. Compare bust and underbust with the supplier chart for your chosen bra.",
  },
  {
    kind: "waist",
    title: "03 / Waist",
    text: "Measure around your natural waist, usually the narrowest part of your torso. Stand relaxed and breathe normally. Keep the tape close without pulling it tight.",
  },
  {
    kind: "hips",
    title: "04 / Hips",
    text: "With your feet together, measure around the fullest part of your hips and seat. Keep the tape parallel to the floor. Use waist and hip measurements for panties and nightwear.",
  },
];
export default function FitGuide() {
  return (
    <article className="lv-guide">
      <p className="lv-eyebrow">THE LADYVOGUE FIT GUIDE</p>
      <Ruler size={36} strokeWidth={1} aria-hidden="true" />
      <h1>
        Good fit.
        <br />
        <em>Beautiful confidence.</em>
      </h1>
      <p className="lv-lead">
        A few careful measurements. A more considered choice.
      </p>
      <section className="lv-guide-note">
        <h2>Before you begin</h2>
        <p>
          Use a soft measuring tape and a mirror to check that it stays level.
          Measure over light clothing or a comfortable, unpadded bra where
          appropriate. Record your measurements in centimetres (cm) or inches
          (in), using the same unit as the product chart.
        </p>
        <p>
          You can keep your measurements privately. This guide does not ask you
          to submit or save them.
        </p>
      </section>
      <div className="lv-guide-grid lv-measurement-grid">
        {steps.map((s) => (
          <section key={s.kind}>
            <MeasurementIllustration kind={s.kind} />
            <h2>{s.title}</h2>
            <p>{s.text}</p>
          </section>
        ))}
      </div>
      <section className="lv-guide-note">
        <h2>Read the chart for your product.</h2>
        <p>
          Check the supplier, unit and whether the chart describes body or
          garment measurements. Body measurements compare with your own; garment
          measurements compare with a similar garment that fits you. A garment
          chart is not a body-size recommendation.
        </p>
        <p>
          Band and cup labels vary between suppliers. UK, EU and US systems can
          differ, and DD and E are not automatically interchangeable. Follow the
          named supplier chart. We do not provide a universal size conversion or
          a fit guarantee.
        </p>
        <p>
          If no chart or a needed measurement is supplied, please{" "}
          <Link href="/pages/contact">contact us</Link> with the product name
          before choosing a size. Do not guess missing measurements.
        </p>
      </section>
      <section className="lv-guide-note">
        <h2>Check how it feels.</h2>
        <p>
          A comfortable bra band sits level, cups contain the bust without
          gaping or digging in, and straps feel supportive without pulling. For
          panties and nightwear, check comfort at the waist and hips and allow
          for how you like to move. Check the product’s fit notes, included
          pieces and care instructions when supplied.
        </p>
      </section>
      <Link className="lv-button" href="/search?category=Bras">
        Explore bras <ArrowRight size={17} />
      </Link>
    </article>
  );
}
