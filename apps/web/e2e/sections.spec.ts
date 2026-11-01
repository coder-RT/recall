import { existsSync } from "node:fs";
import path from "node:path";
import { expect, test, type Page } from "@playwright/test";
import { en } from "../i18n/dictionaries/en";
import { open, prepare, scrollEdgeTo } from "./helpers";

const ROOT = path.resolve(__dirname, "../../..");

/** The problem section, How it works, the model cards, principles and the FAQ. */

test.beforeEach(async ({ page }) => prepare(page));

test("problem section asks the question and lists the three everyday problems", async ({ page }) => {
  await open(page, "/");
  const heading = page.getByRole("heading", { level: 2, name: `${en.problem.line1} ${en.problem.line2}` });
  await expect(heading).toBeAttached();
  for (const point of en.problem.points) await expect(page.getByText(point)).toBeAttached();
});

test.describe("How it works", () => {
  const active = (page: Page) => page.locator("#how [data-step]").evaluateAll((els) => els.map((el) => (el as HTMLElement).dataset.active === "true"));

  test("shows the three steps in order", async ({ page }) => {
    await open(page, "/");
    const cards = page.locator("#how [data-step]");
    await expect(cards).toHaveCount(3);
    for (const [i, step] of en.how.steps.entries()) {
      await expect(cards.nth(i)).toContainText(step.title);
      await expect(cards.nth(i)).toContainText(`Step ${i + 1} of 3`);
    }
  });

  test("the route lights the steps in order as it is drawn", async ({ page }) => {
    await open(page, "/");
    await scrollEdgeTo(page, "#how [data-steps]", "top", 0.8); // just coming into view
    await page.waitForTimeout(500);
    expect(await active(page)).toEqual([true, false, false]);
  });

  test("every step is lit once all three cards are fully on screen", async ({ page }) => {
    await open(page, "/");
    await scrollEdgeTo(page, "#how [data-steps]", "bottom", 0.92);
    await page.waitForTimeout(500);
    expect(await active(page)).toEqual([true, true, true]);
  });

  test("cards tilt towards the pointer and settle back", async ({ page }) => {
    await open(page, "/");
    await scrollEdgeTo(page, "#how [data-steps]", "bottom", 0.9);
    const card = page.locator("#how [data-step] .card").first();
    const box = (await card.boundingBox())!;
    await page.mouse.move(box.x + box.width * 0.9, box.y + box.height * 0.1);
    await page.mouse.move(box.x + box.width * 0.95, box.y + box.height * 0.05, { steps: 4 });
    await expect.poll(() => card.evaluate((el) => getComputedStyle(el).transform)).not.toBe("none");
    await expect.poll(() => card.evaluate((el) => /rotateY\(-?([\d.]+)deg\)/.exec(el.style.transform)?.[1] ?? "0").then(Number)).toBeGreaterThan(1);
  });

  test("with reduced motion every step is lit straight away", async ({ browser }) => {
    const context = await browser.newContext({ reducedMotion: "reduce" });
    const page = await context.newPage();
    await prepare(page);
    await open(page, "/#how");
    expect(await active(page)).toEqual([true, true, true]);
    await context.close();
  });

  test("on a phone the route is hidden and the cards stack", async ({ browser }) => {
    const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
    const page = await context.newPage();
    await prepare(page);
    await open(page, "/#how");
    await expect(page.locator("#how [data-route-line]")).toBeHidden();
    const boxes = await page.locator("#how [data-step]").evaluateAll((els) => els.map((el) => el.getBoundingClientRect().top));
    expect(boxes[1]).toBeGreaterThan(boxes[0]);
    await context.close();
  });
});

