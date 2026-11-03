import fs from "node:fs";
import path from "node:path";
import { expect, test } from "@playwright/test";

/**
 * /film: the demo film's fly-through of the real scan (not linked from the site, not indexed). Time comes from
 * window.__film.seek(t), never the clock, so a capture can step through it frame by frame.
 */

const walks = JSON.parse(fs.readFileSync(path.join(__dirname, "../public/real-scan/flat/walks.json"), "utf8"));
const keys = walks.walks.find((w: { question: string }) => w.question === "Where are my keys?");

test.beforeEach(async ({ page }) => page.addInitScript(() => localStorage.setItem("recall:notice-seen", "1")));

test("is not indexed and seeks to any moment", async ({ page }) => {
  await page.goto("/film?t=0");
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", /noindex/);
  await page.waitForSelector("html[data-film-ready]", { timeout: 60_000 });
  await expect(page.locator("[data-film] canvas")).toHaveCount(1);
  const duration = await page.evaluate(() => (window as unknown as { __film: { duration: number } }).__film.duration);
  expect(duration).toBeGreaterThan(5);
  // nothing labelled at the start; the pin, a step and the measured number later
  await expect(page.locator("[data-pin]")).toHaveCSS("opacity", "0");
  await page.evaluate(() => (window as unknown as { __film: { seek: (t: number) => Promise<void> } }).__film.seek(9));
  await expect(page.locator("[data-pin]")).toHaveCSS("opacity", "1");
  await expect(page.locator("[data-step][style*='opacity: 1']")).toHaveCount(1);
  await page.evaluate((d) => (window as unknown as { __film: { seek: (t: number) => Promise<void> } }).__film.seek(d), duration);
  await expect(page.locator("[data-proof]")).toHaveCSS("opacity", "1");
});

test("labels the real walk: the keys' place and the planner's own steps", async ({ page }) => {
  await page.goto("/film?t=12");
  await page.waitForSelector("html[data-film-ready]", { timeout: 60_000 });
  await expect(page.locator("[data-pin]")).toContainText("keys · near the desk · knee height");
  const steps = await page.locator("[data-step]").allTextContents();
  expect(steps).toEqual(keys.steps.map((s: { say: string }) => s.say.replace(/\.$/, "")));
});
