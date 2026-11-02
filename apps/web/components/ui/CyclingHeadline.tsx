"use client";

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useState } from "react";
import { useMotionPrefs } from "@/lib/motion-prefs";

/** The hero's headline: "Find your …", the last word changing every few seconds in its own colour (the wordmark's).
 *  Screen readers hear one steady sentence; with reduced motion the first word just stays. Motion owns this span;
 *  GSAP animates the paragraph around it, never this element. */
export function CyclingHeadline({ lead, words, sentence }: { lead: string; words: string[]; sentence: string }) {
  const { reduced } = useMotionPrefs();
  const [i, setI] = useState(0);
  useEffect(() => {
    if (reduced) return;
    const id = setInterval(() => setI((n) => (n + 1) % words.length), 2200);
    return () => clearInterval(id);
  }, [reduced, words.length]);
  const word = reduced ? words[0] : words[i];
  return (
    <>
      <span className="sr-only">{sentence}</span>
      <span aria-hidden="true" className="block">
        {lead}{" "}
        <span className="relative inline-grid align-baseline">
          {/* the longest word holds the width, so the line never jumps */}
          <span className="invisible col-start-1 row-start-1">{words.reduce((a, b) => (b.length > a.length ? b : a))}</span>
          <AnimatePresence mode="wait" initial={false}>
            <motion.span
              key={word}
              data-cycling-word
              className="hero-word col-start-1 row-start-1"
              style={{ color: COLOURS[words.indexOf(word) % COLOURS.length] }}
              initial={{ opacity: 0, y: "0.35em", filter: "blur(4px)" }}
              animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
              exit={{ opacity: 0, y: "-0.35em", filter: "blur(4px)" }}
              transition={{ duration: 0.35, ease: [0.22, 1, 0.36, 1] }}
            >
              {word}
            </motion.span>
          </AnimatePresence>
        </span>
      </span>
    </>
  );
}

// the wordmark's letter colours (BrailleHero), each 4.5:1 or better on white
const COLOURS = ["#3b5998", "#c2185b", "#7b2cbf", "#3f4fc4", "#a8431a"];
