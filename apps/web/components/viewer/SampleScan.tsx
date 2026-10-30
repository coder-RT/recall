import { format, getDictionary } from "@/i18n";
import meta from "@/public/samples/demo-flat/meta.json";
import { BAND_EDGES, BANDS, bandOf } from "./bands";
import { FoundViewer } from "./FoundViewer";
import { ViewerStats } from "./ViewerStats";

const s = getDictionary().app.viewer.sample;
const SAMPLE = "/samples/demo-flat";

function bandRange(i: number) {
  if (i === 0) return format(s.bandBelow, { to: BAND_EDGES[0] });
  if (i === BANDS.length - 1) return format(s.bandAbove, { from: BAND_EDGES[BAND_EDGES.length - 1] });
  return format(s.bandRange, { from: BAND_EDGES[i - 1], to: BAND_EDGES[i] });
}

/** The sample room: a real run of our pipeline on one room. Caption, stats, bands and the found list are plain HTML. */
export function SampleScan() {
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
        src={SAMPLE}
        bounds={meta.bounds}
        surfaces={meta.surfaces}
        room={meta.room}
        furniture={meta.furniture}
        things={meta.objects}
        viewer={viewer}
        found={{ ...s.found, bandNames: s.bandNames }}
        caption={
          <>
            <span className="font-semibold text-ink">{s.alt}</span> {s.label} {s.scale} <span data-viewer-hint>{s.hint}</span>
          </>
        }
        poster={
          <noscript>
            {/* eslint-disable-next-line @next/next/no-img-element -- a static poster for visitors without JavaScript */}
            <img src={`${SAMPLE}/poster.webp`} alt={s.posterAlt} className="size-full object-contain" />
          </noscript>
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
