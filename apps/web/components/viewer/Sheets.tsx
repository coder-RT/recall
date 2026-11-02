"use client";

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useRef, useState } from "react";
import { format } from "@/i18n";
import { useMotionPrefs } from "@/lib/motion-prefs";

export interface Sheet {
  id: string;
  title: string;
  file: string;
  summary: string;
}

interface Strings {
  download: string;
  zoom: string;
  close: string;
}

/**
 * The drawing sheets as cards; choosing one enlarges it in place (Motion's shared layout), on this page, never a new
 * tab. Esc, the backdrop or Close shrink it back and focus returns to the card. With reduced motion it simply swaps.
 */
export function Sheets({ sheets, src, t }: { sheets: Sheet[]; src: string; t: Strings }) {
  const [open, setOpen] = useState<string | null>(null);
  const { reduced } = useMotionPrefs();
  const opener = useRef<HTMLButtonElement | null>(null);
  const close = useRef<HTMLButtonElement>(null);
  const sheet = sheets.find((s) => s.id === open) ?? null;
  const transition = reduced ? { duration: 0 } : { type: "spring" as const, stiffness: 260, damping: 30 };

  useEffect(() => {
    if (!sheet) return;
    close.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(null);
      if (e.key === "Tab") {
        e.preventDefault(); // one control in the dialog: focus stays on Close
        close.current?.focus();
      }
    };
    document.addEventListener("keydown", onKey);
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = overflow;
      opener.current?.focus();
    };
  }, [sheet]);

  return (
    <>
      <ul className="mt-4 grid gap-6 lg:grid-cols-2">
        {sheets.map((d) => (
          <li key={d.id} data-sheet={d.id}>
            <figure className="overflow-hidden rounded-xl border border-fb-line bg-white">
              <button
                type="button"
                aria-label={format(t.zoom, { id: d.id })}
                aria-haspopup="dialog"
                onClick={(e) => {
                  opener.current = e.currentTarget;
                  setOpen(d.id);
                }}
                className="block w-full cursor-zoom-in"
              >
                <motion.img layoutId={`sheet-${d.id}`} transition={transition} src={`${src}/${d.file}`} alt={d.summary} width={1587} height={1123} className="h-auto w-full" />
              </button>
              <figcaption className="flex items-center justify-between gap-3 border-t border-fb-line px-4 py-3 text-sm">
                <span className="font-semibold text-ink">
                  {d.id} · {d.title}
                </span>
                <a href={`${src}/${d.file}`} download className="font-semibold text-fb-blue-dark underline">
                  {format(t.download, { id: d.id })}
                </a>
              </figcaption>
            </figure>
          </li>
        ))}
      </ul>
      <AnimatePresence>
        {sheet && (
          <motion.div
            key="backdrop"
            role="dialog"
            aria-modal="true"
            aria-label={`${sheet.id} · ${sheet.title}`}
            data-sheet-dialog
            className="fixed inset-0 z-50 flex items-center justify-center bg-ink/70 p-4"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={reduced ? { duration: 0 } : { duration: 0.2 }}
            onClick={() => setOpen(null)}
          >
            <div className="relative w-full max-w-6xl" onClick={(e) => e.stopPropagation()}>
              <motion.img layoutId={`sheet-${sheet.id}`} transition={transition} src={`${src}/${sheet.file}`} alt={sheet.summary} width={1587} height={1123} className="h-auto max-h-[85vh] w-full rounded-lg bg-white object-contain" />
              <button ref={close} type="button" onClick={() => setOpen(null)} className="btn btn-blue absolute right-3 top-3">
                {t.close}
              </button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}
