import type { Metadata } from "next";
import { getDictionary } from "@/i18n";

const t = getDictionary();

export const metadata: Metadata = {
  title: `${t.privacy.title} · Recall`,
  description: t.privacy.description,
};

/** The privacy note: the same facts as docs/privacy.md and the iPhone app's Settings → Privacy. Plain HTML, no motion. */
export default function PrivacyPage() {
  const p = t.privacy;
  return (
    <article className="mx-auto max-w-3xl px-4 py-16 sm:py-24">
      <p className="classic-label">{p.eyebrow}</p>
      <h1 className="mt-4 text-4xl font-extrabold text-ink sm:text-5xl">{p.heading}</h1>
      <p className="mt-6 text-xl leading-relaxed text-ink">{p.short}</p>

      <section aria-labelledby="kept" className="mt-14">
        <h2 id="kept" className="text-2xl font-extrabold text-fb-blue-dark">
          {p.keptTitle}
        </h2>
        <ul className="mt-5 grid gap-3">
          {p.kept.map((line) => (
            <li key={line} className="rounded-xl bg-fb-grey p-5 text-lg leading-relaxed text-ink">
              {line}
            </li>
          ))}
        </ul>
      </section>

      <section aria-labelledby="sent" className="mt-14">
        <h2 id="sent" className="text-2xl font-extrabold text-fb-blue-dark">
          {p.sentTitle}
        </h2>
        <ul className="mt-5 grid gap-3">
          {p.sent.map((row) => (
            <li key={row.what} className="rounded-2xl border border-fb-line p-5">
              <h3 className="text-lg font-bold text-ink">{row.what}</h3>
              <dl className="mt-2 grid gap-1 text-[1.05rem] leading-relaxed">
                <div className="flex flex-wrap gap-x-2">
                  <dt className="font-bold text-muted">{p.sentLabels.to}:</dt>
                  <dd className="text-ink">{row.to}</dd>
                </div>
                <div className="flex flex-wrap gap-x-2">
                  <dt className="font-bold text-muted">{p.sentLabels.when}:</dt>
                  <dd className="text-ink">{row.when}</dd>
                </div>
              </dl>
            </li>
          ))}
        </ul>
        <p className="mt-4 text-[1.05rem] leading-relaxed text-muted">{p.theirTerms}</p>
      </section>

      <section aria-labelledby="never" className="mt-14">
        <h2 id="never" className="text-2xl font-extrabold text-fb-blue-dark">
          {p.neverTitle}
        </h2>
        <ul className="mt-5 grid list-disc gap-2 pl-6 text-lg leading-relaxed text-ink">
          {p.never.map((line) => (
            <li key={line}>{line}</li>
          ))}
        </ul>
      </section>

      <section aria-labelledby="controls" className="mt-14">
        <h2 id="controls" className="text-2xl font-extrabold text-fb-blue-dark">
          {p.controlsTitle}
        </h2>
        <ul className="mt-5 grid gap-4 sm:grid-cols-2">
          {p.controls.map((c) => (
            <li key={c.title} className="rounded-2xl border border-fb-line p-5">
              <h3 className="text-lg font-bold text-ink">{c.title}</h3>
              <p className="mt-1 text-[1.05rem] leading-relaxed text-ink">{c.body}</p>
            </li>
          ))}
        </ul>
      </section>

      <section aria-labelledby="site" className="mt-14">
        <h2 id="site" className="text-2xl font-extrabold text-fb-blue-dark">
          {p.siteTitle}
        </h2>
        <p className="mt-4 text-lg leading-relaxed text-ink">{p.site}</p>
      </section>

      <p className="mt-14 text-[1.05rem] leading-relaxed text-muted">{p.source}</p>
    </article>
  );
}
