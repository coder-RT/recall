"use client";

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useState } from "react";
import { useT } from "@/i18n/I18nProvider";

const STORAGE_KEY = "recall:notice-seen";
const DELAY_MS = 1500; // after the hero intro, so the two don't compete

/**
 * An honest storage notice. The site sets no cookies and has no analytics; it only keeps two small
 * settings in this browser (reduce motion, and that this note was seen). Not a modal: it never takes
 * focus, and Escape dismisses it while focus is inside.
 */
export function CookieNotice() {
  const [open, setOpen] = useState(false);
  const t = useT().cookie;

  useEffect(() => {
    let seen = false;
    try {
      seen = localStorage.getItem(STORAGE_KEY) === "1";
    } catch {}
    if (seen) return;
    const timer = window.setTimeout(() => setOpen(true), DELAY_MS);
    return () => window.clearTimeout(timer);
  }, []);

  const dismiss = () => {
    setOpen(false);
    try {
      localStorage.setItem(STORAGE_KEY, "1");
    } catch {}
  };

  return (
    <AnimatePresence>
      {open && (
        <motion.section
          role="region"
          aria-label={t.region}
          initial={{ opacity: 0, y: 40, scale: 0.96 }}
          animate={{ opacity: 1, y: 0, scale: 1, transition: { type: "spring", stiffness: 320, damping: 26 } }}
          exit={{ opacity: 0, y: 24, transition: { duration: 0.2 } }}
          onKeyDown={(e) => e.key === "Escape" && dismiss()}
          className="card fixed inset-x-4 bottom-4 z-50 overflow-hidden sm:left-auto sm:right-6 sm:bottom-6 sm:w-[24rem]"
        >
          <p className="bg-fb-blue px-4 py-2 font-classic text-sm font-bold text-white">{t.bar}</p>
          <div className="p-4">
            <p className="flex items-start gap-3 text-ink">
              <motion.span
                aria-hidden="true"
                className="text-3xl leading-none"
                initial={{ rotate: 0 }}
                animate={{ rotate: [0, -14, 10, -6, 0], transition: { delay: 0.35, duration: 0.7 } }}
              >
                🍪
              </motion.span>
              <span>
                <strong className="block text-lg">{t.title}</strong>
                {t.body}
              </span>
            </p>
            <div className="mt-4 flex justify-end gap-3">
              <a href="#privacy" className="btn btn-ghost">
                {t.privacy}
              </a>
              <button type="button" onClick={dismiss} className="btn btn-blue">
                {t.gotIt}
              </button>
            </div>
          </div>
        </motion.section>
      )}
    </AnimatePresence>
  );
}
