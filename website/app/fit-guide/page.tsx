import Link from "next/link";
import { ArrowRight } from "lucide-react";
export const metadata = {
  title: "Bike size guide",
  description: "Choose a bicycle frame or wheel size by rider height and age.",
};
// General guidance only; each product lists its own sizes and rider ranges.
const adult = [
  ["XS", "148–158 cm", '13–14"', "47–49 cm"],
  ["S", "158–168 cm", '15–16"', "50–52 cm"],
  ["M", "168–178 cm", '17–18"', "53–55 cm"],
  ["L", "178–188 cm", '19–20"', "56–58 cm"],
  ["XL", "188–198 cm", '21–22"', "59–61 cm"],
];
const kids = [
  ['10–12"', "2–4 years", "85–100 cm"],
  ['14"', "3–5 years", "95–110 cm"],
  ['16"', "4–6 years", "105–120 cm"],
  ['20"', "6–9 years", "115–135 cm"],
  ['24"', "8–12 years", "130–150 cm"],
];
export default function SizeGuide() {
  return (
    <article className="lv-guide">
      <p className="lv-eyebrow">BICYCLES.PK SIZE GUIDE</p>
      <h1>
        Find your
        <br />
        <em>frame size.</em>
      </h1>
      <p className="lv-lead">
        Use your height as a starting point. Between two sizes? Choose the
        smaller frame for easier handling or the larger one for a stretched-out
        position, and check the sizes listed on each product.
      </p>
      <section className="lv-guide-note" aria-labelledby="adult-sizes">
        <h2 id="adult-sizes">Adult bikes</h2>
        <div className="overflow-x-auto">
          <table className="lv-size-table">
            <thead>
              <tr>
                <th>Size</th>
                <th>Rider height</th>
                <th>Mountain / hybrid frame</th>
                <th>Road / gravel frame</th>
              </tr>
            </thead>
            <tbody>
              {adult.map(([size, height, mtb, road]) => (
                <tr key={size}>
                  <th scope="row">{size}</th>
                  <td>{height}</td>
                  <td>{mtb}</td>
                  <td>{road}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
      <section className="lv-guide-note" aria-labelledby="kids-sizes">
        <h2 id="kids-sizes">Kids bikes</h2>
        <p>Kids bikes are sized by wheel. Your child should reach the ground with the balls of both feet while seated.</p>
        <div className="overflow-x-auto">
          <table className="lv-size-table">
            <thead>
              <tr>
                <th>Wheel</th>
                <th>Typical age</th>
                <th>Child height</th>
              </tr>
            </thead>
            <tbody>
              {kids.map(([wheel, age, height]) => (
                <tr key={wheel}>
                  <th scope="row">{wheel}</th>
                  <td>{age}</td>
                  <td>{height}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
      <p className="muted">
        Not sure? <Link href="/pages/contact">Contact us</Link> with the
        rider’s height and inside-leg measurement and we’ll help you choose.
      </p>
      <Link className="lv-button" href="/bicycles">
        Shop bicycles <ArrowRight size={17} />
      </Link>
    </article>
  );
}
