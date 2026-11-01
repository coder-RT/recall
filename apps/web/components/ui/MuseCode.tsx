import { RevealSection } from "@/components/scroll/RevealSection";
import { getDictionary } from "@/i18n";
import { site } from "@/lib/site";

/** How Meta's Muse Code tested Recall: its three tiers of agents, a few counts, and the public write-up. Static;
 *  the section's own reveal is the only motion. */
export function MuseCode() {
  const t = getDictionary().museCode;
  return (
    <RevealSection id="muse-code" aria-labelledby="muse-code-title" className="scroll-mt-20 bg-fb-grey">
      <div className="mx-auto max-w-6xl px-4 py-24">
        <p data-eyebrow className="classic-label">
          {t.eyebrow}
        </p>
        <h2 id="muse-code-title" data-heading="words" className="mt-4 max-w-3xl text-4xl font-extrabold text-ink sm:text-5xl">
          {t.title}
        </h2>
        <p data-reveal className="mt-6 max-w-3xl text-lg leading-relaxed text-ink">
          {t.lead}
        </p>
        <ol className="mt-10 grid gap-6 md:grid-cols-3" data-tiers>
          {t.tiers.map((tier) => (
            <li key={tier.name} data-reveal className="rounded-2xl border border-fb-line bg-white p-6">
              <p className="text-sm font-bold uppercase tracking-wide text-muted">{tier.step}</p>
              <h3 className="mt-1 text-xl font-extrabold text-fb-blue-dark">{tier.name}</h3>
              <p className="mt-2 text-lg leading-relaxed text-ink">{tier.body}</p>
            </li>
          ))}
        </ol>
        <dl className="mt-8 grid gap-4 sm:grid-cols-3" data-stats>
          {t.stats.map((s) => (
            <div key={s.label} data-reveal className="rounded-xl bg-white p-5">
              <dt className="text-base text-muted">{s.label}</dt>
              <dd className="text-4xl font-extrabold text-ink">{s.value}</dd>
            </div>
          ))}
        </dl>
        <p className="mt-6 text-lg">
          <a href={`${site.repo}/blob/main/docs/muse.md#part-b-how-muse-code-tested-recall`} className="font-bold text-fb-blue-dark underline">
            {t.more}
          </a>
        </p>
      </div>
    </RevealSection>
  );
}
