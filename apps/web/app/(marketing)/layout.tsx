import { CookieNotice } from "@/components/ui/CookieNotice";
import { Footer } from "@/components/ui/Footer";
import { Nav } from "@/components/ui/Nav";
import { ReactionsProvider } from "@/lib/reactions";

export default function MarketingLayout({ children }: LayoutProps<"/">) {
  return (
    <ReactionsProvider>
      <Nav />
      <main id="main">{children}</main>
      <Footer />
      <CookieNotice />
    </ReactionsProvider>
  );
}