test.describe("model cards", () => {
  test("list each model with its job, its real code path and a working badge", async ({ page }) => {
    await open(page, "/#models");
    const cards = page.locator("#models li");
    await expect(cards).toHaveCount(en.models.items.length);
    for (const [i, m] of en.models.items.entries()) {
      await expect(cards.nth(i)).toContainText(m.name);
      await expect(cards.nth(i)).toContainText(m.role);
      await expect(cards.nth(i)).toContainText(m.path);
      await expect(cards.nth(i)).toContainText(en.models.working);
      expect(existsSync(path.join(ROOT, m.path)), m.path).toBe(true); // the path is real
      await expect(cards.nth(i).locator("svg")).toBeVisible();
    }
    await expect(page.getByText(en.models.status)).toBeVisible();
  });

  test("the talking illustration types its answer out while on screen", async ({ page }) => {
    await open(page, "/#models");
    const hidden = () => page.locator("#models [data-ch]").evaluateAll((chars) => chars.filter((c) => c.getAttribute("fill-opacity") === "0").length);
    await expect.poll(hidden, { timeout: 5_000 }).toBeGreaterThan(0);
  });

  test("with reduced motion the illustrations show their finished frame", async ({ browser }) => {
    const context = await browser.newContext({ reducedMotion: "reduce" });
    const page = await context.newPage();
    await prepare(page);
    await open(page, "/#models");
    const hidden = await page.locator("#models [data-ch]").evaluateAll((chars) => chars.filter((c) => c.getAttribute("fill-opacity") === "0").length);
    expect(hidden).toBe(0);
    await expect(page.locator("#models").getByText(en.models.glyph.label, { exact: true })).toBeVisible();
    await context.close();
  });
});

test.describe("where Recall runs", () => {
  test("four devices, each with its honest status; only the iPhone is available now", async ({ page }) => {
    await open(page, "/#devices");
    const cards = page.locator("#devices [data-device]");
    await expect(cards).toHaveCount(4);
    const status = (id: string) => page.locator(`#devices [data-device="${id}"] [data-status]`);
    await expect(status("iphone")).toHaveText(en.devices.status.available);
    await expect(status("watch")).toHaveText(en.devices.status.next);
    await expect(status("glasses")).toHaveText(en.devices.status.planned);
    await expect(status("robots")).toHaveText(en.devices.status.preview);
    await expect(page.locator("#devices").getByText(en.devices.note)).toBeVisible();
    await expect(page.locator('#devices [data-device="robots"] a')).toHaveAttribute("href", "/privacy");
  });

  test("nothing on the page says the Watch works today", async ({ page }) => {
    await open(page, "/");
    const body = (await page.locator("main").innerText()).replace(/\s+/g, " ");
    for (const m of body.matchAll(/[^.]*Apple Watch[^.]*\./g)) {
      expect(m[0], m[0]).not.toMatch(/optional|available now|on your Apple Watch|tap pattern on your/i);
    }
  });
});

test("principles are all listed", async ({ page }) => {
  await open(page, "/#privacy");
  for (const p of en.principles.items) {
    await expect(page.getByRole("heading", { name: p.title })).toBeVisible();
    await expect(page.getByText(p.body)).toBeVisible();
  }
});

test.describe("FAQ", () => {
  test("opens one answer at a time, by mouse or keyboard", async ({ page }) => {
    await open(page, "/#faq");
    const faq = page.locator("#faq");
    const [first, second, third] = en.faq.items;
    const button = (q: string) => faq.getByRole("button", { name: q });

    await expect(button(first.q)).toHaveAttribute("aria-expanded", "true");
    await expect(faq.getByText(first.a)).toBeVisible();

    await button(second.q).click();
    await expect(button(second.q)).toHaveAttribute("aria-expanded", "true");
    await expect(button(first.q)).toHaveAttribute("aria-expanded", "false");
    await expect(faq.getByText(second.a)).toBeVisible();
    await expect(faq.getByText(first.a)).toBeHidden();

    await button(third.q).focus();
    await page.keyboard.press("Enter");
    await expect(button(third.q)).toHaveAttribute("aria-expanded", "true");
    await expect(button(third.q)).toHaveAttribute("aria-controls", /faq-panel-2/);
  });

  test("lists every question", async ({ page }) => {
    await open(page, "/#faq");
    for (const item of en.faq.items) await expect(page.locator("#faq").getByRole("button", { name: item.q })).toBeVisible();
  });
});
