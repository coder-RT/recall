"use client";

import { useRef } from "react";
import { AskCard } from "@/components/ui/AskCard";
import { BrailleText } from "@/components/ui/BrailleText";
import { CyclingHeadline } from "@/components/ui/CyclingHeadline";
import { brailleCells, dotPosition, GLYPH, matrixDots, orbPoints, wordWidth } from "@/lib/braille";
import { gsap, MOTION_OK, ScrollTrigger, useGSAP } from "@/lib/gsap";
import { useMotionPrefs } from "@/lib/motion-prefs";
import { useT } from "@/i18n/I18nProvider";
import { site } from "@/lib/site";
import { ConnectedHome } from "./ConnectedHome";
import { HeroFloaters } from "./HeroFloaters";

const WORD = "RECALL";
const PITCH = 10; // svg units per grid step
const DOT_R = 4.2;
// one strong colour per letter, like falling pieces; each ≥ 5:1 on the page grey
const LETTER_COLOURS = ["#3b5998", "#c2185b", "#7b2cbf", "#3f4fc4", "#a8431a", "#29487d"];


const WIDTH = wordWidth(WORD) * PITCH;
const CENTRE = { x: WIDTH / 2, y: (GLYPH.rows * PITCH) / 2 };

// The word as dots (targets) and the same dots on a sphere (orb). Rendered at the targets, so
// server HTML, no-JS and reduced motion all show the finished word.
const lit = matrixDots(WORD).map((d) => ({ ...d, tx: d.x * PITCH + 5, ty: d.y * PITCH + 5 }));
const orb = orbPoints(lit.length);
const ghost = [...WORD].flatMap((_, letter) =>
  Array.from({ length: GLYPH.cols * GLYPH.rows }, (_, i) => ({
    x: (letter * (GLYPH.cols + GLYPH.gap) + (i % GLYPH.cols)) * PITCH + 5,
    y: Math.floor(i / GLYPH.cols) * PITCH + 5,
  })),
);

// ⠠⠠⠗⠑⠉⠁⠇⠇: eight cells centred under the word, standard Braille proportions.
const cells = brailleCells(WORD, { capsWord: true });
const BRAILLE = { top: (GLYPH.rows + 2) * PITCH, dot: 14, cell: 34 };
const brailleLeft = (WIDTH - ((cells.length - 1) * BRAILLE.cell + BRAILLE.dot)) / 2;
const brailleDots = cells.flatMap((cell, i) =>
  cell.dots.map((d) => {
    const { col, row } = dotPosition(d);
    return { cell: i, indicator: cell.indicator, x: brailleLeft + i * BRAILLE.cell + col * BRAILLE.dot, y: BRAILLE.top + row * BRAILLE.dot };
  }),
);
const HEIGHT = BRAILLE.top + 2 * BRAILLE.dot + 8;

const ORB_RADIUS = 62;
const SPREAD = 0.55; // how far apart in time the dots leave the orb, left to right
const clamp01 = (v: number) => Math.min(1, Math.max(0, v));
const smooth = (v: number) => v * v * (3 - 2 * v);

