"use client";

import { format } from "@/i18n";
import { useT } from "@/i18n/I18nProvider";
import { brailleCells, dotPosition } from "@/lib/braille";

/**
 * A word drawn as Braille cells in SVG, so every browser shows the same dots (Unicode Braille
 * renders unevenly in fallback fonts). Unlit positions are shown faintly to make the cells readable.
 */
export function BrailleText({ word, capsWord = false, className = "" }: { word: string; capsWord?: boolean; className?: string }) {
  const cells = brailleCells(word, { capsWord });
  const t = useT();
  const pitch = 7; // svg units between cells
  return (
    <svg
      viewBox={`0 0 ${cells.length * pitch - 2} 11`}
      className={`inline-block h-[1.1em] w-auto align-[-0.15em] ${className}`}
      role="img"
      aria-label={format(t.braille.label, { word }) + (capsWord ? t.braille.capsSign : "")}
    >
      {cells.map((cell, i) =>
        [1, 2, 3, 4, 5, 6].map((d) => {
          const { col, row } = dotPosition(d);
          const on = cell.dots.includes(d);
          return (
            <circle
              key={`${i}-${d}`}
              cx={i * pitch + 1.5 + col * 3}
              cy={1.5 + row * 4}
              r={on ? 1.4 : 0.6}
              fill="currentColor"
              opacity={on ? (cell.indicator ? 0.55 : 1) : 0.2}
            />
          );
        }),
      )}
    </svg>
  );
}
