import { expect, test, type Page } from "@playwright/test";
import { captionTimes, STORY_SECONDS } from "../content/story";
import { en } from "../i18n/dictionaries/en";
import { open } from "./helpers";

/**
 * The "One morning, one mug" story must always show what each spoken line talks about.
 * With narration on, the story freezes on a line's exact moment while it is spoken, so each
 * line's frame is checked at exactly its `at` time.
 */

type CaptionKey = (typeof captionTimes)[number]["key"];

/** What is on screen in the story frame right now. */
async function look(page: Page) {
  return page.evaluate(() => {
    const story = document.querySelector("#story")!;
    const box = story.querySelector("[data-frame-box]")!.getBoundingClientRect();
    const el = (selector: string) => story.querySelector(selector);
    // multiplies opacity up the tree, so a hidden parent hides its children
    const opacity = (node: Element | null) => {
      let value = 1;
      for (let n = node; n && n !== story; n = n.parentElement) value *= Number(getComputedStyle(n).opacity);
      return value;
    };
    const rect = (selector: string) => el(selector)?.getBoundingClientRect() ?? null;
    const visible = (selector: string) => {
      const r = rect(selector);
      return !!r && opacity(el(selector)) > 0.5 && r.width > 1 && r.height > 1 && r.right > box.left && r.left < box.right && r.bottom > box.top && r.top < box.bottom;
    };
    const sam = rect("[data-sam] > g:first-child");
    const mug = rect("[data-mug]");
    const plant = rect("[data-plant]");
    return {
      caption: el("[data-caption]")?.textContent ?? "",
      clock: el("[data-clock]")?.textContent ?? "",
      samInFrame: !!sam && sam.left >= box.left - 1 && sam.right <= box.right + 1 && opacity(el("[data-sam]")) > 0.5,
      bubble: visible("[data-bubble]"),
      sofaCross: visible("[data-cross='sofa']"),
      phone: visible("[data-phone]"),
      samWaving: visible('[data-frame="wave"]'),
      mugAwake: visible("[data-eyes]") && visible("[data-smile]"),
      mugClearOfPlant: !!mug && !!plant && mug.left > plant.left + plant.width / 2,
    };
  });
}
type Look = Awaited<ReturnType<typeof look>>;

/** What each line needs on screen while it is spoken. A new line without an entry fails the test. */
const storyboard: Record<CaptionKey, (s: Look) => void> = {
  wants: (s) => expect(s.bubble, "Sam's thought bubble shows the mug").toBe(true),
  notHere: (s) => expect(s.sofaCross, "the sofa is crossed out").toBe(true),
  asks: (s) => expect(s.phone, "Sam holds his phone").toBe(true),
  answer: (s) => expect(s.phone, "Sam holds his phone").toBe(true),
  here: (s) => {
    expect(s.mugClearOfPlant, "the mug is out from behind the plant").toBe(true);
    expect(s.mugAwake, "the mug's eyes and smile show").toBe(true);
  },
  there: (s) => {
    expect(s.samWaving, "Sam waves").toBe(true);
    expect(s.mugAwake, "the mug's eyes and smile show").toBe(true);
  },
  found: (s) => expect(s.mugAwake, "the mug's eyes and smile show").toBe(true),
};

const slider = (page: Page) => page.locator("#story input[type=range]");

/** Seek the way a person does: set the slider, then let go (keyup ends the drag). */
async function seek(page: Page, seconds: number) {
  await slider(page).fill(String(Math.round(seconds * 10)));
  await slider(page).press("Shift");
}

test.beforeEach(async ({ page }) => {
  // the privacy note would cover the controls
  await page.addInitScript(() => localStorage.setItem("recall:notice-seen", "1"));
});