export function BrailleHero() {
  const root = useRef<HTMLElement>(null);
  const svgRef = useRef<SVGSVGElement>(null);
  const { reduced } = useMotionPrefs();
  const t = useT();

  useGSAP(
    () => {
      if (reduced) return;
      const mm = gsap.matchMedia();
      mm.add(MOTION_OK, () => {
        const svg = svgRef.current!;
        const dots = Array.from(svg.querySelectorAll<SVGCircleElement>("[data-dot]"));
        const ghostLayer = svg.querySelector<SVGGElement>("[data-ghost]")!;
        const brailleLayer = svg.querySelector<SVGGElement>("[data-braille-row]")!;
        const state = { intro: 0, scroll: 0, angle: 0 };
        const pointer = { x: -1e4, y: -1e4 };
        const push = lit.map(() => ({ x: 0, y: 0 }));

        const render = () => {
          const t = gsap.ticker.time;
          const p = state.intro * (1 - state.scroll);
          const cosA = Math.cos(state.angle);
          const sinA = Math.sin(state.angle);
          const tilt = 0.45;
          dots.forEach((el, i) => {
            const target = lit[i];
            const o = orb[i];
            // rotate the sphere around y, tilt it towards the viewer, then project
            const x1 = o.x * cosA + o.z * sinA;
            const z1 = -o.x * sinA + o.z * cosA;
            const y2 = o.y * Math.cos(tilt) - z1 * Math.sin(tilt);
            const z2 = o.y * Math.sin(tilt) + z1 * Math.cos(tilt);
            const depth = (z2 + 1) / 2; // 0 back … 1 front
            const ox = CENTRE.x + x1 * ORB_RADIUS;
            const oy = CENTRE.y + y2 * ORB_RADIUS;

            // each dot leaves the orb a little later the further right its letter dot is
            const delay = (target.tx / WIDTH) * SPREAD;
            const k = smooth(clamp01(p * (1 + SPREAD) - delay));

            // formed word: gentle drift, and dots step out of the pointer's way
            const dx = target.tx - pointer.x;
            const dy = target.ty - pointer.y;
            const dist = Math.hypot(dx, dy) || 1;
            const force = k > 0.98 && dist < 32 ? (1 - dist / 32) * 9 : 0;
            push[i].x += ((dx / dist) * force - push[i].x) * 0.15;
            push[i].y += ((dy / dist) * force - push[i].y) * 0.15;
            const drift = k * 0.7;
            const fx = target.tx + Math.sin(t * 1.1 + i * 0.7) * drift + push[i].x;
            const fy = target.ty + Math.cos(t * 0.9 + i * 1.3) * drift + push[i].y;

            el.setAttribute("cx", (ox + (fx - ox) * k).toFixed(2));
            el.setAttribute("cy", (oy + (fy - oy) * k).toFixed(2));
            el.setAttribute("r", (2.2 + depth * 1.8 + (DOT_R - 2.2 - depth * 1.8) * k).toFixed(2));
            el.style.opacity = String(0.35 + depth * 0.65 + (1 - 0.35 - depth * 0.65) * k);
          });
          ghostLayer.style.opacity = String(p ** 3);
          brailleLayer.style.opacity = String(clamp01(1 - state.scroll * 2.5));
        };

        // the orb keeps turning; it slows as the word forms
        const tick = () => {
          state.angle += 0.012 + 0.03 * (1 - state.intro * (1 - state.scroll));
          render();
        };
        render(); // first frame now, so the server-rendered word doesn't flash before the orb
        gsap.ticker.add(tick);

        // only animate while the hero is on screen
        const visible = ScrollTrigger.create({
          trigger: root.current,
          start: "top bottom",
          end: "bottom top",
          onToggle: (self) => (self.isActive ? gsap.ticker.add(tick) : gsap.ticker.remove(tick)),
        });

        // scrolling out dissolves the word back into the orb; scrolling up re-forms it
        const setScroll = gsap.quickTo(state, "scroll", { duration: 0.5, ease: "power2.out" });
        const out = ScrollTrigger.create({
          trigger: root.current,
          start: "top top",
          end: "bottom top",
          onUpdate: (self) => setScroll(self.progress),
        });

        const onMove = (e: PointerEvent) => {
          const ctm = svg.getScreenCTM();
          if (!ctm) return;
          const pt = new DOMPoint(e.clientX, e.clientY).matrixTransform(ctm.inverse());
          pointer.x = pt.x;
          pointer.y = pt.y;
        };
        const onLeave = () => {
          pointer.x = pointer.y = -1e4;
        };
        svg.addEventListener("pointermove", onMove);
        svg.addEventListener("pointerleave", onLeave);

        const tl = gsap.timeline();
        tl.to(state, { intro: 1, duration: 1.7, ease: "power3.inOut", delay: 1.1 });
        tl.from("[data-braille]", { scale: 0, autoAlpha: 0, transformOrigin: "50% 50%", duration: 0.45, ease: "back.out(3)", stagger: 0.04 }, "-=0.2");
        tl.fromTo(
          "[data-pulse]",
          { scale: 0.6, autoAlpha: 0.7, transformOrigin: "50% 50%" },
          // immediateRender off: the rings stay hidden until the row lands
          { scale: 2.4, autoAlpha: 0, duration: 0.7, ease: "power2.out", stagger: 0.04, immediateRender: false },
          "<",
        );
        tl.from("[data-hero-copy]", { y: 18, autoAlpha: 0, duration: 0.6, stagger: 0.1, ease: "power2.out" }, 0.3);
        return () => {
          gsap.ticker.remove(tick);
          visible.kill();
          out.kill();
          svg.removeEventListener("pointermove", onMove);
          svg.removeEventListener("pointerleave", onLeave);
          // back to the finished word for reduced motion
          dots.forEach((el, i) => {
            el.setAttribute("cx", String(lit[i].tx));
            el.setAttribute("cy", String(lit[i].ty));
            el.setAttribute("r", String(DOT_R));
            el.style.opacity = "";
          });
          ghostLayer.style.opacity = "";
          brailleLayer.style.opacity = "";
        };
      });
      return () => mm.revert();
    },
    { scope: root, dependencies: [reduced], revertOnUpdate: true },
  );

  return (
    <section ref={root} id="top" aria-labelledby="hero-title" className="relative isolate overflow-hidden">
      <HeroFloaters />
      <div
        aria-hidden="true"
        className="ig-ring pointer-events-none absolute -right-48 -top-48 -z-10 size-[30rem] rounded-full opacity-15 blur-3xl"
      />

      <div className="mx-auto grid max-w-6xl items-center gap-10 px-4 pb-6 pt-12 lg:grid-cols-[1.25fr_1fr] lg:pt-20">
        <div>
          <h1 id="hero-title" className="sr-only">
            {site.name}
          </h1>
          <svg
            ref={svgRef}
            viewBox={`-8 -8 ${WIDTH + 16} ${HEIGHT + 16}`}
            className="w-full max-w-[44rem] touch-pan-y overflow-visible"
            aria-hidden="true"
          >
            <g data-ghost>
              {ghost.map((d, i) => (
                <circle key={i} cx={d.x} cy={d.y} r={1.3} fill="#d3d9e6" />
              ))}
            </g>
            {lit.map((d, i) => (
              <circle key={i} data-dot cx={d.tx} cy={d.ty} r={DOT_R} fill={LETTER_COLOURS[d.letter]} />
            ))}
            <g data-braille-row>
              {brailleDots.map((d, i) => (
                <g key={i}>
                  <circle data-pulse cx={d.x} cy={d.y} r={4.6} fill="none" stroke="#3b5998" strokeWidth={1.2} opacity={0} />
                  <circle data-braille cx={d.x} cy={d.y} r={4.6} fill={d.indicator ? "#8b9dc3" : "#1c1e21"} />
                </g>
              ))}
            </g>
          </svg>

          <p data-hero-copy className="mt-3 flex items-center gap-3 font-classic text-sm font-bold uppercase tracking-[0.2em] text-muted">
            <BrailleText word={WORD} capsWord className="text-ink" />
            <span>
              {t.hero.brailleCaption} <span className="normal-case tracking-normal">{t.hero.capitalsNote}</span>
            </span>
          </p>
          <p data-hero-copy data-headline className="mt-6 text-5xl font-extrabold leading-[1.05] tracking-tight text-ink sm:text-6xl">
            <CyclingHeadline lead={t.hero.headline.lead} words={t.hero.headline.words} sentence={t.hero.headline.sentence} />
          </p>
          <p data-hero-copy className="mt-5 max-w-xl text-2xl font-bold leading-snug text-fb-blue-dark">
            {t.hero.tagline}
          </p>
          <p data-hero-copy className="mt-4 max-w-xl text-lg leading-relaxed text-muted">
            {t.hero.intro}
          </p>
          <div data-hero-copy className="mt-8 flex flex-wrap gap-3">
            <a href="#how" className="btn btn-blue">
              {t.hero.seeHow}
            </a>
            <a href="#feed" className="btn btn-ghost">
              {t.hero.browse}
            </a>
          </div>
        </div>

        <div className="flex justify-center lg:justify-end">
          <AskCard />
        </div>
      </div>

      {/* Sam and his things, connected: Recall's version of the old Facebook map */}
      <div className="mx-auto max-w-6xl px-4 pb-16">
        <ConnectedHome />
      </div>
    </section>
  );
}
