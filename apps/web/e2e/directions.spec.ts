import { expect, test, type Page } from "@playwright/test";
import { en } from "../i18n/dictionaries/en";
import { open, expectNoReactions, expectReactions, prepare, scrollPin } from "./helpers";

/** Clock-face directions: pinned on desktop; the steps light up and the clock hand turns as you scroll. */

const activeCount = (page: Page) =>
  page.locator("#directions [data-direction]").evaluateAll((els) => els.filter((el) => (el as HTMLElement).dataset.active === "true").length);

/** The clock hand's angle in degrees, 0–360 (0 = 12 o'clock). */
const handAngle = (page: Page) =>
  page.locator("#directions [data-hand]").evaluate((el) => {
    const m = (el as SVGGraphicsElement).transform.baseVal.consolidate()?.matrix;
    return m ? (((Math.atan2(m.b, m.a) * 180) / Math.PI) + 360) % 360 : 0;
  });

test.beforeEach(async ({ page }) => prepare(page));

test("lists every step of the route", async ({ page }) => {
  await open(page, "/");
  const steps = page.locator("#directions [data-direction]");
  await expect(steps).toHaveCount(en.directions.steps.length);
  for (const [i, s] of en.directions.steps.entries()) {
    await expect(steps.nth(i)).toContainText(s.text);
    await expect(steps.nth(i)).toContainText(s.detail);
  }
  await expect(page.getByText(en.directions.note)).toBeAttached();
});

test("steps light up one by one as you scroll through the scene", async ({ page }) => {
  await open(page, "/");
  for (const [progress, expected] of [
    [0.05, 1],
    [0.3, 2],
    [0.6, 3],
    [0.95, 4],
  ] as const) {
    await scrollPin(page, "directions", progress);
    await page.waitForTimeout(400);
    expect(await activeCount(page), `at ${progress}`).toBe(expected);
  }
});

test("the clock hand points the way for the current step", async ({ page }) => {
  await open(page, "/");
  await scrollPin(page, "directions", 0.45); // after "Turn to 2 o'clock" and "Walk 4 steps"
  await page.waitForTimeout(1_200);
  expect(Math.abs((await handAngle(page)) - 60)).toBeLessThan(4);
  await scrollPin(page, "directions", 1);
  await page.waitForTimeout(1_200);
  const end = await handAngle(page);
  expect(Math.min(end, 360 - end)).toBeLessThan(4); // 12 o'clock
});

test("arriving at the keys celebrates, and clears once you scroll on", async ({ page }) => {
  await open(page, "/");
  await scrollPin(page, "directions", 0.6);
  await page.waitForTimeout(500);
  await scrollPin(page, "directions", 0.99);
  await expectReactions(page);
  await page.locator("#faq").scrollIntoViewIfNeeded();
  await expectNoReactions(page);
});

test("with reduced motion the whole route is shown", async ({ browser }) => {
  const context = await browser.newContext({ reducedMotion: "reduce" });
  const page = await context.newPage();
  await prepare(page);
  await open(page, "/#directions");
  expect(await activeCount(page)).toBe(en.directions.steps.length);
  await expect(page.locator("#directions [data-goal]")).toBeVisible();
  await context.close();
});
