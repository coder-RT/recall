/**
 * Guards for the voice demo route, the only route on the site that spends money (Muse Voice Transcribe on the Meta
 * Model API); the contact form reuses them. Kept apart from the routes so each rule is tested on its own
 * (e2e/lib.spec.ts).
 *
 * The hard stops are the Vercel firewall rule (`voice-transcribe`, checked with @vercel/firewall in production) and
 * the off switch. The in-memory limits are a fallback: each serverless instance counts on its own, so across
 * instances they are approximate.
 */

/** VOICE_DEMO=off turns the voice demo off at once, without a deploy. */
export function voiceDisabled(env: Record<string, string | undefined>): boolean {
  return (env.VOICE_DEMO ?? "").toLowerCase() === "off";
}

/** Only this site's own pages may call the route: a browser always sends Origin on a POST. */
export function sameSite(headers: Headers): boolean {
  const origin = headers.get("origin");
  const host = headers.get("x-forwarded-host") ?? headers.get("host");
  if (!origin || !host) return false;
  try {
    return new URL(origin).host === host;
  } catch {
    return false;
  }
}

/**
 * Who is asking, for the fallback limit. On Vercel `x-real-ip` is the client's address as Vercel saw it (correct
 * once no proxy sits in front); X-Forwarded-For is never used, because a client can write its first entry.
 */
export function clientKey(headers: Headers, onVercel: boolean): string {
  return (onVercel && headers.get("x-real-ip")) || "local";
}

/** Requests per window per client, in this instance's memory. */
export class WindowLimit {
  private readonly hits = new Map<string, number[]>();
  constructor(
    private readonly limit: number,
    private readonly windowMs: number,
  ) {}

  /** Counts this request; true when it is over the limit. */
  over(key: string, now = Date.now()): boolean {
    const recent = (this.hits.get(key) ?? []).filter((t) => now - t < this.windowMs);
    recent.push(now);
    this.hits.set(key, recent);
    if (this.hits.size > 5000) this.hits.clear(); // keep memory bounded
    return recent.length > this.limit;
  }
}

/** Requests per UTC day, for the whole instance: a ceiling on what a bot can spend. */
export class DailyCap {
  private day = "";
  private count = 0;
  constructor(private readonly cap: number) {}

  /** Counts this request; true when today's cap is already used up. */
  reached(now = new Date()): boolean {
    const day = now.toISOString().slice(0, 10);
    if (day !== this.day) {
      this.day = day;
      this.count = 0;
    }
    if (this.count >= this.cap) return true;
    this.count += 1;
    return false;
  }
}

/** VOICE_DAILY_CAP, or 300 a day. The contact form passes its own variable and default. */
export function dailyCapFrom(env: Record<string, string | undefined>, name = "VOICE_DAILY_CAP", fallback = 300): number {
  const n = Number(env[name]);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback;
}
