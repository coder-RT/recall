import type { Metadata, Viewport } from "next";
import { Atkinson_Hyperlegible_Next } from "next/font/google";
import { SpeedInsights } from "@vercel/speed-insights/next";
import { MagnifierLens } from "@/components/ui/MagnifierLens";
import { ReadAloud } from "@/components/ui/ReadAloud";
import { TextMagnifier } from "@/components/ui/TextMagnifier";
import { A11Y_BOOT } from "@/lib/a11y-boot";
import { A11yPrefsProvider } from "@/lib/a11y-prefs";
import { MotionPrefsProvider } from "@/lib/motion-prefs";
import { defaultLocale, htmlLang } from "@/i18n/config";
import { I18nProvider } from "@/i18n/I18nProvider";
import { getDictionary } from "@/i18n";
import "./globals.css";

// Designed for low-vision readers; next/font downloads it at build time and serves it ourselves.
const body = Atkinson_Hyperlegible_Next({
  variable: "--font-body",
  subsets: ["latin"],
});

const t = getDictionary(defaultLocale);

export const metadata: Metadata = {
  title: t.meta.title,
  description: t.meta.description,
};

export const viewport: Viewport = {
  themeColor: "#3b5998",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    // suppressHydrationWarning: the head script sets the visitor's saved settings on <html> first
    <html lang={htmlLang[defaultLocale]} className={`${body.variable} h-full antialiased`} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: A11Y_BOOT }} />
      </head>
      <body className="min-h-full">
        <I18nProvider locale={defaultLocale}>
        <MotionPrefsProvider>
          <A11yPrefsProvider>
            {children}
            <TextMagnifier />
            <MagnifierLens />
            <ReadAloud />
          </A11yPrefsProvider>
        </MotionPrefsProvider>
        </I18nProvider>
        {/* page-speed numbers for Vercel deployments; no cookies, nothing personal; does nothing locally */}
        <SpeedInsights />
      </body>
    </html>
  );
}
