/**
 * Languages the site is written in. English only for now; to add one, create
 * dictionaries/<locale>.ts typed as `Dictionary` (TypeScript lists any missing text), add the
 * locale here, then follow Next's internationalization guide for app/[lang] routing and the proxy.
 */
export const locales = ["en"] as const;
export type Locale = (typeof locales)[number];
export const defaultLocale: Locale = "en";

/** The <html lang> value for each locale (also used to pick speech voices). */
export const htmlLang: Record<Locale, string> = { en: "en" };
