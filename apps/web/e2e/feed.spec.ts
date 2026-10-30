import { expect, test, type Page } from "@playwright/test";
import { en } from "../i18n/dictionaries/en";
import { objectIcon } from "../lib/pixel-icons";
import { open, expectNoReactions, expectReactions, prepare, scrollPin } from "./helpers";

/** The memory feed: a pinned 3D coverflow on desktop, a grid elsewhere. */

/** Which card is nearest the middle of the screen, how far off it is (0–1), and which sticker shows. */
async function centre(page: Page) {
  return page.evaluate(() => {
    const half = window.innerWidth / 2;
    const cards = [...document.querySelectorAll("#feed [data-post]")].map((el) => {
      const r = el.getBoundingClientRect();
      return Math.abs(r.left + r.width / 2 - half) / half;
    });
    const nearest = cards.indexOf(Math.min(...cards));
    const stickers = [...document.querySelectorAll("#feed [data-sticker]")];
    const sticker = stickers.findIndex((el) => getComputedStyle(el).visibility !== "hidden" && Number(getComputedStyle(el).opacity) > 0.5);
    return { nearest, offset: cards[nearest], sticker, counter: document.querySelector("#feed [data-count]")?.textContent };
  });
}

test.beforeEach(async ({ page }) => prepare(page));

test("every sample memory is a labelled post", async ({ page }) => {
  await open(page, "/");
  const posts = page.locator("#feed [data-post]");
  await expect(posts).toHaveCount(en.feed.posts.length);
  for (const [i, post] of en.feed.posts.entries()) {
    await expect(posts.nth(i).getByRole("article", { name: `${post.object}, last seen ${post.seen}` })).toBeAttached();
    await expect(posts.nth(i)).toContainText(post.text);
  }
  await expect(page.getByText(en.feed.eyebrow)).toBeAttached();
});

test.describe("desktop coverflow", () => {
  test("pins and runs sideways, with the centred card facing forward", async ({ page }) => {
    await open(page, "/");
    await expect(page.locator("#feed")).toHaveAttribute("data-horizontal", "true");
    await scrollPin(page, "feed", 0.4);
    await page.waitForTimeout(1_200);
    const { nearest } = await centre(page);
    const angle = await page.locator("#feed [data-post]").nth(nearest).evaluate((el) => {
      const m = new DOMMatrix(getComputedStyle(el).transform);
      return Math.abs((Math.atan2(-m.m13, m.m11) * 180) / Math.PI);
    });
    expect(angle).toBeLessThan(15);
  });

  test("the floating sticker always shows the centred card's object", async ({ page }) => {
    await open(page, "/");
    let checked = 0;
    for (const progress of [0.2, 0.4, 0.6, 0.8, 1]) {
      await scrollPin(page, "feed", progress);
      await page.waitForTimeout(1_200);
      const c = await centre(page);
      if (c.offset > 0.25) continue; // between two cards
      expect(c.sticker, `at ${progress}`).toBe(c.nearest);
      checked++;
    }
    expect(checked).toBeGreaterThanOrEqual(3);
  });

  test("the last card reaches the middle, with its mug sticker and 6 / 6", async ({ page }) => {
    await open(page, "/");
    await scrollPin(page, "feed", 0.97);
    await page.waitForTimeout(1_200);
    const c = await centre(page);
    expect(c.nearest).toBe(en.feed.posts.length - 1);
    expect(c.sticker).toBe(en.feed.posts.length - 1);
    expect(objectIcon[en.feed.posts[c.sticker].id]).toBe("mug");
    expect(c.counter).toBe(String(en.feed.posts.length));
  });

  test("reaching the end sets off the finale, which clears when you scroll on", async ({ page }) => {
    await open(page, "/");
    await scrollPin(page, "feed", 0.5);
    await page.waitForTimeout(800);
    await scrollPin(page, "feed", 0.97);
    await expectReactions(page);
    await page.locator("#models").scrollIntoViewIfNeeded();
    await expectNoReactions(page);
  });

  test("the finale plays again on the next pass, not on a quick jiggle", async ({ page }) => {
    test.setTimeout(60_000);
    await open(page, "/");
    await scrollPin(page, "feed", 0.5);
    await page.waitForTimeout(800);
    await scrollPin(page, "feed", 0.97);
    await expectReactions(page);
    // a quick jiggle at the end: no second finale
    await scrollPin(page, "feed", 0.9);
    await page.waitForTimeout(600);
    await expectNoReactions(page, 6_000);
    await scrollPin(page, "feed", 0.97);
    await page.waitForTimeout(1_500);
    expect(await page.locator("[data-reactions] > *").count()).toBe(0);
    // back through the feed (re-arms), past the cooldown, then to the end again
    await scrollPin(page, "feed", 0.1);
    await page.waitForTimeout(8_500);
    await scrollPin(page, "feed", 0.97);
    await expectReactions(page);
  });
});

test("reacting to a post sends that reaction up the screen", async ({ browser }) => {
  // phone-sized: the feed is a plain grid, so the card is easy to reach
  const context = await browser.newContext({ viewport: { width: 430, height: 900 } });
  const page = await context.newPage();
  await prepare(page);
  await open(page, "/#feed");
  const post = page.locator("#feed [data-post]").first();
  await post.scrollIntoViewIfNeeded();
  const like = post.getByRole("button", { name: en.feed.reactions[0].label, exact: true });
  await like.hover();
  await post.getByRole("group", { name: en.feed.reactionsLabel }).getByRole("button", { name: en.feed.reactions[1].label }).click();
  await expectReactions(page);
  // the Like button now shows the chosen reaction
  await expect(post.locator("button[aria-controls]")).toHaveText(new RegExp(en.feed.reactions[1].label));
  await context.close();
});

for (const [name, options] of [
  ["on a phone", { viewport: { width: 390, height: 844 } }],
  ["with reduced motion", { reducedMotion: "reduce" as const }],
] as const) {
  test(`${name} the feed is a grid that fits the screen`, async ({ browser }) => {
    const context = await browser.newContext(options);
    const page = await context.newPage();
    await prepare(page);
    await open(page, "/#feed");
    await expect(page.locator("#feed")).not.toHaveAttribute("data-horizontal", "true");
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    await context.close();
  });
}

test("with large text the feed falls back to the grid", async ({ page }) => {
  await prepare(page, { a11y: { textScale: 1.5 } });
  await open(page, "/");
  await expect(page.locator("#feed")).not.toHaveAttribute("data-horizontal", "true");
});
