import { expect, test } from "@playwright/test";
import { captionTimes, STORY_SECONDS } from "../content/story";
import { format } from "../i18n";
import { en } from "../i18n/dictionaries/en";
import { brailleCells, matrixDots, wordWidth } from "../lib/braille";
import { oncePerPass } from "../lib/once-per-pass";
import { PIXEL_GRID, PIXEL_ICON_NAMES, pixelRects } from "../lib/pixel-icons";
import { contactDisabled, contactMessage, looksAutomated, MIN_FILL_MS, subjectFor } from "../lib/contact";
import { clientKey, DailyCap, dailyCapFrom, sameSite, voiceDisabled, WindowLimit } from "../lib/voice-guard";

/** Pure logic and content checks: no browser needed. */

test.describe("braille", () => {
  test("RECALL in Braille is the capital-word sign then the six letters", () => {
    const cells = brailleCells("RECALL", { capsWord: true });
    expect(cells.map((c) => c.char).join("")).toBe("⠠⠠⠗⠑⠉⠁⠇⠇");
    expect(cells.filter((c) => c.indicator)).toHaveLength(2);
  });

  test("the dot-matrix wordmark has dots for every letter and fits its width", () => {
    const dots = matrixDots("RECALL");
    expect(new Set(dots.map((d) => d.letter)).size).toBe(6);
    expect(Math.max(...dots.map((d) => d.x))).toBeLessThan(wordWidth("RECALL"));
  });
});

test.describe("pixel icons", () => {
  for (const name of PIXEL_ICON_NAMES) {
    test(`${name} draws inside its grid, with an outline`, () => {
      const rects = pixelRects(name);
      expect(rects.length).toBeGreaterThan(10);
      for (const r of rects) {
        expect(r.x).toBeGreaterThanOrEqual(0);
        expect(r.x + r.w).toBeLessThanOrEqual(PIXEL_GRID);
        expect(r.y).toBeGreaterThanOrEqual(0);
        expect(r.y).toBeLessThan(PIXEL_GRID);
      }
      expect(rects.some((r) => r.fill === "#1c1e21")).toBe(true);
    });
  }
});

test("oncePerPass fires once, re-arms, and respects its cooldown", async () => {
  const pass = oncePerPass({ cooldown: 80 });
  let fired = 0;
  pass.fire(() => fired++);
  pass.fire(() => fired++);
  expect(fired).toBe(1);
  pass.rearm();
  pass.fire(() => fired++); // still inside the cooldown
  expect(fired).toBe(1);
  await new Promise((r) => setTimeout(r, 100));
  pass.fire(() => fired++);
  expect(fired).toBe(2);
});

test("format fills placeholders and leaves unknown ones alone", () => {
  expect(format("Step {n} of {total}", { n: 2, total: 3 })).toBe("Step 2 of 3");
  expect(format("{a} {b}", { a: "x" })).toBe("x {b}");
});

test("every dictionary entry has text", () => {
  const empty: string[] = [];
  const walk = (value: unknown, path: string) => {
    if (typeof value === "string") {
      if (!value.trim()) empty.push(path);
    } else if (value && typeof value === "object") {
      for (const [k, v] of Object.entries(value)) walk(v, `${path}.${k}`);
    }
  };
  walk(en, "en");
  expect(empty).toEqual([]);
});

test.describe("story script", () => {
  test("lines are in order, inside the 12 seconds, and far enough apart", () => {
    const times = captionTimes.map((c) => c.at);
    expect(times).toEqual([...times].sort((a, b) => a - b));
    expect(Math.max(...times)).toBeLessThan(STORY_SECONDS);
    times.slice(1).forEach((t, i) => expect(t - times[i], `gap before line ${i + 2}`).toBeGreaterThanOrEqual(0.6));
  });
});

