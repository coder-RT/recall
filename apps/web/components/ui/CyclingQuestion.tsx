"use client";

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useRef, useState } from "react";
import { useMotionPrefs } from "@/lib/motion-prefs";

/** The end of the problem question ("put my keys?”"), changing every few seconds to other things Recall finds.
 *  Screen readers hear the first ending only, so the heading's name stays one steady question. It waits while off
 *  screen or in a hidden tab, and stays on the first ending with reduced motion. Motion owns this span; the GSAP mask
 *  animates the line around it, never this element. */
export function CyclingQuestion({ endings }: { endings: string[] }) {
  const { reduced } = useMotionPrefs();
  const [i, setI] = useState(0);
  const [visible, setVisible] = useState(false);
  const ref = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(([entry]) => setVisible(entry.isIntersecting));
    io.observe(el);
    return () => io.disconnect();
  }, []);

  useEffect(() => {
    if (reduced || !visible) return;
    const id = setInterval(() => {
      if (!document.hidden) setI((n) => (n + 1) % endings.length);
    }, 2600);
    return () => clearInterval(id);
  }, [reduced, visible, endings.length]);

  const ending = reduced ? endings[0] : endings[i];
  return (
    <>
      <span className="sr-only">{endings[0]}</span>
      <span ref={ref} aria-hidden="true" className="relative grid max-w-full [overflow-wrap:anywhere]">
        {/* the longest ending holds the width, so the heading never jumps */}
        <span className="invisible col-start-1 row-start-1">{endings.reduce((a, b) => (b.length > a.length ? b : a))}</span>
        <AnimatePresence mode="wait" initial={false}>
          <motion.span
            key={ending}
            data-cycling-ending
            className="col-start-1 row-start-1"
            initial={{ opacity: 0, y: "0.35em", filter: "blur(4px)" }}
            animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
            exit={{ opacity: 0, y: "-0.35em", filter: "blur(4px)" }}
            transition={{ duration: 0.35, ease: [0.22, 1, 0.36, 1] }}
          >
            {ending}
          </motion.span>
        </AnimatePresence>
      </span>
    </>
  );
}
