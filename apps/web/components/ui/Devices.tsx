import { RevealSection } from "@/components/scroll/RevealSection";
import { getDictionary } from "@/i18n";

/**
 * Where Recall runs: the iPhone today, the Watch next, Meta AI glasses planned, home robots in preview. Each card
 * says its status in words (never colour alone), with the same copy as the iPhone app's Devices tab, so nothing
 * planned reads as finished. Product names only; no other company's logos.
 */
export function Devices() {
  const t = getDictionary().devices;
  return (
    <RevealSection id="devices" aria-labelledby="devices-title" className="mx-auto max-w-6xl scroll-mt-20 px-4 py-24">
      <p data-eyebrow className="classic-label">
        {t.eyebrow}
      </p>
      <h2 id="devices-title" data-heading="words" className="mt-4 max-w-3xl text-4xl font-extrabold text-ink sm:text-5xl">
        {t.title}
      </h2>
      <p data-reveal className="mt-4 max-w-2xl text-lg text-muted">
        {t.intro}
      </p>
      <ul className="mt-12 grid gap-6 sm:grid-cols-2">
        {t.items.map((d) => {
          const now = d.status === "available";
          return (
            <li key={d.id} data-reveal data-device={d.id} className="rounded-2xl border border-fb-line p-6">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <h3 className="text-2xl font-extrabold text-fb-blue-dark">{d.name}</h3>
                <span
                  data-status={d.status}
                  className={`rounded-full px-3 py-1 font-classic text-xs font-bold ${now ? "bg-cta-dark text-white" : "bg-fb-blue-pale text-fb-blue-dark"}`}
                >
                  {t.status[d.status]}
                </span>
              </div>
              <p className="mt-3 text-lg font-bold leading-relaxed text-ink">{d.pitch}</p>
              <ul className="mt-3 grid list-disc gap-1 pl-6 text-[1.05rem] leading-relaxed text-ink">
                {d.points.map((p) => (
                  <li key={p}>{p}</li>
                ))}
              </ul>
              {d.built && <p className="mt-3 text-base text-muted" data-built>{d.built}</p>}
              {(d.links?.length || d.id === "robots") && (
                <div className="mt-4" data-device-links>
                  <h4 className="text-sm font-bold uppercase tracking-wide text-muted">{t.open}</h4>
                  <ul className="mt-1 grid gap-1">
                    {d.links?.map((l) => (
                      <li key={l.href}>
                        <a href={l.href} download={l.download || undefined} className="inline-flex min-h-11 items-center font-bold text-fb-blue-dark underline">
                          {l.text}
                        </a>
                      </li>
                    ))}
                    {d.id === "robots" && (
                      <li>
                        <a href="/privacy" className="inline-flex min-h-11 items-center font-bold text-fb-blue-dark underline">
                          {t.robotsPrivacy}
                        </a>
                      </li>
                    )}
                  </ul>
                </div>
              )}
            </li>
          );
        })}
      </ul>
      <p data-reveal className="mt-8 max-w-3xl text-[1.05rem] leading-relaxed text-muted">
        {t.note}
      </p>
    </RevealSection>
  );
}
