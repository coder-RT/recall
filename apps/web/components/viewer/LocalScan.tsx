"use client";

import { useParams } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";
import { format, getDictionary } from "@/i18n";
import { BAND_EDGES, BANDS, bandOf } from "./bands";
import { FoundViewer } from "./FoundViewer";
import type { FurnitureBox, RoomShape, Surface, Thing } from "./Layers";
import { ViewerStats } from "./ViewerStats";

const s = getDictionary().app.viewer.scan;
/** Where `make viewer` writes a home's export; gitignored, so it only ever exists on the computer that scanned. */
const folder = (homeId: string) => `/local-scan/${encodeURIComponent(homeId)}`;

export interface ScanMeta {
  count: number;
  bounds: { min: number[]; max: number[] };
  surfaces: Surface[];
  room: RoomShape;
  furniture: FurnitureBox[];
  objects: Thing[];
  stats: { frames: number; total_s: number; sam_calls: number; captured: string };
}

function bandRange(i: number) {
  if (i === 0) return format(s.bandBelow, { to: BAND_EDGES[0] });
  if (i === BANDS.length - 1) return format(s.bandAbove, { from: BAND_EDGES[BAND_EDGES.length - 1] });
  return format(s.bandRange, { from: BAND_EDGES[i - 1], to: BAND_EDGES[i] });
}

/** Your exported scan if this computer has one, else the steps to make one. */
export function LocalScan({ steps }: { steps: ReactNode }) {
  const { homeId } = useParams<{ homeId: string }>();
  const src = folder(homeId);
  const [meta, setMeta] = useState<ScanMeta | null | "missing">(null);
  useEffect(() => {
    let cancelled = false;
    fetch(`${src}/meta.json`, { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : "missing"))
      .catch(() => "missing")
      .then((m) => !cancelled && setMeta(m));
    return () => {
      cancelled = true;
    };
  }, [src]);

  if (meta === null) return <p className="mt-8 text-muted">{s.looking}</p>;
  if (meta === "missing") return <div data-no-scan>{steps}</div>;

  const stats = [
    { value: String(meta.stats.frames), label: s.stats.frames },
    { value: String(Math.round(meta.stats.total_s)), label: s.stats.rebuild },
    { value: String(meta.stats.sam_calls), label: s.stats.sam },
    { value: `${Math.round(meta.count / 1000)}k`, label: s.stats.points },
  ];
  const viewer = {
    label: s.alt,
    loading: s.loading,
    colour: s.colour,
    modes: s.modes,
    layers: s.layers,
    grid: s.grid,
    bands: s.bands,
    surfaces: s.surfaces,
    room: s.room,
    things: s.things,
  };
  return (
    <>
      <FoundViewer
        src={src}
        bounds={meta.bounds}
        surfaces={meta.surfaces}
        room={meta.room}
        furniture={meta.furniture}
        things={meta.objects}
        viewer={viewer}
        found={{ ...s.found, bandNames: s.bandNames }}
        caption={
          <>
            <span className="font-semibold text-ink">{s.alt}</span> {format(s.label, { date: meta.stats.captured })}{" "}
            <span data-viewer-hint>{s.hint}</span>
          </>
        }
      />

      <div className="mt-8">
        <ViewerStats label={s.stats.label} items={stats} />
      </div>

      <div className="mt-8 grid gap-8 sm:grid-cols-2">
        <section aria-labelledby="bands-title">
          <h2 id="bands-title" className="text-sm font-semibold text-muted">
            {s.bandsTitle}
          </h2>
          <p className="mt-1 text-sm text-muted">{s.bandsBody}</p>
          <dl className="mt-3 divide-y divide-fb-line border-y border-fb-line text-sm">
            {BANDS.map((band, i) => (
              <div key={band} data-band={band} className="flex justify-between py-1.5">
                <dt className="font-semibold text-ink">{s.bandNames[band]}</dt>
                <dd className="tabular-nums text-muted">{bandRange(i)}</dd>
              </div>
            ))}
          </dl>
        </section>

        <section aria-labelledby="surfaces-title">
          <h2 id="surfaces-title" className="text-sm font-semibold text-muted">
            {s.surfacesTitle} · {meta.surfaces.length}
          </h2>
          <p className="mt-1 text-sm text-muted">{s.surfacesBody}</p>
          <ol className="mt-3 divide-y divide-fb-line border-y border-fb-line text-sm tabular-nums text-ink">
            {meta.surfaces.map((f, i) => (
              <li key={i} data-surface className="py-1.5">
                {format(s.surfaceRow, {
                  w: (f.max[0] - f.min[0]).toFixed(2),
                  d: (f.max[1] - f.min[1]).toFixed(2),
                  z: f.z.toFixed(2),
                  band: s.bandNames[bandOf(f.z)].toLowerCase(),
                })}
              </li>
            ))}
          </ol>
        </section>
      </div>
    </>
  );
}
