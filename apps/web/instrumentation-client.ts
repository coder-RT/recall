import { initBotId } from "botid/client/core";

// Vercel BotID: an invisible check that the contact form is sent by a browser, not a script (docs checked 2026-11-01).
// Vercel serves BotID's script itself, so next.config needs no wrapper; elsewhere the script doesn't exist and the
// wrapped fetch would fail, so it runs only in a Vercel build (NEXT_PUBLIC_VERCEL_ENV is one of Vercel's system
// variables), matching the server, which checks only on Vercel (app/api/contact/route.ts).
if (process.env.NEXT_PUBLIC_VERCEL_ENV) {
  initBotId({ protect: [{ path: "/api/contact", method: "POST" }] });
}
