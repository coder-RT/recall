/**
 * The landing page's contact form. Sends the message to Rachit through Resend, so his address (CONTACT_TO) stays on
 * the server and never appears in the page. Errors are codes (see `contact.errors` in i18n/dictionaries).
 *
 * Request format from the Resend docs (checked 2026-11-01): POST https://api.resend.com/emails, Authorization: Bearer
 * <key>, JSON { from, to, subject, text, reply_to }. Without a verified domain, `onboarding@resend.dev` can send only
 * to the Resend account's own address, which is all this needs.
 *
 * Bots are turned away by this site's pages only, Vercel BotID (instrumentation-client.ts), a hidden honeypot field,
 * a minimum fill time, a per-visitor limit and a daily cap. The Hobby plan's one firewall rate-limit rule is used by
 * the voice route, so the limits here are this instance's own count (approximate across instances).
 */

import { checkBotId } from "botid/server";
import { contactDisabled, contactMessage, looksAutomated, subjectFor } from "@/lib/contact";
import { clientKey, DailyCap, dailyCapFrom, sameSite, WindowLimit } from "@/lib/voice-guard";

const ENDPOINT = "https://api.resend.com/emails";
const ON_VERCEL = process.env.VERCEL === "1";
const perVisitor = new WindowLimit(3, 10 * 60_000);
const dailyCap = new DailyCap(dailyCapFrom(process.env, "CONTACT_DAILY_CAP", 20));

/** BotID only runs on Vercel; elsewhere (local, tests) the other checks still apply. */
async function isBot(): Promise<boolean> {
  if (!ON_VERCEL) return false;
  try {
    return (await checkBotId()).isBot;
  } catch {
    return true; // the check couldn't run: refuse rather than let a bot through
  }
}

export async function POST(request: Request) {
  if (contactDisabled(process.env)) return Response.json({ error: "disabled" }, { status: 503 });
  if (!sameSite(request.headers)) return Response.json({ error: "forbidden" }, { status: 403 });
  if (await isBot()) return Response.json({ error: "forbidden" }, { status: 403 });

  const parsed = contactMessage.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return Response.json({ error: "invalid" }, { status: 400 });
  const msg = parsed.data;
  // a bot that filled the trap is told it worked, so it doesn't try again
  if (looksAutomated(msg)) return Response.json({ ok: true });

  const key = process.env.RESEND_API_KEY;
  const to = process.env.CONTACT_TO;
  if (!key || !to) return Response.json({ error: "not_configured" }, { status: 503 });
  if (perVisitor.over(clientKey(request.headers, ON_VERCEL))) return Response.json({ error: "rate_limited" }, { status: 429 });
  if (dailyCap.reached()) return Response.json({ error: "daily_limit" }, { status: 429 });

  let res: Response;
  try {
    res = await fetch(ENDPOINT, {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: process.env.CONTACT_FROM || "Recall <onboarding@resend.dev>",
        to: [to],
        reply_to: msg.email,
        subject: subjectFor(msg.name),
        // plain text only: nothing in the message can become markup
        text: `${msg.message}\n\n— ${msg.name} <${msg.email}>, via the Recall website`,
      }),
      signal: AbortSignal.timeout(8_000),
    });
  } catch {
    return Response.json({ error: "failed" }, { status: 502 });
  }
  if (!res.ok) {
    // log the status only; never the message or the sender's address
    console.error(`[contact] Resend failed: HTTP ${res.status}`);
    return Response.json({ error: "failed" }, { status: 502 });
  }
  return Response.json({ ok: true });
}
