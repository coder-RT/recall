import { expect, type Page } from "@playwright/test";

/**
 * Shared helpers for the landing-page tests. Scroll scenes are driven by real scrolling (pinned
 * sections are wrapped in a GSAP `.pin-spacer`), then the test waits for the scrubbed animation.
 */

/** Skip the privacy note (it covers the bottom-right corner) and optionally preset accessibility settings. */
export async function prepare(page: Page, { notice = false, a11y }: { notice?: boolean; a11y?: Record<string, unknown> } = {}) {
  await page.addInitScript(
    ({ notice, a11y }) => {
      if (!notice) localStorage.setItem("recall:notice-seen", "1");
      if (a11y) localStorage.setItem("recall:a11y", JSON.stringify(a11y));
    },
    { notice, a11y },
  );
}

/** Wait until the page has hydrated and is interactive. */
export const hydrated = (page: Page) => page.waitForFunction(() => document.documentElement.dataset.hydrated === "true");

/** Go to a page and wait until it is interactive (clicks before hydration would be lost). */
export async function open(page: Page, path = "/") {
  await page.goto(path);
  await hydrated(page);
}

/** Scroll so a pinned section's scene is at `progress` (0 = pin starts, 1 = pin ends). */
export async function scrollPin(page: Page, id: string, progress: number) {
  // the scene is set up after hydration; scrolling before the pin exists would land at its start
  await page.waitForFunction((id) => document.getElementById(id)?.parentElement?.classList.contains("pin-spacer"), id);
  await page.evaluate(
    ([id, progress]) => {
      const section = document.getElementById(id as string)!;
      const spacer = section.parentElement?.classList.contains("pin-spacer") ? section.parentElement : section;
      const start = spacer.getBoundingClientRect().top + window.scrollY;
      const length = spacer.offsetHeight - section.offsetHeight;
      window.scrollTo({ top: start + length * (progress as number), behavior: "instant" });
    },
    [id, progress] as const,
  );
}

/** Scroll so an element's top or bottom edge sits at a fraction of the viewport height. */
export async function scrollEdgeTo(page: Page, selector: string, edge: "top" | "bottom", fraction: number) {
  await page.evaluate(
    ([selector, edge, fraction]) => {
      const box = document.querySelector(selector as string)!.getBoundingClientRect();
      const y = edge === "top" ? box.top : box.bottom;
      window.scrollTo({ top: window.scrollY + y - window.innerHeight * (fraction as number), behavior: "instant" });
    },
    [selector, edge, fraction] as const,
  );
}

/** Floating reactions currently on screen. */
export const reactionCount = (page: Page) => page.locator("[data-reactions] > *").count();

/** Wait for floating reactions to appear. */
export const expectReactions = (page: Page, timeout = 3_000) => expect.poll(() => reactionCount(page), { timeout }).toBeGreaterThan(0);
/** Wait for floating reactions to be gone. */
export const expectNoReactions = (page: Page, timeout = 3_000) => expect.poll(() => reactionCount(page), { timeout }).toBe(0);

/** Record device speech instead of speaking: window.__spoken lists spoken texts. */
export async function stubSpeech(page: Page) {
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
          setTimeout(() => u.onend?.(new Event("end") as SpeechSynthesisEvent), 30);
        },
      },
    });
  });
}
export const spokenTexts = (page: Page) => page.evaluate(() => (window as unknown as { __spoken: string[] }).__spoken);

/** The page never shows unfilled template text. */
export async function expectNoBrokenText(page: Page) {
  const text = await page.locator("body").innerText();
  expect(text).not.toMatch(/\bundefined\b|\[object Object\]|\{[a-z]+\}/);
}
