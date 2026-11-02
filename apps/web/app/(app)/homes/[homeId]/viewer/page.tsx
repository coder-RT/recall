import { redirect } from "next/navigation";
import { Suspense } from "react";
import { LocalScan } from "@/components/viewer/LocalScan";
import { ScanSteps } from "@/components/viewer/ScanSteps";
import { format, getDictionary } from "@/i18n";
import { PUBLIC_SCANS, SCAN_ALIASES } from "@/lib/scans";

const t = getDictionary().app.viewer;

// With cacheComponents, the dynamic param is read inside <Suspense> so the rest prerenders as the shell.
async function Heading({ params }: Pick<PageProps<"/homes/[homeId]/viewer">, "params">) {
  const { homeId } = await params;
  const alias = SCAN_ALIASES[homeId];
  if (alias) redirect(`/homes/${alias}/viewer`);
  if (PUBLIC_SCANS.has(homeId)) {
    return (
      <>
        <p
          data-real-badge
          className="inline-flex items-center gap-2 rounded-full border border-fb-line bg-white px-4 py-1.5 text-sm font-semibold tracking-wide text-fb-blue-dark"
        >
          <span aria-hidden className="h-2 w-2 rounded-full bg-cta" />
          {t.real.badge}
        </p>
        <h1 className="mt-5 text-4xl font-bold tracking-tight text-ink sm:text-5xl">{t.real.title}</h1>
      </>
    );
  }
  return (
    <>
      <h1 className="text-3xl font-bold text-ink">
        {t.title}
        {format(t.idSuffix, { id: homeId })}
      </h1>
      <p className="mt-2 text-muted">{t.body}</p>
    </>
  );
}

// The author's real living room is published (geometry only, lib/scans.ts); any other home is your own, exported on
// this computer (make viewer), with the steps to make one when there is none.
export default function ViewerPage({ params }: PageProps<"/homes/[homeId]/viewer">) {
  return (
    <main className="mx-auto max-w-5xl px-4 py-16">
      <Suspense fallback={<h1 className="text-3xl font-bold text-ink">{t.title}</h1>}>
        <Heading params={params} />
      </Suspense>
      <Suspense fallback={null}>
        <LocalScan steps={<ScanSteps />} />
      </Suspense>
      <noscript>
        <ScanSteps />
      </noscript>
    </main>
  );
}
