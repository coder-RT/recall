"use client";

import { MotionConfig } from "motion/react";
import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";

const STORAGE_KEY = "recall:reduce-motion";

interface MotionPrefs {
  /** True when the OS asks for reduced motion or the visitor switched it off on the site. */
  reduced: boolean;
  setReduced: (value: boolean) => void;
}

const MotionPrefsContext = createContext<MotionPrefs>({ reduced: false, setReduced: () => {} });

function readStored(): boolean | null {
  try {
    const value = localStorage.getItem(STORAGE_KEY);
    return value === null ? null : value === "1";
  } catch {
    return null;
  }
}

/** One source of truth for reduced motion: Motion reads it via MotionConfig, GSAP via useMotionPrefs. */
export function MotionPrefsProvider({ children }: { children: ReactNode }) {
  const [reduced, setReducedState] = useState(false);
  // write to <html> only once the real setting is known (the head script set it before paint)
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    const stored = readStored();
    // External source (OS setting + storage) is only readable after mount.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setReducedState(stored ?? query.matches);
    setReady(true);
    const onChange = (e: MediaQueryListEvent) => {
      if (readStored() === null) setReducedState(e.matches);
    };
    query.addEventListener("change", onChange);
    return () => query.removeEventListener("change", onChange);
  }, []);

  useEffect(() => {
    if (ready) document.documentElement.dataset.reduceMotion = String(reduced);
  }, [ready, reduced]);

  const setReduced = useCallback((value: boolean) => {
    setReducedState(value);
    try {
      localStorage.setItem(STORAGE_KEY, value ? "1" : "0");
    } catch {
      // Storage blocked (private mode): the choice still applies for this visit.
    }
  }, []);

  return (
    <MotionPrefsContext.Provider value={{ reduced, setReduced }}>
      <MotionConfig reducedMotion={reduced ? "always" : "user"}>{children}</MotionConfig>
    </MotionPrefsContext.Provider>
  );
}

export const useMotionPrefs = () => useContext(MotionPrefsContext);
