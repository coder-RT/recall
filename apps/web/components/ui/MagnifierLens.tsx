"use client";

import { useEffect, useRef } from "react";
import { useA11yPrefs } from "@/lib/a11y-prefs";

const SIZE = 220; // px
const ZOOM = 2;
const REFRESH_MS = 400;

/**
 * Magnifying glass (accessibility menu): a round 2× lens that follows the mouse or pen.
 * It shows an inert copy of <main>, refreshed at most every 0.4s and after scrolling, so a running
 * animation can lag slightly inside it. Hides on keyboard use and after 3s without movement.
 */
export function MagnifierLens() {
  const { prefs } = useA11yPrefs();
  const lens = useRef<HTMLDivElement>(null);
  const stage = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const main = document.getElementById("main");
    const lensEl = lens.current;
    const stageEl = stage.current;
    if (!prefs.lens || !main || !lensEl || !stageEl) return;

    let point: { x: number; y: number } | null = null;
    let lastSnapshot = 0;
    let idle = 0;
    let settle = 0;

    const snapshot = () => {
      const copy = main.cloneNode(true) as HTMLElement;
      // no duplicate ids outside SVG (SVG masks look theirs up by id and still need them)
      copy.removeAttribute("id");
      copy.querySelectorAll("[id]").forEach((el) => {
        if (!el.closest("svg")) el.removeAttribute("id");
      });
      stageEl.replaceChildren(copy);
      stageEl.style.width = `${main.offsetWidth}px`;
      lastSnapshot = performance.now();
    };

    const place = () => {
      if (!point) return;
      const box = main.getBoundingClientRect();
      lensEl.style.transform = `translate(${point.x - SIZE / 2}px, ${point.y - SIZE / 2}px)`;
      // put the page point under the cursor in the middle of the lens
      stageEl.style.transform = `translate(${SIZE / 2 - (point.x - box.left) * ZOOM}px, ${SIZE / 2 - (point.y - box.top) * ZOOM}px) scale(${ZOOM})`;
    };

    const hide = () => (lensEl.style.opacity = "0");

    const onMove = (e: PointerEvent) => {
      if (e.pointerType === "touch") return;
      point = { x: e.clientX, y: e.clientY };
      if (performance.now() - lastSnapshot > REFRESH_MS) snapshot();
      place();
      lensEl.style.opacity = "1";
      window.clearTimeout(idle);
      idle = window.setTimeout(hide, 3000);
    };
    const onScroll = () => {
      place();
      window.clearTimeout(settle);
      settle = window.setTimeout(() => {
        snapshot();
        place();
      }, 150);
    };

    snapshot();
    window.addEventListener("pointermove", onMove, { passive: true });
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("keydown", hide);
    return () => {
      window.clearTimeout(idle);
      window.clearTimeout(settle);
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("keydown", hide);
      stageEl.replaceChildren();
      hide();
    };
  }, [prefs.lens]);

  if (!prefs.lens) return null;
  return (
    <div
      ref={lens}
      data-lens
      aria-hidden="true"
      style={{ width: SIZE, height: SIZE, opacity: 0 }}
      className="pointer-events-none fixed left-0 top-0 z-[70] overflow-hidden rounded-full border-4 border-[#ffd400] bg-[#f0f2f5] shadow-2xl transition-opacity duration-150"
    >
      <div ref={stage} inert className="absolute left-0 top-0 origin-top-left" />
    </div>
  );
}
