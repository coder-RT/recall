"use client";

import { AnimatePresence, motion } from "motion/react";
import { useState } from "react";
import { useT } from "@/i18n/I18nProvider";

export function Faq() {
  const [openIndex, setOpenIndex] = useState<number | null>(0);
  const faq = useT().faq.items;

  return (
    <ul className="card divide-y divide-fb-line">
      {faq.map((item, i) => {
        const open = openIndex === i;
        const panelId = `faq-panel-${i}`;
        return (
          <li key={item.q}>
            <h3>
              <button
                type="button"
                aria-expanded={open}
                aria-controls={panelId}
                onClick={() => setOpenIndex(open ? null : i)}
                className="flex min-h-14 w-full items-center justify-between gap-4 px-5 py-4 text-left text-lg font-bold text-ink"
              >
                {item.q}
                <motion.span aria-hidden="true" animate={{ rotate: open ? 45 : 0 }} className="text-2xl text-fb-blue">
                  +
                </motion.span>
              </button>
            </h3>
            <AnimatePresence initial={false}>
              {open && (
                <motion.div
                  id={panelId}
                  initial={{ height: 0, opacity: 0 }}
                  animate={{ height: "auto", opacity: 1 }}
                  exit={{ height: 0, opacity: 0 }}
                  transition={{ duration: 0.25, ease: "easeOut" }}
                  className="overflow-hidden"
                >
                  <p className="px-5 pb-5 text-[1.05rem] leading-relaxed text-muted">{item.a}</p>
                </motion.div>
              )}
            </AnimatePresence>
          </li>
        );
      })}
    </ul>
  );
}
