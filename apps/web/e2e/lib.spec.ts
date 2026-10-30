import { expect, test } from "@playwright/test";
import { captionTimes, STORY_SECONDS } from "../content/story";
import { format } from "../i18n";
import { en } from "../i18n/dictionaries/en";
import { brailleCells, matrixDots, wordWidth } from "../lib/braille";
import { oncePerPass } from "../lib/once-per-pass";
import { PIXEL_GRID, PIXEL_ICON_NAMES, pixelRects } from "../lib/pixel-icons";

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
