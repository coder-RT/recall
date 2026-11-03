import type { Metadata } from "next";
import Link from "next/link";
import { WalkDemo, type Walks } from "@/components/viewer/WalkDemo";
import { getDictionary } from "@/i18n";
// made by Recall's own code from the recorded run (make demo-walks): the replayed answers and the planner's routes
import walks from "@/public/real-scan/flat/walks.json";

const t = getDictionary().app.demo;

export const metadata: Metadata = {
  title: `${t.metaTitle} · Recall`,
  description: t.metaDescription,
};

/** The no-keys demo: the published real scan, the recorded answers and the walks to each thing. Signed out, no API. */
export default function DemoPage() {
  return (
    <main className="mx-auto max-w-6xl px-4 py-12 sm:py-16">
      <p data-recorded-badge className="inline-flex items-center gap-2 rounded-full border border-fb-line bg-white px-4 py-1.5 text-sm font-semibold tracking-wide text-fb-blue-dark">
        <span aria-hidden className="h-2 w-2 rounded-full bg-cta" />
        {t.badge}
      </p>
      <h1 className="mt-5 text-4xl font-bold tracking-tight text-ink sm:text-5xl">{t.title}</h1>
      <p className="mt-4 max-w-3xl text-lg text-muted">{t.lead}</p>

      <WalkDemo walks={walks as Walks} src="/real-scan/flat" />

      <section aria-labelledby="run-it" className="mt-12 max-w-3xl">
        <h2 id="run-it" className="text-2xl font-bold text-ink">
          {t.judges.title}
        </h2>
        <p className="mt-2 text-base text-muted">{t.judges.body}</p>
        <pre className="mt-3 overflow-x-auto rounded-lg bg-ink px-4 py-3 text-sm text-white">
          <code>{t.judges.code}</code>
        </pre>
        <p className="mt-4">
          <Link href="/homes/flat/viewer" className="font-bold text-fb-blue-dark underline underline-offset-4">
            {t.viewer}
          </Link>
        </p>
      </section>
    </main>
  );
}
