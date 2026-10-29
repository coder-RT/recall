/**
 * Speech-to-text for the landing demo's "Ask by voice". Forwards a short WAV to Meta Muse Voice
 * Transcribe so META_MUSE_API_KEY never reaches the browser. Recall doesn't store the audio.
 * Errors are codes (see `ask.errors` in i18n/dictionaries); the card shows them in the page's language.
 *
 * Request format from the Muse docs: multipart with a JSON "request" part (no filename) and an
 * "audio" part; Authorization: Bearer <key>; model muse-voice-transcribe-1.0.
 */

const MODEL = "muse-voice-transcribe-1.0";
const MAX_BYTES = 1_500_000; // about 30s of 24 kHz mono; the recorder stops at 15s
const LIMIT = 10; // requests per minute per address, to protect the key
const WINDOW_MS = 60_000;

const recent = new Map<string, number[]>();

function rateLimited(address: string) {
  const now = Date.now();
  const hits = (recent.get(address) ?? []).filter((t) => now - t < WINDOW_MS);
  hits.push(now);
  recent.set(address, hits);
  if (recent.size > 5000) recent.clear(); // keep memory bounded
  return hits.length > LIMIT;
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
  const key = process.env.META_MUSE_API_KEY;
  if (!key) return Response.json({ error: "not_configured" }, { status: 503 });

  if (!request.headers.get("content-type")?.startsWith("audio/wav")) {
    return Response.json({ error: "wrong_format" }, { status: 415 });
  }
  const address = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "local";
  if (rateLimited(address)) return Response.json({ error: "rate_limited" }, { status: 429 });

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
