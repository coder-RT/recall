import { Suspense } from "react";
import { format, getDictionary } from "@/i18n";

const t = getDictionary().app.home;

// With cacheComponents, the dynamic param is read inside <Suspense> so the rest prerenders as the shell.
async function HomeName({ params }: Pick<PageProps<"/homes/[homeId]">, "params">) {
  const { homeId } = await params;
  return <>{format(t.title, { id: homeId })}</>;
}

export default function HomePage({ params }: PageProps<"/homes/[homeId]">) {
  return (
    <main className="mx-auto max-w-3xl px-4 py-16">
      <h1 className="text-3xl font-bold text-ink">
        <Suspense fallback={t.fallback}>
          <HomeName params={params} />
        </Suspense>
      </h1>
      <p className="mt-2 text-muted">{t.body}</p>
    </main>
  );
}
