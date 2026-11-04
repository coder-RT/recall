import fs from "node:fs";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";
import { en } from "../i18n/dictionaries/en";
import { open, prepare } from "./helpers";

/**
 * /demo: the no-keys demo. Recorded answers from a real run (samples/replay/flat) and the planner's walks, read from
 * public/real-scan/flat/walks.json (`make demo-walks`). Nothing here calls a model or the API. The real screen
 * recordings live only on the author's computer (public/local-video, gitignored), so these tests never use them: a
 * made-up test pattern (fixtures/test-clip.mp4) stands in when the recording path is tested.
 */

const PAGE = "/demo";
const t = en.app.demo;
type Option = { label: string; steps: { say: string }[]; arrive: string; mode: string; path: number[][] };
type Item = Partial<Option> & { question: string; answer: string; model: string; choices?: Option[] };
const walks: { recorded_at: string; walks: Item[] } = JSON.parse(fs.readFileSync(path.join(__dirname, "../public/real-scan/flat/walks.json"), "utf8"));
const recorded = JSON.parse(fs.readFileSync(path.join(__dirname, "../../../samples/replay/flat/meta.json"), "utf8"));
const byQuestion = (q: string) => walks.walks.find((w) => w.question === q)!;
const keys = byQuestion("Where are my keys?");
const played = (page: Page) => page.waitForFunction(() => document.querySelector<HTMLElement>("[data-walk-demo]")?.dataset.played === "true", null, { timeout: 15_000 });

/** No clips: what the hosted site shows (this computer's own clips, if any, are hidden from the tests). */
async function noClips(page: Page) {
  await page.route(/\/(local|demo)-video\//, (route) => route.fulfill({ status: 404, body: "" }));
}

test.beforeEach(async ({ page }) => {
  await prepare(page);
  await noClips(page);
});

test("the walks are the recorded run's answers, labelled as replayed", () => {
  expect(walks.recorded_at).toBe(recorded.recorded_at);
  const answers = Object.fromEntries(recorded.answers.map((a: { question: string; answer: string }) => [a.question, a.answer]));
  for (const w of walks.walks) {
    expect(w.answer, w.question).toBe(answers[w.question]);
    expect(w.model).toMatch(/^replay:.*\(recorded\)$/);
  }
});

test("says it is recorded, and opens on the watch and its walk", async ({ page }) => {
  await open(page, PAGE);
  const watch = byQuestion("Where is my watch?");
  await expect(page.locator("[data-recorded-badge]")).toHaveText(t.badge);
  await expect(page.locator("[data-recorded]")).toContainText("Recorded output, not live");
  await expect(page.locator("[data-question]:checked").locator("..")).toContainText("Where is my watch?");
  await expect(page.locator("[data-answer-text]")).toHaveText(watch.answer);
  await expect(page.locator("[data-walk-step]")).toHaveCount(watch.steps!.length);
  await expect(page.locator("[data-walk-arrive]")).toContainText(watch.arrive!);
  await expect(page.locator("[data-simulated-phone]")).toBeVisible();
  await expect(page.getByText(t.phone.simulated)).toBeVisible();
  // no recordings, as on the hosted site: no badge, no shortcut, no photo of the room
  await expect(page.locator("[data-recorded-chip], [data-show-recording], [data-ar-photo]")).toHaveCount(0);
});

test("every question: a walk, a choice of walks, or an honest 'not seen'", async ({ page }) => {
  test.setTimeout(180_000); // 13 questions, each walk played to the end
  await open(page, PAGE);
  for (const [i, w] of walks.walks.entries()) {
    await page.locator("[data-question]").nth(i).check({ force: true });
    await expect(page.locator("[data-answer-text]")).toHaveText(w.answer);
    if (!w.steps && !w.choices) {
      await expect(page.locator("[data-walk-note]"), w.question).toHaveText(t.notSeen);
      await expect(page.locator("[data-walk-step]")).toHaveCount(0);
      continue;
    }
    const options = w.choices ?? [w as Option];
    await expect(page.locator("[data-choice]"), w.question).toHaveCount(w.choices ? options.length : 0);
    for (const [j, o] of options.entries()) {
      if (w.choices) await page.locator("[data-choice]").nth(j).check();
      const steps = page.locator("[data-walk-step]");
      await expect(steps, `${w.question} #${j}`).toHaveCount(o.steps.length);
      await expect(steps.first()).toContainText(o.steps[0].say);
      if (o.mode === "route") await expect(page.locator("[data-walk-arrive]")).toContainText(o.arrive);
      else await expect(page.locator("[data-walk-note]")).toHaveText(t.noPath); // no clear path: landmark directions
    }
    await played(page);
    // once the walk has played, every step is fully shown
    for (const el of await page.locator("[data-walk-step]").all()) await expect(el).toHaveCSS("opacity", "1");
  }
});

test("the phone speaks the step the route has reached, and ends 'there'", async ({ page }) => {
  await open(page, PAGE);
  await page.getByText("Where is my bag?", { exact: true }).click();
  const phone = page.locator("[data-simulated-phone]");
  await expect.poll(() => phone.getAttribute("data-step"), { timeout: 10_000 }).toBe("0");
  const bag = byQuestion("Where is my bag?");
  await expect.poll(() => phone.getAttribute("data-step"), { timeout: 15_000 }).toBe(String(bag.steps!.length));
  await expect(phone).toContainText(bag.arrive!);
});

test("on a wide screen, every point and the architect's room side by side", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 });
  await open(page, PAGE);
  await expect(page.locator("[data-viewer-pair] canvas")).toHaveCount(2, { timeout: 20_000 });
  await expect(page.locator("[data-viewer-single]")).toBeHidden();
  await page.setViewportSize({ width: 1024, height: 900 });
  await expect(page.locator("[data-viewer-pair]")).toBeHidden();
  await expect(page.locator("[data-viewer-single]")).toBeVisible();
});

