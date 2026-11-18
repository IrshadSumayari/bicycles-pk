import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { adultSizes, kidsSizes } from "../../../shared/fit";
import { SizeFinder } from "@/components/size-finder";
export const metadata = {
  title: "Bike size guide",
  description:
    "Find your bicycle frame or wheel size by rider height, inside leg and age.",
};
// General guidance only; each product lists its own sizes and rider ranges.
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
        Enter the rider’s height to get a size. Between two sizes? Choose the
        smaller frame for easier handling or the larger one for a stretched-out
        position, and check the sizes listed on each product.
      </p>
      <section className="lv-guide-note" aria-labelledby="whats-my-size">
        <h2 id="whats-my-size">What’s my size?</h2>
        <SizeFinder />
      </section>
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
              {adultSizes.map((s) => (
                <tr key={s.size}>
                  <th scope="row">{s.size}</th>
                  <td>
                    {s.minHeight}–{s.maxHeight} cm
                  </td>
                  <td>{s.mtbFrame}</td>
                  <td>{s.roadFrame}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="muted">
          Measuring your inside leg: stand against a wall in socks, put a book
          snugly between your legs and measure from its top edge to the floor.
        </p>
      </section>
      <section className="lv-guide-note" aria-labelledby="kids-sizes">
        <h2 id="kids-sizes">Kids bikes by age</h2>
        <p>
          Kids bikes are sized by wheel. Height matters more than age: your
          child should reach the ground with the balls of both feet while
          seated.
        </p>
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
              {kidsSizes.map((s) => (
                <tr key={s.wheel}>
                  <th scope="row">{s.wheel}</th>
                  <td>
                    {s.minAge}–{s.maxAge} years
                  </td>
                  <td>
                    {s.minHeight}–{s.maxHeight} cm
                  </td>
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