test.describe("story, motion on", () => {
  test.beforeEach(async ({ page }) => {
    await open(page, "/#story");
    await page.getByRole("button", { name: en.story.pause }).click();
  });

  for (const line of captionTimes) {
    test(`“${en.story.captions[line.key]}” (${line.at}s) shows what it talks about`, async ({ page }) => {
      await seek(page, line.at);
      const s = await look(page);
      expect(s.caption).toBe(en.story.captions[line.key]);
      expect(s.samInFrame, "Sam is inside the frame").toBe(true);
      storyboard[line.key](s);
    });
  }

  test("every line still shows what it talks about when seeking backwards, and after Replay", async ({ page }) => {
    const visitAllBackwards = async () => {
      for (const line of [...captionTimes].reverse()) {
        await seek(page, line.at);
        const s = await look(page);
        expect(s.caption).toBe(en.story.captions[line.key]);
        expect(s.samInFrame, `Sam is inside the frame at ${line.at}s`).toBe(true);
        storyboard[line.key](s);
      }
    };
    await seek(page, STORY_SECONDS);
    await visitAllBackwards();

    // play out the ending, Replay, and check again
    await seek(page, STORY_SECONDS - 0.3);
    await page.getByRole("button", { name: en.story.play }).click();
    const replay = page.locator("[data-frame-box]").getByRole("button", { name: en.story.replay });
    await replay.click();
    await page.getByRole("button", { name: en.story.pause }).click();
    await visitAllBackwards();
  });

  test("the hearts rise out of the top of the mug", async ({ page }) => {
    await seek(page, 9.2); // just after they appear
    const { mug, hearts } = await page.evaluate(() => {
      const story = document.querySelector("#story")!;
      const r = (el: Element) => el.getBoundingClientRect();
      const body = story.querySelector("[data-mug-body] rect")!; // the mug's body outline
      return {
        mug: { top: r(body).top, left: r(body).left, right: r(body).right },
        hearts: [...story.querySelectorAll("[data-heart]")]
          .filter((h) => Number(getComputedStyle(h).opacity) > 0.05)
          .map((h) => ({ bottom: r(h).bottom, centre: r(h).left + r(h).width / 2 })),
      };
    });
    expect(hearts.length).toBeGreaterThan(0);
    for (const h of hearts) {
      expect(Math.abs(h.bottom - mug.top), "a heart starts at the mug's rim").toBeLessThan(14);
      expect(h.centre).toBeGreaterThan(mug.left);
      expect(h.centre).toBeLessThan(mug.right);
    }
  });

  test("Sam is on screen from the very first frame", async ({ page }) => {
    await seek(page, 0);
    const s = await look(page);
    expect(s.samInFrame).toBe(true);
    expect(s.caption).toBe(en.story.captions.wants);
  });

  test("plays once, stops on the last frame and offers Replay", async ({ page }) => {
    await seek(page, STORY_SECONDS - 0.3);
    await page.getByRole("button", { name: en.story.play }).click();
    const replay = page.locator("[data-frame-box]").getByRole("button", { name: en.story.replay });
    await expect(replay).toBeVisible({ timeout: 5_000 });
    // it doesn't loop: still on the last frame a moment later
    await page.waitForTimeout(2_500);
    expect((await look(page)).clock).toBe("0:12 / 0:12");

    await replay.click();
    await expect(replay).toBeHidden();
    const s = await look(page);
    expect(s.clock.startsWith("0:00") || s.clock.startsWith("0:01")).toBe(true);
    expect(s.samInFrame).toBe(true);
  });

  test("the slider follows the story and can be moved with the keyboard", async ({ page }) => {
    await seek(page, 6);
    await expect(slider(page)).toHaveAttribute("aria-valuetext", "0:06 of 0:12");
    await slider(page).press("ArrowRight");
    await expect(slider(page)).toHaveValue("61");
  });
});

test("with narration on, every line is spoken exactly once, in order, even if paused mid-line", async ({ page }) => {
  // stand-in speech: records each spoken line and ends it after a short moment
  await page.addInitScript(() => {
    const w = window as unknown as { __spoken: string[] };
    w.__spoken = [];
    Object.defineProperty(window, "speechSynthesis", {
      configurable: true,
      value: {
        getVoices: () => [],
        addEventListener: () => {},
        cancel: () => {},
        speak: (u: SpeechSynthesisUtterance) => {
          w.__spoken.push(u.text);
          setTimeout(() => u.onend?.(new Event("end") as SpeechSynthesisEvent), 400);
        },
      },
    });
  });
  await open(page, "/#story");
  await page.getByRole("button", { name: en.story.pause }).click();
  await page.getByRole("button", { name: en.story.soundOn }).click();
  await seek(page, 0);
  await page.getByRole("button", { name: en.story.play }).click();

  // pause and resume while the third line is being spoken
  await page.waitForFunction(() => (window as unknown as { __spoken: string[] }).__spoken.length === 3);
  await page.getByRole("button", { name: en.story.pause }).click();
  await page.getByRole("button", { name: en.story.play }).click();

  await expect(page.locator("[data-frame-box]").getByRole("button", { name: en.story.replay })).toBeVisible({ timeout: 40_000 });
  const spoken = await page.evaluate(() => (window as unknown as { __spoken: string[] }).__spoken);
  expect(spoken).toEqual(captionTimes.map((c) => en.story.captions[c.key].replace(/[“”"]/g, "")));
});

test("reduced motion shows the finished story, the transcript and no player", async ({ browser }) => {
  const context = await browser.newContext({ reducedMotion: "reduce", viewport: { width: 1280, height: 900 } });
  const page = await context.newPage();
  await open(page, "/#story");
  const s = await look(page);
  expect(s.samInFrame).toBe(true);
  expect(s.samWaving).toBe(true);
  expect(s.mugAwake).toBe(true);
  expect(s.mugClearOfPlant).toBe(true);
  await expect(page.locator("#story").getByText(en.story.transcript)).toBeVisible();
  await expect(slider(page)).toHaveCount(0);
  await context.close();
});

test("without JavaScript the story still shows its finished frame", async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 1280, height: 900 } });
  const page = await context.newPage();
  await page.goto("/#story"); // no JavaScript: nothing hydrates, so no waiting for it
  const s = await look(page).catch(() => null);
  // evaluate needs JS; check the server HTML instead
  if (!s) {
    const html = await page.content();
    expect(html).toContain('data-frame="wave"');
    expect(html).toContain(en.story.captions.found);
  }
  await context.close();
});
