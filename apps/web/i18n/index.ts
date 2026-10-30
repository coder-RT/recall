import { defaultLocale, type Locale } from "./config";
import { en } from "./dictionaries/en";

/** The shape every language's dictionary must match (English is the source). */
export type Dictionary = typeof en;

const dictionaries: Record<Locale, Dictionary> = { en };

/** Text for a locale; server components call this, client components use `useT()`. */
export function getDictionary(locale: Locale = defaultLocale): Dictionary {
  return dictionaries[locale];
}

/** Fill `{name}` placeholders: format("Step {n} of {total}", { n: 1, total: 3 }). */
export function format(template: string, values: Record<string, string | number>) {
  return template.replace(/\{(\w+)\}/g, (match, key: string) => (key in values ? String(values[key]) : match));
}
