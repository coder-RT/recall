/**
 * The mug from the landing story: a cartoon mug with a face, arms and legs (original art).
 * Drawn around its own origin (0,0 = middle of the floor line under it), about 70 × 80 units.
 * The markup shows it awake and happy; the story timeline hides the face and arms first.
 * Parts GSAP animates: [data-eyes-closed], [data-eyes], [data-smile], [data-arm-l], [data-arm-r].
 */
export function HappyMug() {
  const ink = "#1c1e21";
  return (
    <g>
      <ellipse cx="0" cy="2" rx="30" ry="5" fill="#000" opacity="0.12" />
      {/* legs */}
      <path d="M-10 -12 v10 h-6 M10 -12 v10 h6" fill="none" stroke={ink} strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round" />
      {/* arms, pivoting at the shoulder */}
      <g data-arm-l>
        <path d="M-24 -40 q-12 6 -14 16" fill="none" stroke={ink} strokeWidth="3.5" strokeLinecap="round" />
        <circle cx="-38" cy="-24" r="4" fill={ink} />
      </g>
      <g data-arm-r>
        <path d="M24 -40 q12 6 14 16" fill="none" stroke={ink} strokeWidth="3.5" strokeLinecap="round" />
        <circle cx="38" cy="-24" r="4" fill={ink} />
      </g>
      {/* handle and body */}
      <path d="M24 -56 h6 a11 11 0 0 1 0 22 h-6" fill="none" stroke={ink} strokeWidth="4" />
      <rect x="-25" y="-70" width="50" height="58" rx="10" fill="#fff8ef" stroke={ink} strokeWidth="3" />
      <rect x="-23.5" y="-34" width="47" height="12" fill="#3b5998" />
      <ellipse cx="0" cy="-66" rx="20" ry="3.5" fill="#6b3e1f" />
      <path d="M-18 -62 q-2 14 0 22" fill="none" stroke="#fff" strokeWidth="2.5" strokeLinecap="round" opacity="0.8" />
      {/* face */}
      <g data-eyes-closed opacity="0">
        <path d="M-12 -50 h7 M5 -50 h7" stroke={ink} strokeWidth="2.5" strokeLinecap="round" />
      </g>
      <g data-eyes>
        <circle cx="-8" cy="-50" r="3.6" fill={ink} />
        <circle cx="8" cy="-50" r="3.6" fill={ink} />
        <circle cx="-7" cy="-51.2" r="1.1" fill="#fff" />
        <circle cx="9" cy="-51.2" r="1.1" fill="#fff" />
      </g>
      <path data-smile d="M-7 -43 q7 7 14 0" fill="none" stroke={ink} strokeWidth="2.5" strokeLinecap="round" />
    </g>
  );
}
