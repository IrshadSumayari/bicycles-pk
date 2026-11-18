import Link from "next/link";
export default function NotFound() {
  return (
    <div className="empty-state">
      <h1>Page not found</h1>
      <p>Let’s find something made for you.</p>
      <Link className="button" href="/">
        Return home
      </Link>
    </div>
  );
}
