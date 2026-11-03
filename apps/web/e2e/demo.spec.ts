import fs from "node:fs";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";
import { en } from "../i18n/dictionaries/en";
import { open, prepare } from "./helpers";

/**
 * /demo: the no-keys demo. Recorded answers from a real run (samples/replay/flat) and the planner's walks, read from
 * public/real-scan/flat/walks.json (`make demo-walks`). Nothing here calls a model or the API.
 */

const PAGE = "/demo";
const t = en.app.demo;
const walks = JSON.parse(fs.readFileSync(path.join(__dirname, "../public/real-scan/flat/walks.json"), "utf8"));
const recorded = JSON.parse(fs.readFileSync(path.join(__dirname, "../../../samples/replay/flat/meta.json"), "utf8"));
const keys = walks.walks.find((w: { question: string }) => w.question === "Where are my keys?");

test.beforeEach(async ({ page }) => prepare(page));

test("the walks are the recorded run's answers, labelled as replayed", () => {
  expect(walks.recorded_at).toBe(recorded.recorded_at);
  const answers = Object.fromEntries(recorded.answers.map((a: { question: string; answer: string }) => [a.question, a.answer]));
  for (const w of walks.walks) {
    expect(w.answer, w.question).toBe(answers[w.question]);
    expect(w.model).toMatch(/^replay:.*\(recorded\)$/);
  }
  expect(keys.steps.length).toBeGreaterThan(0);
});

test("says it is recorded, and shows the first answer and its walk", async ({ page }) => {
  await open(page, PAGE);
  await expect(page.locator("[data-recorded-badge]")).toHaveText(t.badge);
  await expect(page.locator("[data-recorded]")).toContainText("Recorded output, not live");
  await expect(page.locator("[data-answer-text]")).toHaveText(keys.answer);
  await expect(page.getByText(keys.answer, { exact: true }).first()).toBeAttached(); // the screen reader's copy
  await expect(page.locator("[data-walk-step]")).toHaveCount(keys.steps.length);
  await expect(page.locator("[data-walk-arrive]")).toContainText(keys.arrive);
});

test("picking a question shows its answer and walks there step by step", async ({ page }) => {
  const bag = walks.walks.find((w: { question: string }) => w.question === "Where is my bag?");
  await open(page, PAGE);
  await page.getByText("Where is my bag?", { exact: true }).click();
  await expect(page.locator("[data-answer-text]")).toHaveText(bag.answer);
  const steps = page.locator("[data-walk-step]");
  await expect(steps).toHaveCount(bag.steps.length);
  await expect(steps.first()).toContainText(bag.steps[0].say);
  // once the walk has played, every step is fully shown
  await expect.poll(() => steps.last().evaluate((el) => getComputedStyle(el).opacity), { timeout: 10_000 }).toBe("1");
});

test("an answer that asks which one, or a thing never seen, has no walk", async ({ page }) => {
  await open(page, PAGE);
  await page.getByText("Where is my laptop?", { exact: true }).click();
  await expect(page.locator("[data-walk-note]")).toHaveText(t.asksWhich);
  await expect(page.locator("[data-walk-step]")).toHaveCount(0);
  await page.getByText("Where is my umbrella?", { exact: true }).click();
  await expect(page.locator("[data-walk-note]")).toHaveText(t.notSeen);
});

test("with motion reduced, every step is there at once", async ({ browser }) => {
  const context = await browser.newContext({ reducedMotion: "reduce" });
  const page = await context.newPage();
  await prepare(page);
  await open(page, PAGE);
  await page.getByText("Where is my wallet?", { exact: true }).click();
  const steps = page.locator("[data-walk-step]");
  for (const el of await steps.all()) await expect(el).toHaveCSS("opacity", "1");
  await context.close();
});

test("reads without JavaScript: the answer and the steps are in the page", async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto(PAGE);
  await expect(page.locator("[data-answer-text]")).toHaveText(keys.answer);
  await expect(page.locator("[data-walk-step]")).toHaveCount(keys.steps.length);
  await context.close();
});

test("has no WCAG 2.2 AA violations", async ({ page }) => {
  await open(page, PAGE);
  // measured once the walk has played (mid-fade, words are lighter on purpose)
  await page.waitForFunction(() => document.querySelector<HTMLElement>("[data-walk-demo]")?.dataset.played === "true");
  const results = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa", "wcag22aa"]).analyze();
  expect(results.violations).toEqual([]);
});
