"use client";

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useState } from "react";
import { useA11yPrefs } from "@/lib/a11y-prefs";
import { textOf } from "@/lib/speech";

const TEXT = "p, h1, h2, h3, h4, h5, h6, li, a, button, label, legend, figcaption, blockquote, summary, td, th, [data-caption]";

/**
 * Magnifier (accessibility menu): whatever text is under the pointer or has keyboard focus is
 * shown very large, yellow on black, in a bar at the bottom of the screen. Hidden from screen
 * readers, which already have the text.
 */
export function TextMagnifier() {
  const { prefs } = useA11yPrefs();
  const [text, setText] = useState("");

  useEffect(() => {
    if (!prefs.magnifier) return;
    let frame = 0;
    const pick = (target: EventTarget | null) => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const el = target instanceof Element ? target.closest(TEXT) : null;
        setText(el ? textOf(el).slice(0, 280) : "");
      });
    };
    const onPointer = (e: PointerEvent) => pick(e.target);
    const onFocus = (e: FocusEvent) => pick(e.target);
    document.addEventListener("pointerover", onPointer);
    document.addEventListener("focusin", onFocus);
    return () => {
      cancelAnimationFrame(frame);
      document.removeEventListener("pointerover", onPointer);
      document.removeEventListener("focusin", onFocus);
      setText("");
    };
  }, [prefs.magnifier]);

  return (
    <AnimatePresence>
      {prefs.magnifier && text && (
        <motion.div
          data-magnifier
          aria-hidden="true"
          initial={{ opacity: 0, y: 24 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: 24 }}
          transition={{ duration: 0.18 }}
          // fixed pixel sizes and literal colours: unaffected by text size and high contrast
          className="pointer-events-none fixed inset-x-4 bottom-4 z-[60] mx-auto max-w-5xl rounded-2xl border-4 border-[#ffd400] bg-[#000] px-6 py-4 text-[clamp(24px,4.5vw,46px)] font-bold leading-tight text-[#ffd400] shadow-2xl"
        >
          {text}
        </motion.div>
      )}
    </AnimatePresence>
  );
}
