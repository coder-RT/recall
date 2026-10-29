"use client";

import { useRef } from "react";
import { useT } from "@/i18n/I18nProvider";
import { gsap, MOTION_OK, useGSAP } from "@/lib/gsap";
import { useMotionPrefs } from "@/lib/motion-prefs";
import { oncePerPass } from "@/lib/once-per-pass";
import { useReactions } from "@/lib/reactions";

// Route on the floor plan, start (you) to finish (keys); drawn as the steps play.
const ROUTE = "M70 300 L70 220 L190 220 L190 120 L250 120";

/** Clock-face directions: a pinned scene on desktop where scroll plays the route step by step. */
export function ClockRoute() {
  const root = useRef<HTMLElement>(null);
  const { reduced } = useMotionPrefs();
  const burst = useReactions();
  const t = useT();
  const directions = t.directions.steps;

  useGSAP(
    () => {
      if (reduced) return;
      const mm = gsap.matchMedia();
      const items = gsap.utils.toArray<HTMLElement>("[data-direction]");
      mm.add({ desktop: `(min-width: 1024px) and ${MOTION_OK}`, mobile: `(max-width: 1023px) and ${MOTION_OK}` }, (ctx) => {
        const desktop = Boolean(ctx.conditions?.desktop);
        const found = oncePerPass();
        const tl = gsap.timeline({
          defaults: { ease: "power1.inOut" },
          scrollTrigger: {
            trigger: root.current,
            // desktop pins the scene; mobile plays it while the section scrolls past
            start: desktop ? "top top" : "top 70%",
            end: desktop ? "+=140%" : "bottom 60%",
            pin: desktop,
            scrub: 0.6,
            onUpdate: (self) => {
              const active = Math.min(items.length - 1, Math.floor(self.progress * items.length));
              items.forEach((el, i) => (el.dataset.active = String(i <= active)));
              // arriving at the keys: they float up with hearts; re-arms after scrolling back
              if (self.progress > 0.97 && self.direction === 1) {
                found.fire(() => {
                  const goal = root.current?.querySelector("[data-goal]");
                  if (goal) burst({ from: goal, hero: "key", items: ["heart", "love", "heartHands", "like"], count: 18, celebrate: true, until: root.current ?? undefined });
                });
              } else if (self.progress < 0.5) found.rearm();
            },
          },
        });
        tl.from("[data-path]", { drawSVG: "0%", duration: 1 }, 0);
        directions.forEach((step, i) => {
          tl.to("[data-hand]", { rotation: step.clock * 30, svgOrigin: "100 100", duration: 0.2 }, i * 0.25);
        });
        tl.from("[data-goal]", { scale: 0, transformOrigin: "50% 50%", duration: 0.15, ease: "back.out(3)" }, 0.85);
      });
      return () => {
        mm.revert();
        // revert() restores styles, not data attributes: without the scene every step stays highlighted
        items.forEach((el) => (el.dataset.active = "true"));
      };
    },
    { scope: root, dependencies: [reduced, burst], revertOnUpdate: true },
  );

  return (
    <section ref={root} id="directions" aria-labelledby="dir-title" className="scroll-mt-16 bg-white py-20 lg:flex lg:min-h-dvh lg:items-center">
      <div className="mx-auto grid w-full max-w-6xl items-center gap-12 px-4 lg:grid-cols-2">
        <div>
          <p className="classic-label">{t.directions.eyebrow}</p>
          <h2 id="dir-title" className="mt-4 text-4xl font-extrabold text-ink sm:text-5xl">
            {t.directions.title}
          </h2>
          <p className="mt-4 text-lg leading-relaxed text-muted">
            {t.directions.intro}
          </p>
          <ol className="mt-8 grid gap-3">
            {directions.map((step) => (
              <li
                key={step.text}
                data-direction
                data-active="true"
                className="rounded-xl border-l-4 border-fb-line bg-fb-grey px-4 py-3 transition-colors duration-300 data-[active=true]:border-fb-blue data-[active=true]:bg-fb-blue-pale"
              >
                <p className="text-lg font-bold text-ink">{step.text}</p>
                <p className="text-muted">{step.detail}</p>
              </li>
            ))}
          </ol>
          <p className="mt-4 font-classic text-xs text-muted">{t.directions.note}</p>
        </div>

        <div className="grid grid-cols-2 items-center gap-6" aria-hidden="true">
          <svg viewBox="0 0 200 200" className="w-full">
            <circle cx="100" cy="100" r="92" fill="#f0f2f5" stroke="#3b5998" strokeWidth="4" />
            {Array.from({ length: 12 }, (_, i) => {
              const a = (i * 30 - 90) * (Math.PI / 180);
              return (
                <text
                  key={i}
                  // rounded: server and browser trig differ in the last digits, which breaks hydration
                  x={Math.round((100 + Math.cos(a) * 74) * 100) / 100}
                  y={Math.round((100 + Math.sin(a) * 74) * 100) / 100}
                  textAnchor="middle"
                  dominantBaseline="central"
                  fontSize="15"
                  fontWeight="700"
                  fill="#1c1e21"
                >
                  {i === 0 ? 12 : i}
                </text>
              );
            })}
            <g data-hand>
              <line x1="100" y1="100" x2="100" y2="40" stroke="#3b5998" strokeWidth="6" strokeLinecap="round" />
              <circle cx="100" cy="100" r="8" fill="#3b5998" />
            </g>
          </svg>
          <svg viewBox="0 0 300 340" className="w-full">
            <rect x="20" y="20" width="260" height="300" rx="14" fill="#f0f2f5" stroke="#bdc7d8" strokeWidth="4" />
            <path d="M20 170 H140 M220 20 V170 H280" fill="none" stroke="#bdc7d8" strokeWidth="4" />
            <path data-path d={ROUTE} fill="none" stroke="#3b5998" strokeWidth="8" strokeLinecap="round" strokeLinejoin="round" />
            <circle cx="70" cy="300" r="12" fill="#1c1e21" />
            <g data-goal>
              <circle cx="250" cy="120" r="18" fill="white" stroke="#3b5998" strokeWidth="4" />
              <text x="250" y="121" textAnchor="middle" dominantBaseline="central" fontSize="18">
                🔑
              </text>
            </g>
          </svg>
        </div>
      </div>
    </section>
  );
}
