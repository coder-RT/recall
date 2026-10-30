"use client";

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useId, useRef, useState } from "react";
import { useT } from "@/i18n/I18nProvider";
import { TEXT_SCALES, useA11yPrefs, type A11yPrefs } from "@/lib/a11y-prefs";
import { useMotionPrefs } from "@/lib/motion-prefs";
import { canSpeak, speakLong, stopSpeaking, textOf } from "@/lib/speech";

function Switch({ label, hint, checked, onChange }: { label: string; hint: string; checked: boolean; onChange: (v: boolean) => void }) {
  const hintId = useId();
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-describedby={hintId}
      onClick={() => onChange(!checked)}
      className="flex min-h-11 w-full items-start gap-3 rounded-lg px-2 py-2 text-left hover:bg-fb-grey"
    >
      <span className={`mt-0.5 flex h-6 w-10 shrink-0 items-center rounded-full p-0.5 ${checked ? "bg-fb-blue" : "bg-fb-line"}`}>
        <motion.span
          layout
          transition={{ type: "spring", stiffness: 500, damping: 32 }}
          className={`size-5 rounded-full bg-white shadow ${checked ? "ml-auto" : ""}`}
        />
      </span>
      <span>
        <span className="block font-bold text-ink">{label}</span>
        <span id={hintId} className="block text-sm text-muted">
          {hint}
        </span>
      </span>
    </button>
  );
}

/** The section in the middle of the screen, read heading first. */
function readCurrentSection() {
  const el = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
  const section = el?.closest("section, footer");
  if (section) speakLong(textOf(section).slice(0, 2000));
}

/**
 * Accessibility menu in the nav (Alt+A): text size, magnifier, magnifying glass, read aloud,
 * high contrast and reduce motion, saved in this browser. A non-modal popover: Escape closes it
 * and returns focus to the button.
 */
export function AccessibilityMenu() {
  const [open, setOpen] = useState(false);
  const t = useT().a11y;
  const { prefs, set } = useA11yPrefs();
  const { reduced, setReduced } = useMotionPrefs();
  const button = useRef<HTMLButtonElement>(null);
  const panel = useRef<HTMLDivElement>(null);
  const titleId = useId();

  // Alt+A from anywhere (by key position, since Option+A types "å" on a Mac)
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.altKey && e.code === "KeyA") {
        e.preventDefault();
        setOpen((v) => !v);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  // focus the first control on open; close on Escape or a click outside
  useEffect(() => {
    if (!open) return;
    panel.current?.querySelector<HTMLElement>("input, button")?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setOpen(false);
        button.current?.focus();
      }
    };
    const onDown = (e: PointerEvent) => {
      if (!panel.current?.contains(e.target as Node) && !button.current?.contains(e.target as Node)) setOpen(false);
    };
    window.addEventListener("keydown", onKey);
    window.addEventListener("pointerdown", onDown);
    return () => {
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("pointerdown", onDown);
    };
  }, [open]);

  const toggle = (key: keyof Omit<A11yPrefs, "textScale">) => (v: boolean) => set({ [key]: v });

  return (
    <div className="relative">
      <button
        ref={button}
        type="button"
        aria-expanded={open}
        aria-controls={open ? `${titleId}-panel` : undefined}
        aria-keyshortcuts="Alt+A"
        onClick={() => setOpen((v) => !v)}
        className="inline-flex min-h-11 items-center gap-2 rounded-full px-3 text-sm font-bold hover:bg-white/15"
      >
        {/* universal access figure */}
        <svg viewBox="0 0 24 24" className="size-6" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
          <circle cx="12" cy="12" r="10" />
          <circle cx="12" cy="7" r="1.4" fill="currentColor" stroke="none" />
          <path d="M7 10.2l5 1 5-1M12 11.2v3.3l-2.6 4.2M12 14.5l2.6 4.2" />
        </svg>
        <span className="hidden sm:inline">{t.button}</span>
        <span className="sr-only sm:hidden">{t.button}</span>
      </button>

      <AnimatePresence>
        {open && (
          <motion.div
            ref={panel}
            id={`${titleId}-panel`}
            role="dialog"
            aria-labelledby={titleId}
            initial={{ opacity: 0, y: -8, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -8, scale: 0.97 }}
            transition={{ type: "spring", stiffness: 420, damping: 32 }}
            className="card absolute right-0 top-full z-[80] mt-2 max-h-[calc(100dvh-6rem)] w-[min(23rem,calc(100vw-2rem))] origin-top-right overflow-y-auto p-4 text-ink"
          >
            <h2 id={titleId} className="text-xl font-extrabold">
              {t.title}
            </h2>
            <p className="text-sm text-muted">{t.saved}</p>

            <fieldset className="mt-4">
              <legend className="mb-2 font-bold">{t.textSize}</legend>
              <div className="grid grid-cols-5 gap-1">
                {TEXT_SCALES.map((scale) => (
                  <label key={scale} className="relative">
                    <input
                      type="radio"
                      name="text-size"
                      checked={prefs.textScale === scale}
                      onChange={() => set({ textScale: scale })}
                      className="peer sr-only"
                    />
                    <span className="grid min-h-11 cursor-pointer place-items-center rounded-lg border border-fb-line text-sm font-bold peer-checked:border-fb-blue peer-checked:bg-fb-blue peer-checked:text-white peer-focus-visible:outline peer-focus-visible:outline-3 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-fb-blue">
                      {scale * 100}%
                    </span>
                  </label>
                ))}
              </div>
            </fieldset>

            <div className="mt-3 grid gap-1">
              <Switch label={t.magnifier.label} hint={t.magnifier.hint} checked={prefs.magnifier} onChange={toggle("magnifier")} />
              <Switch label={t.lens.label} hint={t.lens.hint} checked={prefs.lens} onChange={toggle("lens")} />
              <Switch
                label={t.readAloud.label}
                hint={canSpeak() ? t.readAloud.hint : t.readAloud.unavailable}
                checked={prefs.readAloud}
                onChange={toggle("readAloud")}
              />
              <Switch label={t.contrast.label} hint={t.contrast.hint} checked={prefs.contrast} onChange={toggle("contrast")} />
              <Switch label={t.motion.label} hint={t.motion.hint} checked={reduced} onChange={setReduced} />
            </div>

            <div className="mt-3 flex flex-wrap gap-2 border-t border-fb-line pt-3">
              <button type="button" onClick={readCurrentSection} className="btn btn-blue">
                {t.readSection}
              </button>
              <button type="button" onClick={stopSpeaking} className="btn btn-ghost">
                {t.stop}
              </button>
            </div>
            <p className="mt-3 text-sm text-muted">{t.voiceTip}</p>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
