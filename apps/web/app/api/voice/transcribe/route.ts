/**
 * Speech-to-text for the landing demo's "Ask by voice". Forwards a short WAV to Meta Muse Voice
 * Transcribe so META_MUSE_API_KEY never reaches the browser. Recall doesn't store the audio.
 * Errors are codes (see `ask.errors` in i18n/dictionaries); the card shows them in the page's language.
 *
 * Request format from the Muse docs: multipart with a JSON "request" part (no filename) and an
 * "audio" part; Authorization: Bearer <key>; model muse-voice-transcribe-1.0.
 *
 * It spends money, so it is guarded (lib/voice-guard.ts): an off switch, this site's pages only, the Vercel firewall
 * rule `voice-transcribe` (10 a minute per visitor, set in the dashboard), and a daily cap.
 */

import { checkRateLimit } from "@vercel/firewall";
import { clientKey, DailyCap, dailyCapFrom, sameSite, voiceDisabled, WindowLimit } from "@/lib/voice-guard";

const MODEL = "muse-voice-transcribe-1.0";
const MAX_BYTES = 1_500_000; // about 30s of 24 kHz mono; the recorder stops at 15s
const ON_VERCEL = process.env.VERCEL === "1";
const fallbackLimit = new WindowLimit(5, 60_000); // if the firewall rule can't be checked
const dailyCap = new DailyCap(dailyCapFrom(process.env));

/** The Vercel firewall rule decides when it can; otherwise this instance's own count does. */
async function rateLimited(request: Request): Promise<boolean> {
  if (ON_VERCEL) {
    try {
      const { rateLimited, error } = await checkRateLimit("voice-transcribe", { request, timeout: 1_500 });
      if (!error) return rateLimited;
      if (error === "blocked") return true;
      // "not-found": the rule isn't set up in the dashboard yet; fall through to the local count
    } catch {
      // the firewall couldn't be asked: fall through rather than refuse everyone
    }
  }
  return fallbackLimit.over(clientKey(request.headers, ON_VERCEL));
}

// The documented host. META_MUSE_BASE_URL in .env points at a different service, which doesn't
// serve speech-to-text, so it isn't used here.
const ENDPOINT = "https://api.meta.ai/v1/asr/transcribe";

/** multipart/form-data built by hand: the JSON part must carry its content type and no filename. */
function multipart(audio: ArrayBuffer) {
  const boundary = `----recall${crypto.randomUUID()}`;
  const enc = new TextEncoder();
  const head = (headers: string) => enc.encode(`--${boundary}\r\n${headers}\r\n\r\n`);
  const json = JSON.stringify({ model: MODEL, audioEncoding: "WAV", mode: "PUSH_TO_TALK" });
  const parts = [
    head('Content-Disposition: form-data; name="request"\r\nContent-Type: application/json'),
    enc.encode(`${json}\r\n`),
    head('Content-Disposition: form-data; name="audio"; filename="question.wav"\r\nContent-Type: audio/wav'),
    new Uint8Array(audio),
    enc.encode(`\r\n--${boundary}--\r\n`),
  ];
  return { body: new Blob(parts), contentType: `multipart/form-data; boundary=${boundary}` };
}

/** Response (checked 2026-10-29): { sessionId, transcript, audioDurationMs, turns }. */
function readTranscript(data: unknown): string {
  const transcript = data && typeof data === "object" ? (data as { transcript?: unknown }).transcript : undefined;
  // Muse can end a question with "?." — tidy that for display
  return typeof transcript === "string" ? transcript.replace(/([?!])\.$/, "$1") : "";
}

export async function POST(request: Request) {
  if (voiceDisabled(process.env)) return Response.json({ error: "disabled" }, { status: 503 });
  const key = process.env.META_MUSE_API_KEY;
  if (!key) return Response.json({ error: "not_configured" }, { status: 503 });
  if (!sameSite(request.headers)) return Response.json({ error: "forbidden" }, { status: 403 });

  if (!request.headers.get("content-type")?.startsWith("audio/wav")) {
    return Response.json({ error: "wrong_format" }, { status: 415 });
  }
  // refuse by the declared size before reading anything into memory
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (declared > MAX_BYTES) return Response.json({ error: "too_long" }, { status: 413 });

  if (await rateLimited(request)) return Response.json({ error: "rate_limited" }, { status: 429 });
  if (dailyCap.reached()) return Response.json({ error: "daily_limit" }, { status: 429 });

  const audio = await request.arrayBuffer();
  if (audio.byteLength > MAX_BYTES) return Response.json({ error: "too_long" }, { status: 413 });
  if (audio.byteLength < 2_000) return Response.json({ error: "too_short" }, { status: 400 });

  const { body, contentType } = multipart(audio);
  let res: Response;
  try {
    res = await fetch(ENDPOINT, {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, Accept: "application/json", "Content-Type": contentType },
      body,
      signal: AbortSignal.timeout(20_000),
    });
  } catch {
    return Response.json({ error: "unreachable" }, { status: 502 });
  }
  if (!res.ok) {
    // log the status only; the body may echo request details
    console.error(`[voice] Muse transcribe failed: HTTP ${res.status}`);
    return Response.json({ error: "failed" }, { status: 502 });
  }

  const transcript = readTranscript(await res.json().catch(() => null)).trim();
  return Response.json({ transcript });
}
