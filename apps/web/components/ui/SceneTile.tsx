import { useId } from "react";
import type { Scene } from "@/content/posts";

// Flat drawn rooms for the feed tiles (no photos of a real home). Static SVG, no motion.
const PALETTE: Record<Scene, [string, string]> = {
  hallway: ["#ffd9a8", "#f39c6b"],
  shelf: ["#c7d8ff", "#6f8fd6"],
  kitchen: ["#c9f0dc", "#4fae86"],
  desk: ["#f3d6ff", "#a970d6"],
  sofa: ["#ffe3a8", "#e0a332"],
  bedside: ["#d7d2ff", "#6b62c9"],
  door: ["#ffd0d6", "#d96a7f"],
};

export function SceneTile({ scene }: { scene: Scene }) {
  const [light, dark] = PALETTE[scene];
  // the same scene appears in several cards; ids must stay unique on the page
  const id = useId();
  return (
    <svg viewBox="0 0 120 120" preserveAspectRatio="xMidYMid slice" className="size-full" aria-hidden="true">
      <defs>
        <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={light} />
          <stop offset="1" stopColor={dark} />
        </linearGradient>
      </defs>
      <rect width="120" height="120" fill={`url(#${id})`} />
      <rect y="92" width="120" height="28" fill="#000" opacity="0.12" />
      {scene === "hallway" && (
        <>
          <rect x="44" y="30" width="32" height="62" rx="2" fill="#fff" opacity="0.75" />
          <rect x="18" y="58" width="22" height="4" fill="#5a3b22" />
          <circle cx="29" cy="54" r="4" fill="#3b5998" />
        </>
      )}
      {scene === "shelf" && (
        <>
          {[40, 60, 80].map((y) => (
            <rect key={y} x="20" y={y} width="80" height="4" fill="#3b2a1a" opacity="0.7" />
          ))}
          <rect x="30" y="47" width="10" height="13" fill="#fff" />
          <circle cx="70" cy="55" r="5" fill="#ffd34d" />
          <rect x="56" y="66" width="18" height="14" fill="#29487d" />
        </>
      )}
      {scene === "kitchen" && (
        <>
          <rect x="10" y="66" width="100" height="26" fill="#fff" opacity="0.8" />
          <rect x="22" y="40" width="26" height="18" rx="3" fill="#fff" opacity="0.6" />
          <circle cx="82" cy="58" r="8" fill="#e85d4a" />
        </>
      )}
      {scene === "desk" && (
        <>
          <rect x="16" y="64" width="88" height="6" fill="#3b2a1a" opacity="0.75" />
          <rect x="40" y="40" width="40" height="24" rx="2" fill="#1c1e21" opacity="0.8" />
          <rect x="44" y="44" width="32" height="16" fill="#9fd3ff" />
        </>
      )}
      {scene === "sofa" && (
        <>
          <rect x="14" y="56" width="92" height="30" rx="8" fill="#b04d3a" />
          <rect x="14" y="48" width="18" height="38" rx="6" fill="#933f2f" />
          <rect x="88" y="48" width="18" height="38" rx="6" fill="#933f2f" />
          <rect x="88" y="44" width="14" height="5" rx="2" fill="#1c1e21" />
        </>
      )}
      {scene === "bedside" && (
        <>
          <rect x="38" y="60" width="44" height="32" rx="3" fill="#f6efe6" />
          <rect x="52" y="34" width="16" height="22" rx="3" fill="#ffe08a" />
          <rect x="46" y="56" width="10" height="5" rx="2" fill="#7a4b2a" />
        </>
      )}
      {scene === "door" && (
        <>
          <rect x="38" y="22" width="44" height="70" rx="3" fill="#fff" opacity="0.85" />
          <circle cx="74" cy="58" r="3" fill="#29487d" />
        </>
      )}
    </svg>
  );
}