test.describe("voice route guards", () => {
  test("the off switch", () => {
    expect(voiceDisabled({ VOICE_DEMO: "off" })).toBe(true);
    expect(voiceDisabled({ VOICE_DEMO: "OFF" })).toBe(true);
    expect(voiceDisabled({})).toBe(false);
    expect(voiceDisabled({ VOICE_DEMO: "on" })).toBe(false);
  });

  test("only this site's own pages may call it", () => {
    const h = (o: Record<string, string>) => new Headers(o);
    expect(sameSite(h({ origin: "https://recall.example", host: "recall.example" }))).toBe(true);
    expect(sameSite(h({ origin: "https://evil.example", host: "recall.example" }))).toBe(false);
    expect(sameSite(h({ host: "recall.example" }))).toBe(false); // scripts often send no Origin
    expect(sameSite(h({ origin: "not a url", host: "recall.example" }))).toBe(false);
  });

  test("the client is never taken from X-Forwarded-For, which the client can write", () => {
    const spoofed = new Headers({ "x-forwarded-for": "1.2.3.4", "x-real-ip": "203.0.113.9" });
    expect(clientKey(spoofed, true)).toBe("203.0.113.9");
    expect(clientKey(spoofed, false)).toBe("local");
    expect(clientKey(new Headers({ "x-forwarded-for": "1.2.3.4" }), true)).toBe("local");
  });

  test("the fallback limit counts per client per window", () => {
    const limit = new WindowLimit(2, 60_000);
    expect([limit.over("a", 0), limit.over("a", 1), limit.over("a", 2)]).toEqual([false, false, true]);
    expect(limit.over("b", 3)).toBe(false); // someone else
    expect(limit.over("a", 61_000)).toBe(false); // a minute later
  });

  test("the fallback limit forgets the longest-quiet visitors first, never everyone", () => {
    const limit = new WindowLimit(1, 60_000, 3);
    for (const [i, who] of ["a", "b", "c", "d"].entries()) limit.over(who, i);
    expect(limit.size).toBe(3);
    expect(limit.over("d", 10)).toBe(true); // d is still counted: the oldest, a, was dropped instead
    expect(limit.over("a", 11)).toBe(false);
  });

  test("the daily cap stops at the cap and starts again the next UTC day", () => {
    const cap = new DailyCap(2);
    const d1 = new Date("2026-11-01T10:00:00Z");
    expect([cap.reached(d1), cap.reached(d1), cap.reached(d1)]).toEqual([false, false, true]);
    expect(cap.reached(new Date("2026-11-02T00:00:01Z"))).toBe(false);
    expect(dailyCapFrom({ VOICE_DAILY_CAP: "50" })).toBe(50);
    expect(dailyCapFrom({ VOICE_DAILY_CAP: "nonsense" })).toBe(300);
    expect(dailyCapFrom({})).toBe(300);
  });

  test("the contact form reads its own daily cap", () => {
    expect(dailyCapFrom({ CONTACT_DAILY_CAP: "5" }, "CONTACT_DAILY_CAP", 20)).toBe(5);
    expect(dailyCapFrom({ VOICE_DAILY_CAP: "50" }, "CONTACT_DAILY_CAP", 20)).toBe(20);
  });
});

test.describe("contact form rules", () => {
  const msg = { name: " Ada ", email: "ada@example.com", message: "Hello there, Rachit.", startedAt: 1_000 };

  test("accepts a proper message and trims it", () => {
    const parsed = contactMessage.parse(msg);
    expect(parsed.name).toBe("Ada");
    expect(parsed.website).toBe("");
  });

  test("rejects bad emails, short messages and very long names", () => {
    expect(contactMessage.safeParse({ ...msg, email: "nope" }).success).toBe(false);
    expect(contactMessage.safeParse({ ...msg, message: "hi" }).success).toBe(false);
    expect(contactMessage.safeParse({ ...msg, name: "x".repeat(81) }).success).toBe(false);
    expect(contactMessage.safeParse({ ...msg, startedAt: "soon" }).success).toBe(false);
  });

  test("a filled honeypot or a too-fast send looks automated", () => {
    const parsed = contactMessage.parse(msg);
    expect(looksAutomated(parsed, 1_000 + MIN_FILL_MS)).toBe(false);
    expect(looksAutomated(parsed, 1_000 + MIN_FILL_MS - 1)).toBe(true);
    expect(looksAutomated({ ...parsed, website: "x" }, 1_000_000)).toBe(true);
  });

  test("the subject can't carry extra lines, and CONTACT_FORM=off turns it off", () => {
    expect(subjectFor("Ada\r\nBcc: x@example.com")).toBe("Recall site: Ada Bcc: x@example.com");
    expect(contactDisabled({ CONTACT_FORM: "OFF" })).toBe(true);
    expect(contactDisabled({})).toBe(false);
  });
});
