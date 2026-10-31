"use client";

import { motion, useMotionValueEvent, useScroll } from "motion/react";
import { usePathname } from "next/navigation";
import { useState } from "react";
import { useT } from "@/i18n/I18nProvider";
import { useHashAfterPins } from "@/lib/gsap";
import { Logo } from "./Logo";
import { AccessibilityMenu } from "./AccessibilityMenu";

/** Classic blue bar; after the first scroll it shrinks and turns glassy. */
export function Nav() {
  const { scrollY } = useScroll();
  const [compact, setCompact] = useState(false);
  const t = useT();
  // the section links point into the landing page; from another page (Privacy) they lead back to it
  const home = usePathname() === "/" ? "" : "/";
  useHashAfterPins();
  useMotionValueEvent(scrollY, "change", (y) => setCompact(y > 40));

  return (
    <motion.header
      data-site-nav
      initial={false}
      animate={{
        height: compact ? "3.75rem" : "4.75rem",
        backgroundColor: compact ? "rgba(59, 89, 152, 0.86)" : "rgba(59, 89, 152, 1)",
        boxShadow: compact ? "0 8px 30px -12px rgba(29, 42, 91, 0.6)" : "0 0 0 rgba(0,0,0,0)",
      }}
      transition={{ duration: 0.25, ease: "easeOut" }}
      className="sticky top-0 z-50 text-white backdrop-blur-md"
    >
      <a
        href="#main"
        className="absolute left-4 top-2 -translate-y-24 rounded bg-white px-3 py-2 font-bold text-fb-blue-dark focus:translate-y-0"
      >
        {t.nav.skip}
      </a>
      <div className="mx-auto flex h-full max-w-6xl items-center justify-between gap-4 px-4">
        <a href={`${home}#top`} aria-label={t.nav.home} className="min-h-11 content-center">
          <Logo />
        </a>
        <nav aria-label={t.nav.sections} data-section-links className="hidden lg:block">
          <ul className="flex gap-1 font-classic text-sm font-bold">
            {t.nav.links.map((item) => (
              <li key={item.href}>
                <a href={`${home}${item.href}`} className="block rounded-md px-3 py-2 hover:bg-white/15">
                  {item.label}
                </a>
              </li>
            ))}
            <li>
              <a href="/privacy" className="block rounded-md px-3 py-2 hover:bg-white/15">
                {t.nav.privacy}
              </a>
            </li>
          </ul>
        </nav>
        <div className="flex items-center gap-2">
          <AccessibilityMenu />
          <a href={`${home}#ask`} className="btn btn-green hidden sm:inline-flex">
            {t.nav.tryDemo}
          </a>
        </div>
      </div>
    </motion.header>
  );
}
