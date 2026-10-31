import { Suspense } from "react";
import { LocalScan } from "@/components/viewer/LocalScan";
import { ScanSteps } from "@/components/viewer/ScanSteps";
import { format, getDictionary } from "@/i18n";

const t = getDictionary().app.viewer;

// With cacheComponents, the dynamic param is read inside <Suspense> so the rest prerenders as the shell.
async function HomeId({ params }: Pick<PageProps<"/homes/[homeId]/viewer">, "params">) {
  const { homeId } = await params;
  return <>{format(t.idSuffix, { id: homeId })}</>;
}

// Your own home, from your own Mac: the page looks for this home's scan exported on this computer (make viewer) and
// shows the steps to make one when there is none. No home ships with the repo or the hosted site.
export default function ViewerPage({ params }: PageProps<"/homes/[homeId]/viewer">) {
  return (
    <main className="mx-auto max-w-5xl px-4 py-16">
      <h1 className="text-3xl font-bold text-ink">
        {t.title}
        <Suspense fallback={null}>
          <HomeId params={params} />
        </Suspense>
      </h1>
      <p className="mt-2 text-muted">{t.body}</p>
      <Suspense fallback={null}>
        <LocalScan steps={<ScanSteps />} />
      </Suspense>
      <noscript>
        <ScanSteps />
      </noscript>
    </main>
  );
}
