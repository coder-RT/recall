import { getDictionary } from "@/i18n";

const t = getDictionary().app.viewer.steps;

/** How to see your own room here: plain HTML, so it reads without JavaScript. */
export function ScanSteps() {
  return (
    <section aria-labelledby="steps-title" className="mt-8 rounded-xl border border-fb-line bg-white p-6">
      <h2 id="steps-title" className="text-xl font-bold text-ink">
        {t.title}
      </h2>
      <p className="mt-2 text-muted">{t.body}</p>
      <ol className="mt-4 list-decimal space-y-3 pl-6 text-ink">
        {t.items.map((item) => (
          <li key={item.text}>
            {item.text}
            {item.code && (
              <pre className="mt-1 overflow-x-auto rounded-md bg-fb-grey px-3 py-2 text-sm">
                <code>{item.code}</code>
              </pre>
            )}
          </li>
        ))}
      </ol>
      <p className="mt-4 text-sm text-muted">{t.privacy}</p>
    </section>
  );
}
