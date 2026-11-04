import { getDictionary } from "@/i18n";

/** What the iPhone does live, in AR and by voice, and exactly when it listens: the pages around it replay or show a scan. */
export function ArOnPhone() {
  const t = getDictionary().app.arMode;
  return (
    <section aria-labelledby="ar-on-phone" className="mt-12" data-ar-mode>
      <h2 id="ar-on-phone" className="text-2xl font-bold text-ink">
        {t.title}
      </h2>
      <p className="mt-2 max-w-3xl text-base text-muted">{t.lead}</p>
      <ol className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
        {t.steps.map((step, i) => (
          <li key={step.title} className="card p-4">
            <p aria-hidden className="text-sm font-bold text-fb-blue-dark">
              {i + 1}
            </p>
            <h3 className="mt-1 text-base font-bold text-ink">{step.title}</h3>
            <p className="mt-1 text-sm text-muted">{step.body}</p>
          </li>
        ))}
      </ol>
      <div className="card mt-3 border-l-4 border-fb-blue p-4" data-when-it-listens>
        <h3 className="text-base font-bold text-ink">{t.listenTitle}</h3>
        <p className="mt-1 max-w-3xl text-sm text-muted">{t.listen}</p>
      </div>
    </section>
  );
}
