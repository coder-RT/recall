"use client";

import { useParams } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";
import { format, getDictionary } from "@/i18n";
import { BAND_EDGES, BANDS, bandOf } from "./bands";
import { PUBLIC_SCANS, scanFolder } from "@/lib/scans";
import { FoundViewer } from "./FoundViewer";
import { extent, floorArea, perimeter } from "./scanStats";
import { Sheets } from "./Sheets";
import { RealScanStory } from "./RealScanStory";
import type { FurnitureBox, RoomShape, Surface, Thing } from "./Layers";
import { ViewerStats } from "./ViewerStats";

const s = getDictionary().app.viewer.scan;

export interface ScanMeta {
  count: number;
  bounds: { min: number[]; max: number[] };
  surfaces: Surface[];
  room: RoomShape;
  furniture: FurnitureBox[];
  objects: Thing[];
  stats: {
    frames: number;
    total_s: number;
    sam_calls: number;
    captured: string;
    duration_s?: number;
    reconstruct_s?: number;
  };
  /** the published real scan: geometry only, every colour from height (make public-scan) */
  public?: boolean;
  /** present when the export built a surface mesh */
  mesh?: { vertices: number; triangles: number };
  /** present when the export painted the surface with the scan's photos */
  photo?: { frames_used: number; textured_share: number };
  /** present when the export regenerated the room (architect.json) */
  architect?: { walls: number; scanned_walls: number };
  /** the spacing of the published points, metres */
  voxel_m?: number;
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
  const src = scanFolder(homeId);
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
    axes: s.axes,
    axisLabels: s.axisLabels,
    best: s.best,
    more: s.more,
    camera: s.camera,
    presets: s.presets,
    wallOpacity: s.wallOpacity,
    showFurniture: s.showFurniture,
    wireframe: s.wireframe,
    flat: s.flat,
    cut: s.cut,
  };
  return (
    <>
      {PUBLIC_SCANS.has(homeId) && (
        <>
          <p className="mt-4 max-w-3xl text-lg text-muted" data-real-intro>
            {format(getDictionary().app.viewer.real.body, { date: meta.stats.captured })}
          </p>
          <p className="mt-6 flex flex-wrap items-center gap-3" data-try-it>
            <span className="rounded-full bg-cta-dark px-3 py-1 text-sm font-bold text-white">{getDictionary().app.viewer.real.tryIt}</span>
            <span className="text-base text-ink">{getDictionary().app.viewer.real.tryHint}</span>
          </p>
        </>
      )}
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

      {PUBLIC_SCANS.has(homeId) && <RealScanStory meta={meta} src={src} part="before" />}

      {meta.drawings && meta.drawings.length > 0 && (
        <section aria-labelledby="drawings-title" className="mt-10">
          {PUBLIC_SCANS.has(homeId) ? (
            <>
              <h2 id="drawings-title" className="mt-6 text-3xl font-bold tracking-tight text-ink sm:text-4xl">
                {s.drawings.publicTitle}
              </h2>
              <p className="mt-3 max-w-3xl text-lg text-muted">{s.drawings.body}</p>
            </>
          ) : (
            <>
              <h2 id="drawings-title" className="text-sm font-semibold text-muted">
                {s.drawings.title} · {meta.drawings.length}
              </h2>
              <p className="mt-1 text-sm text-muted">{s.drawings.body}</p>
            </>
          )}
          {PUBLIC_SCANS.has(homeId) && (
            <>
              <p className="mt-3 max-w-3xl rounded-lg border-l-4 border-fb-blue bg-white px-4 py-3 text-base text-ink" data-drawings-credit>
                {s.drawings.credit}
              </p>
              <dl className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6" data-drawing-stats>
                {[
                  [s.drawings.stats.area, `${floorArea(meta.room.floor).toFixed(1)} m²`],
                  [s.drawings.stats.size, (([w, l]) => `${w.toFixed(2)} × ${l.toFixed(2)} m`)(extent(meta.room.floor))],
                  [s.drawings.stats.perimeter, `${perimeter(meta.room.floor).toFixed(1)} m`],
                  ...(meta.room.height_m ? [[s.drawings.stats.height, `${meta.room.height_m.toFixed(2)} m`]] : []),
                  ...(meta.architect ? [[s.drawings.stats.walls, `${meta.architect.walls} (${meta.architect.scanned_walls} ${s.drawings.stats.scanned})`]] : []),
                  [s.drawings.stats.shown, `${meta.objects.length + meta.furniture.length}`],
                ].map(([k, v]) => (
                  <div key={k} className="rounded-lg bg-white px-3 py-2">
                    <dt className="text-xs text-muted">{k}</dt>
                    <dd className="text-lg font-bold tabular-nums text-ink">{v}</dd>
                  </div>
                ))}
              </dl>
            </>
          )}
          <Sheets sheets={meta.drawings} src={src} t={{ download: s.drawings.download, zoom: s.drawings.zoom, close: s.drawings.close }} />
        </section>
      )}

      {PUBLIC_SCANS.has(homeId) && <RealScanStory meta={meta} src={src} part="after" />}

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
