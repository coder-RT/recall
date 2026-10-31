import { expect, test, type Page } from "@playwright/test";
import { en } from "../i18n/dictionaries/en";
import { open, prepare } from "./helpers";

/**
 * Usability: the site's tasks done the way many blind and low-vision visitors do them: keyboard only, at large
 * text, on a phone-sized screen. Each keyboard task counts key presses and must finish within its budget.
 */

/** Presses Tab until `target` has focus; returns how many presses it took (fails after `max`). */
async function tabTo(page: Page, isTarget: () => Promise<boolean>, max: number): Promise<number> {
  for (let presses = 1; presses <= max; presses++) {
    await page.keyboard.press("Tab");
    if (await isTarget()) return presses;
  }
  throw new Error(`not reached within ${max} Tab presses`);
}

const focusedName = (page: Page) =>
  page.evaluate(() => (document.activeElement?.textContent ?? "").replace(/\s+/g, " ").trim());

// budgets are today's measured paths (the nav comes first on a wide screen), kept as a guard against them growing
test("keyboard only: from the top to a spoken answer in the Ask card, in at most 15 presses", async ({ page }) => {
  await prepare(page);
  await open(page, "/");
  const wallet = en.ask.questions[2];
  let presses = await tabTo(page, async () => (await focusedName(page)) === en.nav.tryDemo, 10);
  await page.keyboard.press("Enter");
  presses += 1;
  presses += await tabTo(page, async () => (await focusedName(page)).includes(wallet.q), 3);
  await page.keyboard.press("Enter");
  presses += 1;
  await expect(page.locator("#ask").getByText(wallet.a)).toBeVisible();
  expect(presses).toBeLessThanOrEqual(15);
});

test("keyboard only: from the top to the privacy page, in at most 9 presses", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 }); // the section links show from the large breakpoint
  await prepare(page);
  await open(page, "/");
  const presses = await tabTo(page, async () => (await focusedName(page)) === en.nav.privacy, 8);
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/\/privacy$/);
  await expect(page.getByRole("heading", { level: 1, name: en.privacy.heading })).toBeVisible();
  expect(presses + 1).toBeLessThanOrEqual(9);
});

for (const path of ["/", "/privacy"]) {
  test(`${path}: on a phone at 200% text, nothing scrolls sideways and the main heading is readable`, async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await prepare(page, { a11y: { textScale: 2 } });
    await open(page, path);
    await expect.poll(() => page.evaluate(() => document.documentElement.style.fontSize)).toBe("200%");
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true);
    await expect(page.getByRole("heading", { level: 1 }).first()).toBeVisible();
  });
}

test("the privacy page reads in order: what is kept, what is sent, never, controls, this website", async ({ page }) => {
  await prepare(page);
  await open(page, "/privacy");
  const headings = await page.getByRole("heading", { level: 2 }).allTextContents();
  expect(headings).toEqual([
    en.privacy.keptTitle,
    en.privacy.sentTitle,
    en.privacy.neverTitle,
    en.privacy.controlsTitle,
    en.privacy.siteTitle,
  ]);
});
