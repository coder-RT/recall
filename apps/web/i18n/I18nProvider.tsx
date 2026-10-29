"use client";

import { createContext, useContext, type ReactNode } from "react";
import { defaultLocale, type Locale } from "./config";
import { getDictionary, type Dictionary } from "./index";

const I18nContext = createContext<{ locale: Locale; t: Dictionary }>({ locale: defaultLocale, t: getDictionary() });

/** Makes the page's language available to client components. Mounted once in the root layout. */
export function I18nProvider({ locale, children }: { locale: Locale; children: ReactNode }) {
  return <I18nContext.Provider value={{ locale, t: getDictionary(locale) }}>{children}</I18nContext.Provider>;
}

/** The current dictionary: `const t = useT(); t.ask.title`. */
export const useT = () => useContext(I18nContext).t;
export const useLocale = () => useContext(I18nContext).locale;
