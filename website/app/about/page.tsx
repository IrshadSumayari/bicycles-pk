import Link from "next/link";
import Image from "next/image";
export const metadata = { title: "Our story" };
export default function About() {
  return (
    <article className="lv-guide">
      <p className="lv-eyebrow">HELLO, WE’RE LADYVOGUE</p>
      <h1>
        Everyday.
        <br />
        <em>Beautifully yours.</em>
      </h1>
      <p className="lv-lead">
        A space for lingerie, nightwear and essentials that put you first.
      </p>
      <div className="lv-about-photo">
        <Image
          src="/ladyvogue/campaign.webp"
          alt="Rose satin and blush lace in a warm, softly lit room"
          fill
          sizes="90vw"
        />
      </div>
      <section className="lv-guide-note">
        <h2>Small things. Personal moments.</h2>
        <p>
          LadyVogue is being created for women in Pakistan who want to bring a
          little more comfort and beauty to their everyday wardrobes. Our focus
          is simple: bras, panties, matching sets and nightwear, with a
          thoughtful shopping experience.
        </p>
        <p>
          From choosing your first layer to finding something for a quiet
          evening, this is a space to discover your own kind of confidence.
        </p>
      </section>
      <Link className="lv-button" href="/#collections">
        Discover the collection
      </Link>
    </article>
  );
}