test("with motion reduced, every step is there at once and the phone shows the end", async ({ browser }) => {
  const context = await browser.newContext({ reducedMotion: "reduce" });
  const page = await context.newPage();
  await prepare(page);
  await noClips(page);
  await open(page, PAGE);
  await page.getByText("Where is my wallet?", { exact: true }).click();
  for (const el of await page.locator("[data-walk-step]").all()) await expect(el).toHaveCSS("opacity", "1");
  const wallet = byQuestion("Where is my wallet?");
  await expect(page.locator("[data-simulated-phone]")).toHaveAttribute("data-step", String(wallet.steps!.length));
  await context.close();
});

test("reads without JavaScript: the answer and the steps are in the page", async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto(PAGE);
  const watch = byQuestion("Where is my watch?");
  await expect(page.locator("[data-answer-text]")).toHaveText(watch.answer);
  await expect(page.locator("[data-walk-step]")).toHaveCount(watch.steps!.length);
  await context.close();
});

test("a real recording plays on the phone for its thing, with captions, when this computer has one", async ({ page }) => {
  await page.unrouteAll();
  const clip = fs.readFileSync(path.join(__dirname, "fixtures/test-clip.mp4"));
  const clips = {
    source: "local",
    clips: [{ id: "watch", kind: "find", thing: "watch", title: "Finding the watch", recorded: "2026-11-02", walk: [0.5, 2.5], file: "watch.mp4", seconds: 3, captions: [[0, "First line"], [1, "Second line"]] }],
  };
  await page.route("**/local-video/clips.json", (route) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(clips) }));
  await page.route("**/local-video/watch.mp4", (route) => route.fulfill({ status: 200, contentType: "video/mp4", body: clip }));
  await page.route("**/demo-video/**", (route) => route.fulfill({ status: 404, body: "" }));
  await open(page, PAGE);
  // the watch question says it has a real recording, and the page opens on it, so it needs no shortcut
  await expect(page.locator("[data-recorded-chip]")).toHaveCount(1);
  await expect(page.locator("label", { has: page.locator("[data-recorded-chip]") })).toContainText("Where is my watch?");
  await expect(page.locator("[data-answer-text]")).toHaveText(byQuestion("Where is my watch?").answer);
  await expect(page.locator("[data-show-recording]")).toHaveCount(0);
  const phone = page.locator("[data-recorded-phone='watch']");
  await expect(phone).toBeVisible();
  await expect(page.getByText(t.phone.localOnly).first()).toBeVisible();
  // played, not seeked: the test's stand-in clip is served without range requests
  await phone.locator("video").evaluate((v: HTMLVideoElement) => v.play());
  await expect(phone.locator("[data-clip-caption]")).toHaveText("Second line");
  // the simulated screen is one switch away
  await page.getByLabel(t.phone.showSimulated).check();
  await expect(page.locator("[data-simulated-phone]")).toBeVisible();
});

