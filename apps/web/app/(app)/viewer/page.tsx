import { LocalScan } from "@/components/viewer/LocalScan";
import { ScanSteps } from "@/components/viewer/ScanSteps";
import { getDictionary } from "@/i18n";

const t = getDictionary().app.viewer;

// Your own room, from your own Mac: the page looks for a scan exported on this computer (make viewer) and shows the
// steps to make one when there is none. No room ships with the repo or the hosted site.
export default function ViewerPage() {
  return (
    <main className="mx-auto max-w-5xl px-4 py-16">
      <h1 className="text-3xl font-bold text-ink">{t.title}</h1>
      <p className="mt-2 text-muted">{t.body}</p>
      <LocalScan steps={<ScanSteps />} />
      <noscript>
        <ScanSteps />
      </noscript>
    </main>
  );
}
