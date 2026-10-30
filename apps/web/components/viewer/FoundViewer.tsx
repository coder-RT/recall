"use client";

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
  bandNames: Record<(typeof BANDS)[number], string>;
}

interface Props {
  src: string;
  bounds: { min: number[]; max: number[] };
  surfaces: Surface[];
  room: RoomShape;
  furniture: FurnitureBox[];
  things: Thing[];
  viewer: ViewerStrings;
  found: FoundStrings;
  caption: React.ReactNode;
}

/** The 3D room and, beside it in plain HTML, the list of what Recall found; choosing one highlights its pin. */
export function FoundViewer({ src, bounds, surfaces, room, furniture, things, viewer, found, caption }: Props) {
  const [selected, setSelected] = useState<number | null>(null);
  const kinds = [...new Set(furniture.map((f) => f.label))];
  return (
    <div className="mt-8 grid gap-6 lg:grid-cols-[minmax(0,1fr)_17rem]">
      <figure className="self-start overflow-hidden rounded-xl border border-fb-line bg-white">
        <div className="aspect-[4/5] sm:aspect-square">
          <RoomViewer src={src} bounds={bounds} surfaces={surfaces} room={room} furniture={furniture} things={things} selected={selected} t={viewer} />
        </div>
        <figcaption className="border-t border-fb-line px-4 py-3 text-sm text-muted">{caption}</figcaption>
      </figure>

      <section aria-labelledby="found-title">
        <h2 id="found-title" className="text-sm font-semibold text-muted">
          {found.title} · {things.length}
        </h2>
        <p className="mt-1 text-sm text-muted">{found.body}</p>
        <ul className="mt-3 divide-y divide-fb-line border-y border-fb-line text-sm">
          {things.map((t, i) => (
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
        </ul>
        <p className="mt-3 text-sm text-muted">{format(found.furniture, { n: furniture.length, kinds: kinds.join(", ") })}</p>
      </section>
    </div>
  );
}
