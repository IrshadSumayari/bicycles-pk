import Link from "next/link";
export const metadata = { title: "About us" };
export default function About() {
  return (
    <article className="lv-guide">
      <p className="lv-eyebrow">HELLO, WE’RE BICYCLES.PK</p>
      <h1>
        Ride further.
        <br />
        <em>Ride better.</em>
      </h1>
      <p className="lv-lead">
        Bicycles for every age and every road, with the accessories and parts
        to keep you riding.
      </p>
      <section className="lv-guide-note">
        <h2>Bikes for everyone.</h2>
        <p>
          Bicycles.pk brings together city and commuter bikes, kids bikes,
          sports bikes, e-bikes, accessories and spare parts, with help choosing
          the right size and delivery across Pakistan.
        </p>
      </section>
      <Link className="lv-button" href="/#collections">
        Shop by section
      </Link>
    </article>
  );
}