test("the labelled room shows when this computer has that frame, and not on the hosted site", async ({ page }) => {
  await page.unrouteAll();
  const clips = { source: "local", clips: [{ id: "ar-labels", kind: "image", title: "The room with its labels", recorded: "2026-11-04", file: "ar-labels.jpg", seconds: 0, captions: [] }] };
  await page.route("**/local-video/clips.json", (route) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(clips) }));
  await page.route("**/local-video/ar-labels.jpg", (route) => route.fulfill({ status: 200, contentType: "image/svg+xml", body: "<svg xmlns='http://www.w3.org/2000/svg' width='8' height='8'/>" }));
  await page.route("**/demo-video/**", (route) => route.fulfill({ status: 404, body: "" }));
  await open(page, PAGE);
  const section = page.locator("[data-ar-photo]");
  await expect(section).toContainText(t.arPhoto.title);
  await expect(section.locator("img")).toHaveAttribute("alt", "The room with its labels");
  await expect(section).toContainText(t.phone.localOnly);
});

test("has no WCAG 2.2 AA violations", async ({ page }) => {
  await open(page, PAGE);
  // measured once the walk has played (mid-fade, words are lighter on purpose)
  await played(page);
  const results = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa", "wcag22aa"]).analyze();
  expect(results.violations).toEqual([]);
});

test("says how the iPhone works in AR, and that it listens only on your turn", async ({ page }) => {
  await open(page, PAGE);
  const ar = page.locator("[data-ar-mode]");
  await expect(ar.getByRole("heading", { name: en.app.arMode.title })).toBeVisible();
  await expect(ar.getByRole("listitem")).toHaveCount(en.app.arMode.steps.length);
  await expect(page.locator("[data-when-it-listens]")).toContainText("never in the background");
  await expect(page.locator("[data-when-it-listens]")).toContainText("isn't a live stream");
});

for (const path of ["/", PAGE, "/homes/flat/viewer"]) {
  test(`${path}: Back to top appears after scrolling, and returns view and focus`, async ({ page }) => {
    await open(page, path);
    const button = page.locator("[data-back-to-top]");
    await expect(button).toHaveCount(0);
    await page.evaluate(() => window.scrollTo(0, 2000));
    await expect(button).toBeVisible();
    await button.evaluate((b: HTMLElement) => b.click());
    await expect.poll(() => page.evaluate(() => window.scrollY), { timeout: 8_000 }).toBeLessThan(5);
    expect(await page.evaluate(() => document.activeElement?.tagName)).toBe("H1");
  });
}

test("the viewer shows what was measured in real use, says what it isn't, and reads the room aloud", async ({ page }) => {
  await open(page, "/homes/flat/viewer");
  const stats = page.locator("[data-field-stats]");
  for (const item of en.app.fieldStats.items) await expect(stats).toContainText(item.value);
  await expect(stats).toContainText("not a study");
  await expect(page.locator("[data-ar-mode]")).toBeVisible();
  await expect(page.locator("[data-hear-room]")).toHaveText(en.app.hearRoom.hear);
});
