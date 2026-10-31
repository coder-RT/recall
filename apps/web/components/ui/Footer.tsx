import { format, getDictionary } from "@/i18n";
import { site } from "@/lib/site";

/**
 * The 2009 footer: a thin rule, then one row with the copyright on the left and the links on the
 * right, a small square separating the site's links from the author's; the fine print beneath.
 */
export function Footer() {
  const t = getDictionary();
  const link = "text-fb-blue-dark hover:underline";
  const ours = [
    { href: site.repo, label: t.footer.source },
    { href: site.author.linkedin, label: t.footer.linkedin },
    { href: site.author.github, label: t.footer.github },
  ];
  return (
    <footer className="border-t border-fb-line bg-white">
      <div className="mx-auto max-w-6xl px-4 py-6 font-classic text-[0.8125rem]">
        <div className="flex flex-wrap items-baseline justify-between gap-x-8 gap-y-2">
          <p className="text-muted">{format(t.footer.copyright, { name: site.name })}</p>
          <ul className="flex flex-wrap items-baseline gap-x-4 gap-y-2">
            {t.nav.links.map((item) => (
              <li key={item.href}>
                <a href={`/${item.href}`} className={link}>
                  {item.label}
                </a>
              </li>
            ))}
            <li>
              <a href="/privacy" className={link}>
                {t.nav.privacy}
              </a>
            </li>
            <li aria-hidden="true" className="select-none text-[0.5rem] text-fb-line">
              ■
            </li>
            {ours.map((item) => (
              <li key={item.href}>
                <a href={item.href} rel="me noopener" className={link}>
                  {item.label}
                </a>
              </li>
            ))}
          </ul>
        </div>
        <p className="mt-3 text-muted">{format(t.footer.fineprint, { author: site.author.name, event: site.event })}</p>
      </div>
    </footer>
  );
}
