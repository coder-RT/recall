"use client";

import { useEffect } from "react";
import { useA11yPrefs } from "@/lib/a11y-prefs";
import { speakLong, stopSpeaking, textOf } from "@/lib/speech";

const INTERACTIVE = "a, button, input, select, textarea, summary, [role='switch'], [role='radio'], [tabindex]";
const BLOCK = "p, h1, h2, h3, h4, h5, h6, li, blockquote, figcaption, label, td, th";

/**
 * Read aloud (accessibility menu), for sighted low-vision visitors: focusing a control reads its
 * label, clicking plain text reads that block, Escape stops. The block being read is outlined.
 * Screen-reader users already hear the page, so this stays off by default.
 */
export function ReadAloud() {
  const { prefs } = useA11yPrefs();

  useEffect(() => {
    if (!prefs.readAloud) return;
    let current: Element | null = null;
    const mark = (el: Element | null) => {
      current?.removeAttribute("data-reading");
      current = el;
      el?.setAttribute("data-reading", "");
    };
    const read = (el: Element) => {
      const text = textOf(el);
      if (!text) return;
      mark(el);
      speakLong(text.slice(0, 800)).then(() => {
        if (current === el) mark(null);
      });
    };

    const onFocus = (e: FocusEvent) => {
      if (e.target instanceof Element && e.target.matches(INTERACTIVE)) read(e.target);
    };
    const onClick = (e: MouseEvent) => {
      const target = e.target instanceof Element ? e.target : null;
      // controls are read on focus; plain text is read on click
      if (!target || target.closest(INTERACTIVE)) return;
      const block = target.closest(BLOCK);
      if (block) read(block);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        stopSpeaking();
        mark(null);
      }
    };

    document.addEventListener("focusin", onFocus);
    document.addEventListener("click", onClick);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("focusin", onFocus);
      document.removeEventListener("click", onClick);
      document.removeEventListener("keydown", onKey);
      stopSpeaking();
      mark(null);
    };
  }, [prefs.readAloud]);

  return null;
}
