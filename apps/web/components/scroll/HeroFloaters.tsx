"use client";

import { useRef } from "react";
import { PixelIcon } from "@/components/ui/PixelIcon";
import { gsap, MOTION_OK, useGSAP } from "@/lib/gsap";
import { useMotionPrefs } from "@/lib/motion-prefs";
import type { PixelIconName } from "@/lib/pixel-icons";

/**
 * Reactions and everyday things floating behind the hero. A horizontal mask keeps them clear in
 * the side margins of wide screens and faint behind the content column, so they never crowd the
 * text; on laptops and phones (no real margins) they are faint everywhere. Decorative.
 */

// left/top in % of the hero; size in px; badge = a white round reaction badge
const FLOATERS: { icon: PixelIconName; left: number; top: number; size: number; tilt: number; badge?: boolean }[] = [
  // left margin
  { icon: "love", left: 4, top: 6, size: 52, tilt: -8, badge: true },
  { icon: "key", left: 10, top: 13, size: 46, tilt: 12 },
  { icon: "like", left: 6, top: 25, size: 44, tilt: 6, badge: true },
  { icon: "glasses", left: 11, top: 34, size: 50, tilt: -10 },
  { icon: "heartHands", left: 3, top: 44, size: 58, tilt: 4, badge: true },
  { icon: "wallet", left: 11, top: 55, size: 44, tilt: -6 },
  { icon: "star", left: 5, top: 66, size: 36, tilt: 14 },
  { icon: "found", left: 10, top: 74, size: 48, tilt: -4, badge: true },
  { icon: "mug", left: 4, top: 86, size: 50, tilt: 8 },
  // right margin
  { icon: "heart", left: 92, top: 5, size: 44, tilt: 10, badge: true },
  { icon: "phone", left: 88, top: 14, size: 48, tilt: -12 },
  { icon: "cool", left: 95, top: 24, size: 50, tilt: 6, badge: true },
  { icon: "mug", left: 89, top: 33, size: 54, tilt: -5 },
  { icon: "like", left: 93, top: 45, size: 58, tilt: -8, badge: true },
  { icon: "remote", left: 88, top: 55, size: 46, tilt: 14 },
  { icon: "clock", left: 95, top: 64, size: 44, tilt: 4 },
  { icon: "key", left: 89, top: 75, size: 44, tilt: -14 },
  { icon: "star", left: 94, top: 86, size: 38, tilt: 8 },
  // a few behind the content, kept faint by the mask
  { icon: "heart", left: 30, top: 8, size: 38, tilt: -6 },
  { icon: "glasses", left: 47, top: 36, size: 42, tilt: 8 },
  { icon: "like", left: 66, top: 4, size: 40, tilt: 6 },
  { icon: "wallet", left: 38, top: 62, size: 40, tilt: -8 },
  { icon: "phone", left: 72, top: 52, size: 38, tilt: 10 },
  { icon: "love", left: 58, top: 80, size: 40, tilt: -4 },
];

// clear (but softened) beyond the 72rem content column (± a little), faint over it
const MASK =
  "linear-gradient(to right, rgb(0 0 0 / 0.35) calc(50% - 38rem), rgb(0 0 0 / 0.14) calc(50% - 34rem), rgb(0 0 0 / 0.14) calc(50% + 34rem), rgb(0 0 0 / 0.35) calc(50% + 38rem))";

export function HeroFloaters() {
  const root = useRef<HTMLDivElement>(null);
  const { reduced } = useMotionPrefs();

  useGSAP(
    () => {
      if (reduced) return;
      const mm = gsap.matchMedia();
      mm.add(MOTION_OK, () => {
        const items = gsap.utils.toArray<HTMLElement>("[data-floater] > span");
        gsap.from(items, { scale: 0, opacity: 0, duration: 0.6, ease: "back.out(2)", delay: 0.6, stagger: { each: 0.04, from: "random" } });

        // each drifts on its own slow loop, only while the hero is on screen
        const drift = gsap.timeline({
          paused: true,
          scrollTrigger: { trigger: root.current, start: "top bottom", end: "bottom top", toggleActions: "play pause resume pause" },
        });
        items.forEach((el, i) => {
          drift.to(
            el,
            { y: i % 2 ? -12 : 10, x: i % 3 ? 4 : -5, rotation: i % 2 ? 5 : -5, duration: 3 + (i % 5) * 0.7, ease: "sine.inOut", yoyo: true, repeat: -1 },
            (i % 7) * 0.3,
          );
        });

        // they lag behind as the hero scrolls away
        gsap.to(root.current, { y: 140, ease: "none", scrollTrigger: { trigger: root.current, start: "top top", end: "bottom top", scrub: true } });
      });
      return () => mm.revert();
    },
    { scope: root, dependencies: [reduced], revertOnUpdate: true },
  );

  return (
    <div
      ref={root}
      data-floaters
      aria-hidden="true"
      className="pointer-events-none absolute inset-0 -z-10"
      style={{ maskImage: MASK, WebkitMaskImage: MASK }}
    >
      {FLOATERS.map((f, i) => (
        <span
          key={i}
          data-floater={f.icon}
          className="absolute"
          style={{ left: `${f.left}%`, top: `${f.top}%`, transform: `translate(-50%, -50%) rotate(${f.tilt}deg)` }}
        >
          <span className={f.badge ? "flex rounded-full bg-white p-2 shadow-[0_6px_18px_rgb(28_30_33/0.14)]" : "block drop-shadow-[0_4px_6px_rgb(28_30_33/0.18)]"}>
            <PixelIcon name={f.icon} size={f.size} />
          </span>
        </span>
      ))}
    </div>
  );
}
