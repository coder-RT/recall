"use client";

import gsap from "gsap";
import { DrawSVGPlugin } from "gsap/DrawSVGPlugin";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { SplitText } from "gsap/SplitText";
import { useGSAP } from "@gsap/react";
import { useEffect } from "react";

// Register once; components import gsap and its plugins from here, never from the packages.
gsap.registerPlugin(ScrollTrigger, SplitText, DrawSVGPlugin, useGSAP);
// Mobile URL bars resize the viewport while scrolling; re-measuring then makes pins jump.
ScrollTrigger.config({ ignoreMobileResize: true });

export const ease = {
  editorial: "expo.out",
  soft: "power2.out",
  drop: "bounce.out",
} as const;

export const duration = {
  fast: 0.4,
  base: 0.8,
  slow: 1.4,
} as const;

/** Media query every GSAP effect runs under; the site toggle is checked separately. */
export const MOTION_OK = "(prefers-reduced-motion: no-preference)";

/**
 * Deep links (/#privacy): the browser jumps to the anchor before the pinned sections add their
 * scroll space, and later re-measures (ScrollTrigger refreshes) shift the page again. So the jump
 * is re-applied after every refresh until the visitor takes over (scroll, key, tap) or 5s pass.
 * Mount once.
 */
export function useHashAfterPins() {
  useEffect(() => {
    let target: Element | null = null;
    try {
      if (location.hash.length > 1) target = document.querySelector(decodeURIComponent(location.hash));
    } catch {}
    if (!target) return;
    const jump = () => target!.scrollIntoView({ behavior: "instant", block: "start" });
    const takeover = ["wheel", "touchstart", "keydown", "pointerdown"] as const;
    const stop = () => {
      ScrollTrigger.removeEventListener("refresh", jump);
      takeover.forEach((type) => window.removeEventListener(type, stop));
      window.clearTimeout(timer);
      cancelAnimationFrame(frame);
    };
    ScrollTrigger.addEventListener("refresh", jump);
    takeover.forEach((type) => window.addEventListener(type, stop, { passive: true }));
    const timer = window.setTimeout(stop, 5000);
    const frame = requestAnimationFrame(jump);
    return stop;
  }, []);
}

export { gsap, ScrollTrigger, SplitText, DrawSVGPlugin, useGSAP };
