import { Suspense } from "react";
import { format, getDictionary } from "@/i18n";

const t = getDictionary().app.viewer;

async function HomeId({ params }: Pick<PageProps<"/homes/[homeId]/viewer">, "params">) {
  const { homeId } = await params;
  return <>{format(t.idSuffix, { id: homeId })}</>;
}

// No home has a scan in the memory store yet; the sample room has its own static page (homes/demo-flat/viewer).
export default function ViewerPage({ params }: PageProps<"/homes/[homeId]/viewer">) {
  return (
    <main className="mx-auto max-w-4xl px-4 py-16">
      <h1 className="text-3xl font-bold text-ink">
        {t.title}
        <Suspense fallback={null}>
          <HomeId params={params} />
        </Suspense>
      </h1>
      <p className="mt-2 text-muted">{t.body}</p>
      <p className="mt-6 text-muted">{t.empty}</p>
    </main>
  );
}
