"use client";

import { useRef, type RefObject } from "react";
import { gsap, MOTION_OK, ScrollTrigger, SplitText, useGSAP } from "./gsap";
import { useMotionPrefs } from "./motion-prefs";

/**
 * Section entrance presets, read from the section's markup:
 *   [data-eyebrow]                 the small label above a heading
 *   [data-heading="mask"|"words"]  heading; "mask" raises each [data-line] out of its clip,
 *                                  "words" raises each word out of its own clip
 *   [data-reveal]                  copy, list items, buttons: fade up, staggered
 *   [data-card]                    cards: tilt in from the right and settle flat
 * Everything uses from(), so the server HTML is the finished state.
 */
export function buildReveal(root: HTMLElement) {
  const tl = gsap.timeline({ paused: true });

  const eyebrow = root.querySelectorAll("[data-eyebrow]");
  if (eyebrow.length) tl.from(eyebrow, { y: 10, autoAlpha: 0, duration: 0.5, ease: "power2.out" }, 0);

  const heading = root.querySelector<HTMLElement>("[data-heading]");
  if (heading?.dataset.heading === "words") {
    const words = SplitText.create(heading, { type: "words", mask: "words", aria: "auto" }).words;
    tl.from(words, { yPercent: 110, duration: 0.8, stagger: 0.05, ease: "expo.out" }, 0.1);
  } else if (heading) {
    tl.from(heading.querySelectorAll("[data-line]"), { yPercent: 105, duration: 0.9, stagger: 0.12, ease: "expo.out" }, 0.1);
  }

  const body = root.querySelectorAll("[data-reveal]");
  if (body.length) {
    tl.from(body, { y: 18, autoAlpha: 0, duration: 0.6, stagger: Math.min(0.08, 0.5 / body.length), ease: "power2.out" }, 0.35);
  }

  root.querySelectorAll<HTMLElement>("[data-card]").forEach((card, i) => {
    tl.from(
      card,
      { x: 80, y: 40, rotationY: -14, rotationX: 6, scale: 0.92, autoAlpha: 0, transformPerspective: 1100, duration: 0.9, ease: "power3.out" },
      0.3 + i * 0.12,
    );
  });

  return tl;
}

/** Plays a section's reveal once, when it scrolls into view. Off under reduced motion. */
export function useSectionReveal<T extends HTMLElement>(): RefObject<T | null> {
  const ref = useRef<T>(null);
  const { reduced } = useMotionPrefs();

  useGSAP(
    () => {
      if (reduced || !ref.current) return;
      const root = ref.current;
      const mm = gsap.matchMedia();
      mm.add(MOTION_OK, () => {
        const tl = buildReveal(root);
        ScrollTrigger.create({ trigger: root, start: "top 78%", once: true, onEnter: () => tl.play() });
      });
      return () => mm.revert();
    },
    { scope: ref, dependencies: [reduced], revertOnUpdate: true },
  );

  return ref;
}
