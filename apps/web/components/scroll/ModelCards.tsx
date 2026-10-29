import { getDictionary } from "@/i18n";
import { ModelGlyph } from "./ModelGlyph";
import { RevealSection } from "./RevealSection";

/**
 * Built on Meta's models: cards tilt in and settle (data-card preset in lib/reveal.ts), and each
 * shows a small looping illustration of its job (ModelGlyph).
 */
export function ModelCards() {
  const t = getDictionary();
  return (
    <RevealSection id="models" aria-labelledby="models-title" className="mx-auto max-w-6xl scroll-mt-20 overflow-x-clip px-4 py-24">
      <p data-eyebrow className="classic-label">
        {t.models.eyebrow}
      </p>
      <h2 id="models-title" data-heading="words" className="mt-4 max-w-3xl text-4xl font-extrabold text-ink sm:text-5xl">
        {t.models.title}
      </h2>
      <p data-reveal className="mt-4 max-w-2xl text-lg text-muted">
        {t.models.status}
      </p>
      <ul className="mt-12 grid gap-6 sm:grid-cols-2">
        {t.models.items.map((m) => (
          <li key={m.name} data-card className="card p-6">
            <div className="mb-5 rounded-xl bg-fb-grey px-2 py-1">
              <ModelGlyph kind={m.kind} />
            </div>
            <div className="flex items-start justify-between gap-4">
              <h3 className="text-2xl font-extrabold text-fb-blue-dark">{m.name}</h3>
              <span className="rounded-full bg-fb-blue-pale px-3 py-1 font-classic text-xs font-bold text-fb-blue-dark">
                {t.models.planned}
              </span>
            </div>
            <p className="mt-3 text-lg leading-relaxed text-ink">{m.role}</p>
            <p className="mt-4 font-mono text-sm text-muted">{m.path}</p>
          </li>
        ))}
      </ul>
    </RevealSection>
  );
}
