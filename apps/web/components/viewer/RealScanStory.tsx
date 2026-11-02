"use client";

import { format, getDictionary } from "@/i18n";
import { site } from "@/lib/site";
import { bandOf } from "./bands";
import type { ScanMeta } from "./LocalScan";
import { density, extent, floorArea, meanConfidence, perimeter, waiting } from "./scanStats";

const t = getDictionary().app.viewer.story;
const bandNames = getDictionary().app.viewer.scan.bandNames;

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

function Table({ head, rows, label }: { head: string[]; rows: React.ReactNode[][]; label: string }) {
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
  const [w, l] = extent(meta.room.floor);
  const measured: (string | number)[][] = [
    [t.measured.frames, meta.stats.frames],
    ...(minutes ? [[t.measured.walk, format(t.measured.minutes, { n: minutes })]] : []),
    ...(meta.stats.reconstruct_s ? [[t.measured.rebuild, format(t.measured.seconds, { n: meta.stats.reconstruct_s })]] : []),
    [t.measured.total, format(t.measured.seconds, { n: meta.stats.total_s })],
    [t.measured.samCalls, meta.stats.sam_calls.toLocaleString("en")],
    [t.measured.points, meta.count.toLocaleString("en")],
    [t.measured.floor, format(t.measured.area, { n: floorArea(meta.room.floor).toFixed(1) })],
    [t.measured.size, format(t.measured.sizeValue, { w: w.toFixed(2), l: l.toFixed(2) })],
    [t.measured.perimeter, format(t.measured.metres, { n: perimeter(meta.room.floor).toFixed(1) })],
    ...(meta.room.height_m ? [[t.measured.height, format(t.measured.metres, { n: meta.room.height_m.toFixed(2) })]] : []),
    [t.measured.walls, meta.room.walls.length],
    [t.measured.furniture, meta.furniture.length],
    [t.measured.things, things.length],
    [t.measured.waiting, waiting(things)],
    [t.measured.sure, `${Math.round(meanConfidence(things) * 100)}%`],
    [t.measured.flats, meta.surfaces.length],
    ...(meta.voxel_m ? [[t.measured.spacing, format(t.measured.cm, { n: (meta.voxel_m * 100).toFixed(1) })]] : []),
    [t.measured.density, Math.round(density(meta.count, meta.room.floor)).toLocaleString("en")],
    ...(meta.mesh ? [[t.measured.triangles, meta.mesh.triangles.toLocaleString("en")]] : []),
    ...(meta.room.north_deg != null ? [[t.measured.north, format(t.measured.degrees, { n: Math.round(meta.room.north_deg) })]] : []),
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
          <Table
            label={t.robots.title}
            head={t.robots.head}
            rows={t.robots.rows.map((r) => [
              r.file,
              r.what,
              <span key="d" className="flex flex-wrap gap-x-3">
                {r.files.map((f) => (
                  <a key={f} href={`${src}/robot/${f}`} download data-robot-file={f} className="font-semibold text-fb-blue-dark underline">
                    {f}
                  </a>
                ))}
              </span>,
            ])}
          />
          <p className="mt-4 flex flex-wrap items-center gap-4">
            <a href={`${src}/robot/recall-living-room.zip`} download className="btn btn-blue" data-robot-zip>
              {t.robots.all}
            </a>
            <span className="text-sm text-muted">{t.robots.real}</span>
          </p>
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

        <aside aria-labelledby="public-data-title" className="mt-12 rounded-2xl border-2 border-fb-blue bg-white p-6" data-privacy-note>
          <h2 id="public-data-title" className="flex items-center gap-2 text-xl font-extrabold text-fb-blue-dark">
            <svg aria-hidden viewBox="0 0 24 24" className="size-6 fill-current">
              <path d="M12 2 4 5v6c0 5 3.4 9.7 8 11 4.6-1.3 8-6 8-11V5l-8-3Zm-1.2 14.2-3.5-3.5 1.4-1.4 2.1 2.1 4.6-4.6 1.4 1.4-6 6Z" />
            </svg>
            {t.privacyTitle}
          </h2>
          <p className="mt-2 text-base text-ink">{format(t.privacy, { src })}</p>
          <ul className="mt-3 flex flex-wrap gap-2">
            {t.privacyItems.map((item) => (
              <li key={item} className="rounded-full bg-fb-blue-pale px-3 py-1 text-sm font-semibold text-fb-blue-dark">
                {item}
              </li>
            ))}
          </ul>
          <p className="mt-3 text-sm font-semibold text-ink">{t.privacyNever}</p>
        </aside>
      </div>
    );
  }
  return (
    <div data-real-scan-story="before">
      <Section id="models-title" title={t.models.title} lead={t.models.lead}>
        <Table label={t.models.title} head={t.models.head} rows={models} />
      </Section>

      <Section id="agents-title" title={t.agents.title} lead={t.agents.lead}>
        <Table label={t.agents.title} head={t.agents.head} rows={t.agents.rows.map((r) => [r.agent, r.job, r.model, r.may, r.runs])} />
        <p className="mt-3 text-sm">
          <a href={`${site.repo}/blob/main/docs/muse.md#part-b-how-muse-code-tested-recall`} className="font-semibold text-fb-blue-dark underline">
            {t.agents.link}
          </a>
        </p>
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
