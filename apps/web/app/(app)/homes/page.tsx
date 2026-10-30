import { getDictionary } from "@/i18n";

export default function HomesPage() {
  const t = getDictionary().app.homes;
  return (
    <main className="mx-auto max-w-3xl px-4 py-16">
      <h1 className="text-3xl font-bold text-ink">{t.title}</h1>
      <p className="mt-2 text-muted">{t.body}</p>
    </main>
  );
}
