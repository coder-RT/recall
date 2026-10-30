"use client";

import { useRef } from "react";
import { gsap, MOTION_OK, useGSAP } from "@/lib/gsap";
import { useT } from "@/i18n/I18nProvider";
import { useMotionPrefs } from "@/lib/motion-prefs";

export type ModelKind = "see" | "map" | "talk" | "listen";

const BLUE = "#3b5998";
const INK = "#1c1e21";
const LINE = "#bdc7d8";

// map: a 5 × 4 floor grid in isometric projection
const GRID = Array.from({ length: 20 }, (_, n) => {
  const i = n % 5;
  const j = Math.floor(n / 5);
  return { x: 80 + (i - j) * 14, y: 34 + (i + j) * 7 };
});
// listen: bar heights of the finished waveform
const BARS = [10, 22, 34, 18, 28, 40, 24, 14, 8];

/** Text drawn as one <tspan> per character, so GSAP can type it out. */
function Typed({ text, ...props }: { text: string } & React.SVGProps<SVGTextElement>) {
  return (
    <text {...props}>
      {[...text].map((ch, i) => (
        <tspan key={i} data-ch>
          {ch}
        </tspan>
      ))}
    </text>
  );
}

/**
 * A small looping illustration of what each model does: seeing, mapping, talking, listening.
 * Illustrations only, not model output. The markup is the finished frame, so reduced motion and
 * no-JS show a complete picture; the loop plays only while the card is on screen.
 */
export function ModelGlyph({ kind }: { kind: ModelKind }) {
  const svg = useRef<SVGSVGElement>(null);
  const { reduced } = useMotionPrefs();
  const t = useT().models.glyph;

  useGSAP(
    () => {
      if (reduced) return;
      const mm = gsap.matchMedia();
      mm.add(MOTION_OK, () => {
        const tl = gsap.timeline({
          repeat: -1,
          repeatDelay: 1.6,
          scrollTrigger: { trigger: svg.current, start: "top bottom", end: "bottom top", toggleActions: "play pause resume pause" },
        });
        const chars = "[data-ch]";
        // reveal text one character at a time
        const type = { attr: { "fill-opacity": 1 }, duration: 0.01, stagger: 0.04 };

        if (kind === "see") {
          tl.from("[data-outline]", { drawSVG: "0%", duration: 1, ease: "power1.inOut" })
            .from("[data-tint]", { opacity: 0, duration: 0.4 }, "-=0.1")
            .from("[data-label]", { scale: 0, transformOrigin: "0% 100%", duration: 0.4, ease: "back.out(3)" });
        } else if (kind === "map") {
          tl.from("[data-dot]", {
            x: () => gsap.utils.random(-50, 50),
            y: () => gsap.utils.random(-30, 30),
            opacity: 0,
            duration: 0.8,
            ease: "power3.out",
            stagger: { amount: 0.6, from: "center" },
          })
            .fromTo("[data-cam]", { x: 0 }, { x: 110, duration: 1.8, ease: "sine.inOut" })
            .fromTo("[data-cone]", { opacity: 0 }, { opacity: 1, duration: 0.3, yoyo: true, repeat: 5 }, "<")
            .to("[data-cam]", { x: 0, duration: 0.6, ease: "power2.inOut" });
        } else if (kind === "talk") {
          // typing dots bounce, then the answer types out
          tl.set(chars, { attr: { "fill-opacity": 0 } })
            .set("[data-typing]", { opacity: 1 })
            .to("[data-typing] circle", { y: -4, duration: 0.22, yoyo: true, repeat: 5, stagger: 0.1, ease: "sine.inOut" })
            .set("[data-typing]", { opacity: 0 })
            .to(chars, type);
        } else {
          tl.set(chars, { attr: { "fill-opacity": 0 } })
            .to("[data-bar]", {
              scaleY: () => gsap.utils.random(0.2, 1.4),
              transformOrigin: "50% 50%",
              duration: 0.16,
              yoyo: true,
              repeat: 9,
              repeatRefresh: true,
              stagger: 0.03,
              ease: "sine.inOut",
            })
            .to("[data-bar]", { scaleY: 1, duration: 0.2 })
            .to(chars, type);
        }
      });
      return () => mm.revert();
    },
    { scope: svg, dependencies: [reduced, kind], revertOnUpdate: true },
  );

  return (
    <svg ref={svg} viewBox="0 0 160 90" className="h-24 w-full" aria-hidden="true">
      {kind === "see" && (
        <>
          <line x1="16" y1="74" x2="144" y2="74" stroke={LINE} strokeWidth="4" strokeLinecap="round" />
          <rect x="62" y="38" width="30" height="34" rx="5" fill="#dfe3ee" stroke={INK} strokeWidth="2" />
          <path d="M92 46 h6 a7 7 0 0 1 0 14 h-6" fill="none" stroke={INK} strokeWidth="2" />
          <rect data-tint x="62" y="38" width="30" height="34" rx="5" fill={BLUE} opacity="0.35" />
          <rect data-outline x="55" y="31" width="52" height="47" rx="7" fill="none" stroke={BLUE} strokeWidth="2.5" />
          <g data-label>
            <rect x="104" y="14" width="34" height="16" rx="8" fill={BLUE} />
            <text x="121" y="22.5" textAnchor="middle" dominantBaseline="central" fontSize="10" fontWeight="700" fill="white">
              {t.label}
            </text>
          </g>
        </>
      )}

      {kind === "map" && (
        <>
          {GRID.map((d, i) => (
            <circle key={i} data-dot cx={d.x} cy={d.y} r="2.6" fill={BLUE} />
          ))}
          <g data-cam>
            <path data-cone d="M24 22 L4 80 L52 80 Z" fill={BLUE} opacity="0.12" />
            <rect x="16" y="12" width="16" height="11" rx="2" fill={INK} />
            <circle cx="24" cy="17.5" r="3" fill="white" />
          </g>
        </>
      )}

      {kind === "talk" && (
        <>
          <rect x="6" y="14" width="148" height="50" rx="14" fill="#f0f2f5" stroke={LINE} strokeWidth="2" />
          <path d="M28 64 L22 78 L40 64" fill="#f0f2f5" stroke={LINE} strokeWidth="2" strokeLinejoin="round" />
          <g data-typing opacity="0">
            <circle cx="66" cy="39" r="4" fill={BLUE} />
            <circle cx="80" cy="39" r="4" fill={BLUE} />
            <circle cx="94" cy="39" r="4" fill={BLUE} />
          </g>
          <Typed text={t.answer} x="80" y="39" textAnchor="middle" dominantBaseline="central" fontSize="10.5" fontWeight="700" fill={INK} />
        </>
      )}

      {kind === "listen" && (
        <>
          {BARS.map((h, i) => (
            <rect key={i} data-bar x={30 + i * 11} y={32 - h / 2} width="6" height={h} rx="3" fill={BLUE} />
          ))}
          <Typed text={t.question} x="80" y="76" textAnchor="middle" fontSize="11" fontWeight="700" fill={INK} />
        </>
      )}
    </svg>
  );
}
