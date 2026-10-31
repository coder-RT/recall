import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";
import { en } from "../i18n/dictionaries/en";
import { open, prepare } from "./helpers";

/** The privacy page: what is kept, what is sent where, the controls; reachable from the nav, the footer and the FAQ. */

test("says what leaves the Mac, to whom, and what never happens", async ({ page }) => {
  await prepare(page);
  await open(page, "/privacy");
  await expect(page).toHaveTitle(`${en.privacy.title} · Recall`);
  await expect(page.getByRole("heading", { level: 1, name: en.privacy.heading })).toBeVisible();
  for (const row of en.privacy.sent) {
    await expect(page.getByRole("heading", { level: 3, name: row.what })).toBeVisible();
  }
  await expect(page.getByText("Meta Model API: SAM 3.1", { exact: true })).toBeVisible();
  for (const c of en.privacy.controls) await expect(page.getByRole("heading", { name: c.title })).toBeVisible();
});

test("works without JavaScript", async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto("/privacy");
  await expect(page.getByRole("heading", { level: 1, name: en.privacy.heading })).toBeVisible();
  await expect(page.getByText(en.privacy.never[1])).toBeVisible();
  await context.close();
});

test("the nav, footer and FAQ lead to it, and the nav leads back to the landing sections", async ({ page }) => {
  await prepare(page);
  await open(page, "/");
  const nav = page.getByRole("navigation", { name: en.nav.sections });
  await expect(nav.getByRole("link", { name: en.nav.privacy })).toHaveAttribute("href", "/privacy");
  await expect(page.locator("footer").getByRole("link", { name: en.nav.privacy })).toHaveAttribute("href", "/privacy");
  const faq = en.faq.items.find((i) => "href" in i)!;
  await page.getByRole("button", { name: faq.q }).click();
  await page.getByRole("link", { name: "Read the privacy page" }).click();
  await expect(page).toHaveURL(/\/privacy$/);
  await expect(nav.getByRole("link", { name: en.nav.links[0].label })).toHaveAttribute("href", `/${en.nav.links[0].href}`);
});

test("no WCAG 2.2 AA violations", async ({ browser }) => {
  const context = await browser.newContext({ reducedMotion: "reduce" });
  const page = await context.newPage();
  await prepare(page);
  await open(page, "/privacy");
  const results = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"]).analyze();
  expect(results.violations.map((v) => `${v.id}: ${v.nodes[0]?.target.join(" ")}`)).toEqual([]);
  await context.close();
});
