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
  /** present when the export built a surface mesh */
  mesh?: { vertices: number; triangles: number };
  /** present when the export painted the surface with the scan's photos */
  photo?: { frames_used: number; textured_share: number };
  /** present when the export regenerated the room (architect.json) */
  architect?: { walls: number; scanned_walls: number };
  /** the drawing sheets (SVG) the export made */
  drawings?: { id: string; title: string; file: string; summary: string }[];
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
    view: s.view,
    views: s.views,
    viewNotes: s.viewNotes,
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
        hasMesh={Boolean(meta.mesh)}
        hasPhoto={Boolean(meta.photo)}
        hasArchitect={Boolean(meta.architect)}
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

      {meta.drawings && meta.drawings.length > 0 && (
        <section aria-labelledby="drawings-title" className="mt-10">
          <h2 id="drawings-title" className="text-sm font-semibold text-muted">
            {s.drawings.title} · {meta.drawings.length}
          </h2>
          <p className="mt-1 text-sm text-muted">{s.drawings.body}</p>
          <ul className="mt-4 grid gap-6 lg:grid-cols-2">
            {meta.drawings.map((d) => (
              <li key={d.id} data-sheet={d.id}>
                <figure className="overflow-hidden rounded-xl border border-fb-line bg-white">
                  {/* eslint-disable-next-line @next/next/no-img-element -- a local SVG sheet, not an optimisable photo */}
                  <img src={`${src}/${d.file}`} alt={d.summary} width={1587} height={1123} className="h-auto w-full" />
                  <figcaption className="flex items-center justify-between gap-3 border-t border-fb-line px-4 py-3 text-sm">
                    <span className="font-semibold text-ink">
                      {d.id} · {d.title}
                    </span>
                    <a href={`${src}/${d.file}`} download className="font-semibold text-fb-blue-dark underline">
                      {format(s.drawings.download, { id: d.id })}
                    </a>
                  </figcaption>
                </figure>
              </li>
            ))}
          </ul>
        </section>
      )}

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
