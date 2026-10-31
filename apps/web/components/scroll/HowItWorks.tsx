"use client";

import { useRef } from "react";
import { TiltCard } from "@/components/ui/TiltCard";
import { format } from "@/i18n";
import { useT } from "@/i18n/I18nProvider";
import { gsap, MOTION_OK, ScrollTrigger, useGSAP } from "@/lib/gsap";
import { useMotionPrefs } from "@/lib/motion-prefs";

const ICONS = ["📱", "🗣️", "🧭"];

/**
 * Three step cards. On wide screens a dotted route draws through numbered stops above them as you
 * scroll, lighting each card when it arrives. GSAP owns the route and the <li> wrappers; the tilt
 * inside each card is Motion. The server HTML has every step lit.
 */
export function HowItWorks() {
  const root = useRef<HTMLElement>(null);
  const { reduced } = useMotionPrefs();
  const t = useT();
  const steps = t.how.steps;

  useGSAP(
    () => {
      if (reduced) return;
      const marks = gsap.utils.toArray<HTMLElement>("[data-step], [data-stop]");
      const mm = gsap.matchMedia();
      mm.add({ desktop: `(min-width: 1024px) and ${MOTION_OK}`, mobile: `(max-width: 1023px) and ${MOTION_OK}` }, (ctx) => {
        gsap.from("[data-how-head] > *", {
          y: 20,
          autoAlpha: 0,
          stagger: 0.08,
          duration: 0.6,
          ease: "power2.out",
          scrollTrigger: { trigger: root.current, start: "top 75%", once: true },
        });

        if (!ctx.conditions?.desktop) {
          ScrollTrigger.batch("[data-step]", {
            start: "top 85%",
            once: true,
            onEnter: (batch) => gsap.from(batch, { y: 40, autoAlpha: 0, stagger: 0.12, duration: 0.6, ease: "power2.out" }),
          });
          return;
        }

        // light step i (its stop and its card) once the route has reached it; the line runs from
        // stop 1 to stop 3, so stop 2 is reached halfway
        const light = (progress: number) => {
          const reached = 1 + Math.floor(progress * (steps.length - 1) + 0.02);
          marks.forEach((el) => (el.dataset.active = String(Number(el.dataset.index) < reached)));
        };
        light(0);
        gsap.fromTo(
          "[data-route-line]",
          { clipPath: "inset(0 100% 0 0)" },
          {
            clipPath: "inset(0 0% 0 0)",
            ease: "none",
            scrollTrigger: {
              trigger: "[data-steps]",
              // from the cards coming into view to their bottom edge entering it, so every step is
              // lit by the time all three are fully visible
              start: "top 85%",
              end: "bottom 95%",
              scrub: 0.5,
              onUpdate: (self) => light(self.progress),
            },
          },
        );
      });
      return () => {
        mm.revert();
        // revert() restores styles, not data attributes: without the scene every step stays lit
        marks.forEach((el) => (el.dataset.active = "true"));
      };
    },
    { scope: root, dependencies: [reduced], revertOnUpdate: true },
  );

  return (
    <section ref={root} id="how" aria-labelledby="how-title" className="scroll-mt-16 bg-fb-blue py-20 text-white">
      <div className="mx-auto w-full max-w-6xl px-4">
        <div data-how-head>
          <p className="font-classic text-sm font-bold uppercase tracking-[0.2em] text-fb-blue-pale">{t.how.eyebrow}</p>
          <h2 id="how-title" className="mt-2 text-4xl font-extrabold sm:text-5xl">
            {t.how.title}
          </h2>
        </div>

        <div data-steps className="mt-12">
          {/* route: numbered stops joined by a dotted line, one stop per card column */}
          <div aria-hidden="true" className="relative mb-8 hidden grid-cols-3 lg:grid">
            <div
              data-route-line
              className="absolute left-[calc(100%/6)] right-[calc(100%/6)] top-1/2 -translate-y-1/2 border-t-4 border-dotted border-white/80"
            />
            {steps.map((step, i) => (
              <div key={step.title} className="relative flex justify-center">
                <span
                  data-stop
                  data-index={i}
                  data-active="true"
                  className="grid size-12 place-items-center rounded-full border-4 border-white/50 bg-fb-blue text-lg font-extrabold text-white/70 transition-all duration-500 data-[active=true]:scale-110 data-[active=true]:border-white data-[active=true]:bg-white data-[active=true]:text-fb-blue-dark"
                >
                  {i + 1}
                </span>
              </div>
            ))}
          </div>

          <ol className="grid gap-6 lg:grid-cols-3">
            {steps.map((step, i) => (
              <li
                key={step.title}
                data-step
                data-index={i}
                data-active="true"
                // CSS transition on desktop only: on mobile GSAP fades these in and the two would fight
                className="translate-y-3 opacity-55 data-[active=true]:translate-y-0 data-[active=true]:opacity-100 lg:transition-all lg:duration-500 lg:ease-out"
              >
                <TiltCard className="card flex h-full flex-col p-7 text-ink">
                  <div className="flex flex-wrap items-center gap-4">
                    <span className="ig-ring grid size-16 shrink-0 place-items-center rounded-full p-[3px]">
                      <span className="grid size-full place-items-center rounded-full bg-white text-3xl" aria-hidden="true">
                        {ICONS[i]}
                      </span>
                    </span>
                    <div>
                      <p className="font-classic text-sm font-bold text-fb-blue-dark">{format(t.how.stepOf, { n: i + 1, total: steps.length })}</p>
                      <h3 className="text-2xl font-extrabold">{step.title}</h3>
                    </div>
                  </div>
                  <p className="mt-5 flex-1 text-lg leading-relaxed text-ink">{step.body}</p>
                  <p className="mt-5 border-t border-fb-line pt-3 font-classic text-sm text-muted">{step.meta}</p>
                </TiltCard>
              </li>
            ))}
          </ol>
        </div>
      </div>
    </section>
  );
}
