import Image from "next/image";
import Link from "next/link";
import { ShieldCheck, Truck, Wrench } from "lucide-react";
import home from "@/content/home.json";
const icons = { shield: ShieldCheck, wrench: Wrench, truck: Truck } as const;
// Full-bleed homepage hero: video when content/home.json names one,
// otherwise the hero image. The header overlays it on the homepage.
export function LandingHero() {
  const { hero, usps } = home;
  return (
    <section className="lv-landing-hero" aria-labelledby="hero-title">
      <div className="lv-landing-media">
        {hero.video ? (
          <video
            autoPlay
            muted
            loop
            playsInline
            poster={hero.poster || undefined}
            aria-label={hero.imageAlt}
          >
            <source src={hero.video} />
          </video>
        ) : (
          <Image
            src={hero.image}
            alt={hero.imageAlt}
            fill
            priority
            sizes="100vw"
            style={{ objectFit: "cover", objectPosition: hero.imagePosition }}
          />
        )}
      </div>
      <div className="lv-landing-copy">
        <h1 id="hero-title">
          {hero.headline.map((line) => (
            <span key={line}>{line}</span>
          ))}
        </h1>
        <p>{hero.subline}</p>
        <Link className="lv-pill-button" href={hero.cta.href}>
          {hero.cta.label}
        </Link>
      </div>
      <ul className="lv-landing-usps" aria-label="Why ride with us">
        {usps.map((usp) => {
          const Icon = icons[usp.icon as keyof typeof icons] ?? ShieldCheck;
          return (
            <li key={usp.title}>
              <Icon size={26} strokeWidth={1.5} aria-hidden="true" />
              <span>
                <strong>{usp.title}</strong>
                {usp.text}
              </span>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
