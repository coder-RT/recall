"use client";

import { useEffect, useState } from "react";
import { getDictionary } from "@/i18n";
import { useMotionPrefs } from "@/lib/motion-prefs";

const label = getDictionary().nav.backToTop;
const SHOW_AFTER = 600;

/** Back to the top of a long page. Focus goes with the view, so a keyboard or screen reader user isn't left behind. */
export function BackToTop() {
  const { reduced } = useMotionPrefs();
  const [show, setShow] = useState(false);

  useEffect(() => {
    const check = () => setShow(window.scrollY > SHOW_AFTER);
    check();
    window.addEventListener("scroll", check, { passive: true });
    return () => window.removeEventListener("scroll", check);
  }, []);

  if (!show) return null;
  const toTop = () => {
    const smooth = !reduced && window.matchMedia("(prefers-reduced-motion: no-preference)").matches;
    window.scrollTo({ top: 0, behavior: smooth ? "smooth" : "auto" });
    const heading = document.querySelector<HTMLElement>("h1");
    if (heading) {
      heading.tabIndex = -1;
      heading.focus({ preventScroll: true });
    }
  };
  return (
    <button type="button" onClick={toTop} className="btn btn-blue fixed bottom-6 right-6 z-40 min-h-11 gap-2 shadow-lg" data-back-to-top>
      <span aria-hidden>↑</span>
      {label}
    </button>
  );
}
