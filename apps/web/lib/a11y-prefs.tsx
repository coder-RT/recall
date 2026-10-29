"use client";

import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import { ScrollTrigger } from "./gsap";

const STORAGE_KEY = "recall:a11y";

export const TEXT_SCALES = [1, 1.25, 1.5, 1.75, 2] as const;
export type TextScale = (typeof TEXT_SCALES)[number];

export interface A11yPrefs {
  /** Root font size multiplier; every rem-based size follows it. */
  textScale: TextScale;
  /** Hovered or focused text shown very large in a bar at the bottom. */
  magnifier: boolean;
  /** A round 2× magnifying glass that follows the pointer. */
  lens: boolean;
  /** Speak focused or clicked text. */
  readAloud: boolean;
  /** Black, white and yellow theme. */
  contrast: boolean;
}

const DEFAULTS: A11yPrefs = { textScale: 1, magnifier: false, lens: false, readAloud: false, contrast: false };

const A11yContext = createContext<{ prefs: A11yPrefs; set: (patch: Partial<A11yPrefs>) => void }>({
  prefs: DEFAULTS,
  set: () => {},
});

function readStored(): Partial<A11yPrefs> {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "{}");
  } catch {
    return {};
  }
}

/** The visitor's low-vision settings, saved in this browser and applied to <html>. */
export function A11yPrefsProvider({ children }: { children: ReactNode }) {
  const [prefs, setPrefs] = useState<A11yPrefs>(DEFAULTS);
  // the saved settings are already on <html> before first paint (lib/a11y-boot.ts);
  // only write to <html> once they've been read here too, never the defaults
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    // storage is only readable after mount
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setPrefs({ ...DEFAULTS, ...readStored() });
    setLoaded(true);
  }, []);

  useEffect(() => {
    if (!loaded) return;
    const html = document.documentElement;
    html.style.fontSize = prefs.textScale === 1 ? "" : `${prefs.textScale * 100}%`;
    html.dataset.textScale = String(prefs.textScale);
    html.dataset.contrast = prefs.contrast ? "high" : "normal";
    html.dataset.hydrated = "true"; // the page is interactive (also what browser tests wait for)
  }, [loaded, prefs.textScale, prefs.contrast]);

  // a new text size moves every section, so scroll-driven scenes re-measure
  useEffect(() => {
    const frame = requestAnimationFrame(() => ScrollTrigger.refresh());
    return () => cancelAnimationFrame(frame);
  }, [prefs.textScale]);

  const set = useCallback((patch: Partial<A11yPrefs>) => {
    setPrefs((prev) => {
      const next = { ...prev, ...patch };
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
      } catch {
        // Storage blocked (private mode): the choice still applies for this visit.
      }
      return next;
    });
  }, []);

  return <A11yContext.Provider value={{ prefs, set }}>{children}</A11yContext.Provider>;
}

export const useA11yPrefs = () => useContext(A11yContext);

