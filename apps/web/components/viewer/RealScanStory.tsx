"use client";

import { format, getDictionary } from "@/i18n";
import { site } from "@/lib/site";
import { bandOf } from "./bands";
import type { ScanMeta } from "./LocalScan";

const t = getDictionary().app.viewer.story;
const bandNames = getDictionary().app.viewer.scan.bandNames;

/** Floor area from the room's outline (shoelace), in square metres. */
function floorArea(meta: ScanMeta) {
  const p = meta.room.floor;
  let a = 0;
  for (let i = 0; i < p.length; i++) {
    const [x1, y1] = p[i];
    const [x2, y2] = p[(i + 1) % p.length];
    a += x1 * y2 - x2 * y1;
  }
  return Math.abs(a) / 2;
}

/** A section with one big heading, the way the rest of the page reads. */
function Section({ id, title, lead, children }: { id: string; title: string; lead: string; children: React.ReactNode }) {
  return (
    <section aria-labelledby={id} className="mt-16" data-story={id}>
      <h2 id={id} className="text-3xl font-bold tracking-tight text-ink sm:text-4xl">
        {title}
      </h2>
      <p className="mt-3 max-w-3xl text-lg text-muted">{lead}</p>
      <div className="mt-6">{children}</div>
    </section>
  );
}

function Table({ head, rows, label }: { head: string[]; rows: (string | number)[][]; label: string }) {
  return (
    <div className="overflow-x-auto rounded-xl border border-fb-line bg-white">
      <table className="w-full text-left text-sm">
        <caption className="sr-only">{label}</caption>
        <thead className="bg-fb-grey text-ink">
          <tr>
            {head.map((h) => (
              <th key={h} scope="col" className="px-4 py-3 font-semibold">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-fb-line tabular-nums text-ink">
          {rows.map((r, i) => (
            <tr key={i}>
              {r.map((c, j) =>
                j === 0 ? (
                  <th key={j} scope="row" className="px-4 py-2.5 font-semibold">
                    {c}
                  </th>
                ) : (
                  <td key={j} className="px-4 py-2.5 text-muted">
                    {c}
                  </td>
                ),
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/**
 * The published real scan, told section by section: that it is real, which Meta model made which part, the measured
 * numbers, what SAM 3.1 found, what a robot gets, and how it all fits. Every number comes from this scan's meta.json.
 */
export function RealScanStory({ meta, src, part }: { meta: ScanMeta; src: string; part: "before" | "after" }) {
  const things = meta.objects;
  const minutes = meta.stats.duration_s ? (meta.stats.duration_s / 60).toFixed(1) : null;
  const models = t.models.rows.map((r) => [
    r.model,
    r.made,
    format(r.numbers, {
      points: meta.count.toLocaleString("en"),
      frames: meta.stats.frames,
      calls: meta.stats.sam_calls.toLocaleString("en"),
      furniture: meta.furniture.length,
      things: things.length,
    }),
    r.runs,
  ]);
  const measured: (string | number)[][] = [
    [t.measured.frames, meta.stats.frames],
    ...(minutes ? [[t.measured.walk, format(t.measured.minutes, { n: minutes })]] : []),
    ...(meta.stats.reconstruct_s ? [[t.measured.rebuild, format(t.measured.seconds, { n: meta.stats.reconstruct_s })]] : []),
    [t.measured.total, format(t.measured.seconds, { n: meta.stats.total_s })],
    [t.measured.samCalls, meta.stats.sam_calls.toLocaleString("en")],
    [t.measured.points, meta.count.toLocaleString("en")],
    [t.measured.floor, format(t.measured.area, { n: floorArea(meta).toFixed(1) })],
    ...(meta.room.height_m ? [[t.measured.height, format(t.measured.metres, { n: meta.room.height_m.toFixed(2) })]] : []),
    [t.measured.walls, meta.room.walls.length],
    [t.measured.furniture, meta.furniture.length],
    [t.measured.things, things.length],
  ];
  const found = things.map((o) => [
    [o.color, o.label].filter(Boolean).join(" "),
    bandNames[bandOf(o.at[2])],
    o.size ? o.size.map((v) => Math.round(v * 100)).join(" × ") + " cm" : "–",
    o.photos ?? "–",
    `${Math.round(o.confidence * 100)}%`,
    // Balanced, the default level: seen in at least 2 photos (or confirmed by the owner)
    o.photos == null || o.photos >= 2 ? t.found.told : t.found.waits,
  ]);
  if (part === "after") {
    return (
      <div data-real-scan-story="after">
        <Section id="robots-title" title={t.robots.title} lead={t.robots.lead}>
          <Table label={t.robots.title} head={t.robots.head} rows={t.robots.rows.map((r) => [r.file, r.what])} />
          <p className="mt-4 text-sm text-muted">{t.robots.fetch}</p>
        </Section>

        <Section id="how-title" title={t.how.title} lead={t.how.lead}>
          <figure className="overflow-hidden rounded-xl border border-fb-line bg-white p-4">
            {/* eslint-disable-next-line @next/next/no-img-element -- a generated SVG diagram, not an optimisable photo */}
            <img src="/diagrams/two-paths.svg" alt={t.how.alt} className="h-auto w-full" />
            <figcaption className="mt-3 text-sm text-muted">
              {t.how.caption}{" "}
              <a href={`${site.repo}/blob/main/docs/architecture.md`} className="font-semibold text-fb-blue-dark underline">
                {t.how.link}
              </a>
            </figcaption>
          </figure>
        </Section>

        <Section id="install-title" title={t.install.title} lead={t.install.lead}>
          <a href="/INSTALL.md" download className="btn btn-blue" data-install-link>
            {t.install.download}
          </a>
        </Section>

        <p className="mt-12 text-sm text-muted" data-privacy-note>
          {format(t.privacy, { src })}
        </p>
      </div>
    );
  }
  return (
    <div data-real-scan-story="before">
      <Section id="models-title" title={t.models.title} lead={t.models.lead}>
        <Table label={t.models.title} head={t.models.head} rows={models} />
      </Section>

      <Section id="measured-title" title={t.measured.title} lead={format(t.measured.lead, { date: meta.stats.captured })}>
        <Table label={t.measured.title} head={t.measured.head} rows={measured} />
      </Section>

      <Section id="found-title" title={format(t.found.title, { n: things.length })} lead={t.found.lead}>
        <Table label={t.found.title} head={t.found.head} rows={found} />
      </Section>

    </div>
  );
}
