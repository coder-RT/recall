import Link from "next/link";
import { BackToTop } from "@/components/ui/BackToTop";
import { Logo } from "@/components/ui/Logo";
import { getDictionary } from "@/i18n";

/** The app pages (a home's scan and its viewer): a slim bar that always leads back to the landing page. */
export default function AppLayout({ children }: LayoutProps<"/">) {
  const t = getDictionary().app.viewer.back;
  return (
    <div className="min-h-dvh bg-fb-grey">
      <nav aria-label={t.label} className="bg-fb-blue text-white" data-app-nav>
        <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-x-6 gap-y-1 px-4 py-2">
          <Link href="/" aria-label={t.home} className="inline-flex min-h-11 items-center">
            <Logo />
          </Link>
          <div className="flex flex-wrap items-center gap-x-5">
            <Link href="/" className="inline-flex min-h-11 items-center gap-2 font-bold underline-offset-4 hover:underline">
              <span aria-hidden>←</span>
              {t.back}
            </Link>
            <Link href="/#ask" className="inline-flex min-h-11 items-center font-bold underline-offset-4 hover:underline">
              {t.ask}
            </Link>
          </div>
        </div>
      </nav>
      {children}
      <BackToTop />
    </div>
  );
}
