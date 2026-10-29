import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";
import { en } from "../i18n/dictionaries/en";
import { open, hydrated, prepare, spokenTexts, stubSpeech } from "./helpers";

/** The accessibility menu and its tools, keyboard use, and an automated WCAG 2.2 AA audit. */

const openMenu = async (page: Page) => {
  await page.getByRole("button", { name: en.a11y.button }).click();
  const panel = page.getByRole("dialog", { name: en.a11y.title });
  await expect(panel).toBeVisible();
  return panel;
};

test.beforeEach(async ({ page }) => prepare(page));

test.describe("menu", () => {
  test("opens from the nav, closes with Escape and returns focus", async ({ page }) => {
    await open(page, "/");
    const button = page.getByRole("button", { name: en.a11y.button });
    await expect(button).toHaveAttribute("aria-expanded", "false");
    await openMenu(page);
    await expect(button).toHaveAttribute("aria-expanded", "true");
    await page.keyboard.press("Escape");
    await expect(page.getByRole("dialog", { name: en.a11y.title })).toBeHidden();
    await expect(button).toBeFocused();
  });

  test("Alt+A toggles it from anywhere", async ({ page }) => {
    await open(page, "/");
    await hydrated(page);
    await page.keyboard.press("Alt+KeyA");
    await expect(page.getByRole("dialog", { name: en.a11y.title })).toBeVisible();
    await page.keyboard.press("Alt+KeyA");
    await expect(page.getByRole("dialog", { name: en.a11y.title })).toBeHidden();
  });
});

test.describe("tools", () => {
  test("text size scales the whole page and is remembered", async ({ page }) => {
    await open(page, "/");
    const panel = await openMenu(page);
    await panel.getByText("200%", { exact: true }).click();
    await expect.poll(() => page.evaluate(() => document.documentElement.style.fontSize)).toBe("200%");
    await page.reload();
    await expect.poll(() => page.evaluate(() => document.documentElement.style.fontSize)).toBe("200%");
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true);
  });

  test("high contrast switches the page to black, white and yellow", async ({ page }) => {
    await open(page, "/");
    const panel = await openMenu(page);
    await panel.getByRole("switch", { name: en.a11y.contrast.label }).click();
    await expect(page.locator("html")).toHaveAttribute("data-contrast", "high");
    await expect.poll(() => page.evaluate(() => getComputedStyle(document.body).backgroundColor)).toBe("rgb(0, 0, 0)");
  });

  test("the magnifier shows the text under the pointer, very large", async ({ page }) => {
    await open(page, "/");
    const panel = await openMenu(page);
    await panel.getByRole("switch", { name: en.a11y.magnifier.label }).click();
    await page.keyboard.press("Escape");
    const target = page.getByText(en.principles.items[0].body);
    await target.scrollIntoViewIfNeeded();
    await target.hover();
    await expect(page.locator("[data-magnifier]")).toHaveText(en.principles.items[0].body);
  });

  test("the magnifying glass follows the mouse", async ({ page }) => {
    await open(page, "/");
    const panel = await openMenu(page);
    await panel.getByRole("switch", { name: en.a11y.lens.label }).click();
    await page.keyboard.press("Escape");
    await page.mouse.move(300, 400);
    await page.mouse.move(320, 420, { steps: 3 });
    const lens = page.locator("[data-lens]");
    await expect.poll(() => lens.evaluate((el) => getComputedStyle(el).opacity)).toBe("1");
    expect(await lens.locator("[inert] > *").count()).toBe(1);
  });

  test("read aloud speaks text you click and controls you focus", async ({ page }) => {
    await stubSpeech(page);
    await open(page, "/");
    const panel = await openMenu(page);
    await panel.getByRole("switch", { name: en.a11y.readAloud.label }).click();
    await page.keyboard.press("Escape");
    const text = page.getByText(en.principles.items[1].body);
    await text.scrollIntoViewIfNeeded();
    await text.click();
    // long text is spoken a sentence at a time
    await expect.poll(async () => (await spokenTexts(page)).join("").replace(/\s+/g, " ")).toContain(en.principles.items[1].body);
    await page.getByRole("link", { name: en.hero.seeHow }).focus();
    await expect.poll(() => spokenTexts(page)).toContain(en.hero.seeHow);
  });

  test("“Read this section” reads the section in the middle of the screen", async ({ page }) => {
    await stubSpeech(page);
    await open(page, "/");
    await hydrated(page);
    // centre the principles section; late re-measuring after load can move it, so re-check
    await expect
      .poll(() =>
        page.locator("#privacy").evaluate((el) => {
          el.scrollIntoView({ block: "center", behavior: "instant" });
          return document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2)?.closest("section")?.id;
        }),
      )
      .toBe("privacy");
    const panel = await openMenu(page);
    // dispatch: Playwright's scroll-into-view would move the page under the sticky nav's panel
    await panel.getByRole("button", { name: en.a11y.readSection }).dispatchEvent("click");
    await expect.poll(async () => (await spokenTexts(page)).join(" ")).toContain(en.principles.items[0].title);
  });

  test("reduce motion is a switch that the whole page follows", async ({ page }) => {
    await open(page, "/");
    const panel = await openMenu(page);
    await panel.getByRole("switch", { name: en.a11y.motion.label }).click();
    await expect(page.locator("html")).toHaveAttribute("data-reduce-motion", "true");
    await expect(page.locator("#feed")).not.toHaveAttribute("data-horizontal", "true");
  });
});

test.describe("WCAG 2.2 AA audit (axe-core)", () => {
  for (const [name, setup] of [
    ["default", async () => {}],
    ["high contrast", async (page: Page) => prepare(page, { a11y: { contrast: true } })],
  ] as const) {
    test(`no violations: ${name}`, async ({ browser }) => {
      // reduced motion: every section in its finished state, so the audit sees stable content
      const context = await browser.newContext({ reducedMotion: "reduce" });
      const page = await context.newPage();
      await prepare(page);
      await setup(page);
      await open(page, "/");
      await hydrated(page);
      const results = await new AxeBuilder({ page })
        .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
        .exclude("[data-reactions]")
        .analyze();
      const summary = results.violations.map((v) => `${v.id} (${v.impact}): ${v.nodes.length} × ${v.nodes[0]?.target.join(" ")}`);
      expect(summary).toEqual([]);
      await context.close();
    });
  }
});
