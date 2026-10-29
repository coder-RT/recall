import { SampleScan } from "@/components/viewer/SampleScan";
import { format, getDictionary } from "@/i18n";

const t = getDictionary().app.viewer;

// A static page (no params), so the caption, stats and poster are in the HTML even without JavaScript.
export default function SampleViewerPage() {
  return (
    <main className="mx-auto max-w-4xl px-4 py-16">
      <h1 className="text-3xl font-bold text-ink">
        {t.title}
        {format(t.idSuffix, { id: "demo-flat" })}
      </h1>
      <p className="mt-2 text-muted">{t.body}</p>
      <SampleScan />
    </main>
  );
}
