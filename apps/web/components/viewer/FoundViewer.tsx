"use client";

import { AnimatePresence, motion } from "motion/react";
import { useState } from "react";
import { format } from "@/i18n";
import { BANDS, bandOf } from "./bands";
import type { FurnitureBox, RoomShape, Surface, Thing } from "./Layers";
import { RoomViewer } from "./RoomViewer";
import type { ViewerStrings } from "./ViewerCanvas";

export interface FoundStrings {
  title: string;
  body: string;
  row: string;
  sure: string;
  furniture: string;
  /** the group's name when the export has no room name */
  thisRoom: string;
  bandNames: Record<(typeof BANDS)[number], string>;
}

interface Props {
  src: string;
  bounds: { min: number[]; max: number[] };
  surfaces: Surface[];
  room: RoomShape;
  furniture: FurnitureBox[];
  things: Thing[];
  hasMesh?: boolean;
  hasPhoto?: boolean;
  hasArchitect?: boolean;
  viewer: ViewerStrings;
  found: FoundStrings;
  caption: React.ReactNode;
}

/** The 3D room and, beside it in plain HTML, the list of what Recall found; choosing one highlights its pin. */
export function FoundViewer({ src, bounds, surfaces, room, furniture, things, hasMesh, hasPhoto, hasArchitect, viewer, found, caption }: Props) {
  const [selected, setSelected] = useState<number | null>(null);
  const [closed, setClosed] = useState<Set<string>>(new Set());
  const kinds = [...new Set(furniture.map((f) => f.label))];
  const groups = [...things.reduce((m, t, i) => {
    const name = t.room ?? room.name ?? found.thisRoom;
    m.set(name, [...(m.get(name) ?? []), { t, i }]);
    return m;
  }, new Map<string, { t: Thing; i: number }[]>())];
  return (
    <div className="mt-8 grid gap-6 lg:grid-cols-[minmax(0,1fr)_17rem]">
      <figure className="self-start overflow-hidden rounded-xl border border-fb-line bg-white">
        {/* the canvas keeps its own shape; the controls below it take the height they need */}
        <div>
          <RoomViewer src={src} bounds={bounds} surfaces={surfaces} room={room} furniture={furniture} things={things} selected={selected} hasMesh={hasMesh} hasPhoto={hasPhoto} hasArchitect={hasArchitect} t={viewer} />
        </div>
        <figcaption className="border-t border-fb-line px-4 py-3 text-sm text-muted">{caption}</figcaption>
      </figure>

      <section aria-labelledby="found-title">
        <h2 id="found-title" className="text-sm font-semibold text-muted">
          {found.title} · {things.length}
        </h2>
        <p className="mt-1 text-sm text-muted">{found.body}</p>
        {/* grouped by room, like the app's Found tab: each room folds open and closed */}
        {groups.map(([name, items]) => {
          const open = !closed.has(name);
          const panel = `found-room-${name.replace(/\W+/g, "-")}`;
          return (
            <div key={name} data-room-group={name} className="mt-3">
              <button
                type="button"
                aria-expanded={open}
                aria-controls={panel}
                onClick={() => setClosed((c) => { const n = new Set(c); if (n.has(name)) n.delete(name); else n.add(name); return n; })}
                className="flex min-h-11 w-full items-center justify-between gap-3 rounded-lg bg-fb-grey px-3 text-left text-sm font-semibold text-ink"
              >
                <span>
                  {name} · {items.length}
                </span>
                <span aria-hidden className={`transition-transform motion-reduce:transition-none ${open ? "rotate-90" : ""}`}>
                  ▸
                </span>
              </button>
              <AnimatePresence initial={false}>
                {open && (
                  <motion.ul
                    id={panel}
                    key="list"
                    initial={{ height: 0, opacity: 0 }}
                    animate={{ height: "auto", opacity: 1 }}
                    exit={{ height: 0, opacity: 0 }}
                    transition={{ duration: 0.25 }}
                    className="mt-1 divide-y divide-fb-line overflow-hidden border-y border-fb-line text-sm"
                  >
                    {items.map(({ t, i }) => (
                      <li key={i}>
                        <button
                          type="button"
                          aria-pressed={selected === i}
                          onClick={() => setSelected(selected === i ? null : i)}
                          className="flex w-full items-baseline justify-between gap-3 py-2 text-left text-ink hover:bg-fb-grey aria-pressed:bg-fb-blue-pale aria-pressed:font-semibold"
                        >
                          <span>
                            {format(found.row, {
                              thing: [t.color, t.label].filter(Boolean).join(" "),
                              band: found.bandNames[bandOf(t.at[2])].toLowerCase(),
                              z: t.at[2].toFixed(2),
                            })}
                          </span>
                          <span className="shrink-0 tabular-nums text-muted">{format(found.sure, { pct: Math.round(t.confidence * 100) })}</span>
                        </button>
                      </li>
                    ))}
                  </motion.ul>
                )}
              </AnimatePresence>
            </div>
          );
        })}
        <p className="mt-3 text-sm text-muted">{format(found.furniture, { n: furniture.length, kinds: kinds.join(", ") })}</p>
      </section>
    </div>
  );
}
