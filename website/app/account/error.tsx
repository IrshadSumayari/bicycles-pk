"use client";
export default function ErrorPage({ reset }: { reset: () => void }) {
  return (
    <div role="alert">
      <p>We couldn’t load your account. Please try again.</p>
      <button className="button" onClick={reset}>
        Try again
      </button>
    </div>
  );
}
