// Original line illustrations of bag shapes, shown until a category has a
// published product photograph.
const shapes: Record<string, React.ReactNode> = {
  "tote-bags": (
    <>
      <path d="M52 86h136l-12 98H64Z" />
      <path d="M86 86c0-44 68-44 68 0M98 86c0-30 44-30 44 0" />
      <path d="M64 108h112" opacity=".45" />
    </>
  ),
  "shoulder-bags": (
    <>
      <path d="M58 112c0-14 10-22 24-22h76c14 0 24 8 24 22v46c0 16-10 24-26 24H84c-16 0-26-8-26-24Z" />
      <path d="M70 92c4-58 96-58 100 0" />
      <path d="M58 128h124M114 128v16h12v-16" />
    </>
  ),
  "crossbody-bags": (
    <>
      <path d="M70 118h100v54a10 10 0 0 1-10 10H80a10 10 0 0 1-10-10Z" />
      <path d="M70 118l50 30 50-30" />
      <circle cx="120" cy="150" r="5" />
      <path d="M74 118 40 30M166 118l34-88" strokeDasharray="5 6" />
    </>
  ),
  "top-handle-bags": (
    <>
      <path d="M56 106h128l-6 78H62Z" />
      <path d="M96 106V88c0-22 48-22 48 0v18" />
      <path d="M56 106l64 32 64-32" />
      <rect x="112" y="132" width="16" height="12" rx="2" />
    </>
  ),
  clutches: (
    <>
      <path d="M40 92h160v76a10 10 0 0 1-10 10H50a10 10 0 0 1-10-10Z" />
      <path d="M40 92l80 44 80-44" />
      <path d="M112 132h16v12h-16Z" />
    </>
  ),
  "mini-bags": (
    <>
      <path d="M86 118h68v52a8 8 0 0 1-8 8H94a8 8 0 0 1-8-8Z" />
      <path d="M92 118c0-34 56-34 56 0" />
      <path d="M86 136h68" />
      <circle cx="120" cy="148" r="4" />
    </>
  ),
  backpacks: (
    <>
      <path d="M72 84c0-26 96-26 96 0v90a10 10 0 0 1-10 10H82a10 10 0 0 1-10-10Z" />
      <path d="M104 62c0-18 32-18 32 0" />
      <path d="M86 128h68v34H86Z" />
      <path d="M72 96h96" opacity=".45" />
    </>
  ),
  "wallets-purses": (
    <>
      <rect x="48" y="96" width="144" height="84" rx="10" />
      <path d="M48 120h144" />
      <path d="M164 132h28v24h-28a12 12 0 0 1 0-24Z" />
      <circle cx="166" cy="144" r="4" />
    </>
  ),
};

export function BagArt({ kind = "tote-bags" }: { kind?: string }) {
  return (
    <svg
      viewBox="0 0 240 220"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
      className="lv-bag-art"
    >
      <circle cx="120" cy="126" r="90" fill="currentColor" opacity=".04" />
      <g
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        {shapes[kind] ?? shapes["tote-bags"]}
      </g>
    </svg>
  );
}
