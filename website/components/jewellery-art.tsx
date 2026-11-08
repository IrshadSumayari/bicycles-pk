export function JewelleryArt({ kind = "necklaces" }: { kind?: string }) {
  return (
    <svg
      viewBox="0 0 240 220"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
      className="lv-jewellery-art"
    >
      <circle cx="120" cy="110" r="88" fill="currentColor" opacity=".035" />
      {kind === "rings" ? (
        <g stroke="currentColor" strokeWidth="2">
          <ellipse cx="100" cy="126" rx="43" ry="48" />
          <ellipse cx="146" cy="126" rx="39" ry="45" />
          <path d="m86 76 14-20 14 20-14 18Z" />
          <path d="M86 76h28M100 56v38" />
        </g>
      ) : kind === "earrings" ? (
        <g stroke="currentColor" strokeWidth="2">
          <path d="M67 72c-18-24 17-38 17-13v25M157 72c-18-24 17-38 17-13v25" />
          <path d="M84 84c-55 41-40 92 0 92s55-51 0-92ZM174 84c-55 41-40 92 0 92s55-51 0-92Z" />
          <circle cx="84" cy="132" r="12" />
          <circle cx="174" cy="132" r="12" />
        </g>
      ) : kind === "bangles" ? (
        <g stroke="currentColor" strokeWidth="2">
          <ellipse
            cx="98"
            cy="113"
            rx="39"
            ry="65"
            transform="rotate(-20 98 113)"
          />
          <ellipse cx="125" cy="113" rx="39" ry="65" />
          <ellipse
            cx="150"
            cy="113"
            rx="39"
            ry="65"
            transform="rotate(20 150 113)"
          />
        </g>
      ) : kind === "bracelets" || kind === "anklets" ? (
        <g stroke="currentColor" strokeWidth="2">
          <ellipse cx="120" cy="110" rx="67" ry="58" strokeDasharray="7 6" />
          <ellipse cx="120" cy="110" rx="57" ry="48" />
          <path d="m120 158 13 19-13 18-13-18Z" />
          <circle cx="120" cy="51" r="7" />
        </g>
      ) : (
        <g stroke="currentColor" strokeWidth="2">
          <path d="M49 52c0 78 23 111 71 111s71-33 71-111M60 52c0 68 20 99 60 99s60-31 60-99" />
          <path d="m120 157 17 22-17 24-17-24Z" />
          <path d="M103 179h34M120 157v46" />
          {kind === "jewellery-sets" && (
            <>
              <circle cx="46" cy="158" r="14" />
              <circle cx="194" cy="158" r="14" />
              <path d="M46 144v-15M194 144v-15" />
            </>
          )}
        </g>
      )}
    </svg>
  );
}
