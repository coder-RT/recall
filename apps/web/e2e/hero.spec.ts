import { expect, test } from "@playwright/test";
import { en } from "../i18n/dictionaries/en";
import { brailleCells, matrixDots } from "../lib/braille";
import { open, prepare, spokenTexts, stubSpeech } from "./helpers";

const PITCH = 10; // svg units per grid step in BrailleHero
const targets = matrixDots("RECALL").map((d) => ({ x: d.x * PITCH + 5, y: d.y * PITCH + 5 }));
const brailleDotCount = brailleCells("RECALL", { capsWord: true }).reduce((n, c) => n + c.dots.length, 0);

const dotPositions = (page: import("@playwright/test").Page) =>
  page.locator("#top [data-dot]").evaluateAll((dots) => dots.map((d) => ({ x: Number(d.getAttribute("cx")), y: Number(d.getAttribute("cy")) })));

test.beforeEach(async ({ page }) => prepare(page));

test.describe("hero wordmark", () => {
  test("has a real heading and every wordmark dot", async ({ page }) => {
    await open(page, "/");
    await expect(page.getByRole("heading", { level: 1, name: "Recall" })).toBeAttached();
    await expect(page.locator("#top [data-dot]")).toHaveCount(targets.length);
    await expect(page.locator("#top [data-braille]")).toHaveCount(brailleDotCount);
    await expect(page.getByRole("img", { name: `RECALL${en.braille.label.replace("{word}", "")}${en.braille.capsSign}` })).toBeVisible();
  });

  test("the orb settles into the word, every dot on its letter", async ({ page }) => {
    await open(page, "/");
    await page.waitForTimeout(4_500); // spin, then the 1.7s assembly
    const dots = await dotPositions(page);
    dots.forEach((d, i) => {
      expect(Math.abs(d.x - targets[i].x), `dot ${i} x`).toBeLessThan(3);
      expect(Math.abs(d.y - targets[i].y), `dot ${i} y`).toBeLessThan(3);
    });
  });

  test("starts as an orb (the dots are not yet on the letters)", async ({ page }) => {
    await open(page, "/");
    await page.waitForTimeout(400);
    const dots = await dotPositions(page);
    const offTarget = dots.filter((d, i) => Math.hypot(d.x - targets[i].x, d.y - targets[i].y) > 5).length;
    expect(offTarget).toBeGreaterThan(dots.length / 2);
  });

  test("with reduced motion the word is simply there", async ({ browser }) => {
    const context = await browser.newContext({ reducedMotion: "reduce" });
    const page = await context.newPage();
    await prepare(page);
    await open(page, "/");
    expect(await dotPositions(page)).toEqual(targets);
    await context.close();
  });

  test("calls to action lead to their sections", async ({ page }) => {
    await open(page, "/");
    await expect(page.getByRole("link", { name: en.hero.seeHow })).toHaveAttribute("href", "#how");
    await expect(page.getByRole("link", { name: en.hero.browse })).toHaveAttribute("href", "#feed");
    await expect(page.getByText(en.hero.tagline)).toBeVisible();
  });
});

test.describe("connected home band", () => {
  const band = (page: import("@playwright/test").Page) => page.locator("#top svg").filter({ has: page.locator("[data-node]") });
  const seenOf = (id: string) => en.feed.posts.find((p) => p.id === id)!.seen;

  test("shows Sam and his things linked up, with time chips and emoji badges", async ({ page }) => {
    await open(page);
    await expect(band(page)).toHaveAttribute("aria-hidden", "true");
    await expect(band(page).locator("[data-node]")).toHaveCount(7); // Sam + six things
    await expect(band(page).locator("[data-link]")).toHaveCount(10);
    await expect(band(page).locator("[data-emoji]")).toHaveCount(4);
    expect(await band(page).locator("[data-time-chip]").allTextContents()).toEqual([seenOf("keys"), seenOf("mug")]);
  });

  test("its dotted links flow while it is on screen", async ({ page }) => {
    await open(page);
    await band(page).scrollIntoViewIfNeeded();
    await page.waitForTimeout(3_200); // after its entrance
    const offset = () => band(page).locator("[data-link]").first().evaluate((el) => getComputedStyle(el).strokeDashoffset);
    const first = await offset();
    await expect.poll(offset).not.toBe(first);
  });

  test("with reduced motion it is fully drawn and still", async ({ browser }) => {
    const context = await browser.newContext({ reducedMotion: "reduce" });
    const page = await context.newPage();
    await prepare(page);
    await open(page);
    const opacities = await band(page)
      .locator("[data-node] > g, [data-emoji] > g, [data-mini-card] > g, [data-link]")
      .evaluateAll((els) => els.map((el) => Number(getComputedStyle(el).opacity)));
    expect(Math.min(...opacities)).toBe(1);
    const offset = () => band(page).locator("[data-link]").first().evaluate((el) => getComputedStyle(el).strokeDashoffset);
    const first = await offset();
    await page.waitForTimeout(800);
    expect(await offset()).toBe(first);
    await context.close();
  });

  test("fits a phone without sideways scrolling", async ({ browser }) => {
    const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
    const page = await context.newPage();
    await prepare(page);
    await open(page);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    // the band is cropped to its middle on a phone: Sam's pin stays fully on screen
    await band(page).scrollIntoViewIfNeeded();
    const sam = await band(page).locator("[data-node]").filter({ has: page.locator("[data-frame]") }).boundingBox();
    expect(sam!.x).toBeGreaterThanOrEqual(0);
    expect(sam!.x + sam!.width).toBeLessThanOrEqual(390);
    await context.close();
  });
});

test.describe("connected home band: Sam's walk", () => {
  const band = (page: import("@playwright/test").Page) => page.locator("#top svg").filter({ has: page.locator("[data-node]") });
  const walkerAt = (page: import("@playwright/test").Page) =>
    band(page)
      .locator("[data-walker]")
      .evaluate((el) => {
        const m = (el as SVGGraphicsElement).transform.baseVal.consolidate()!.matrix;
        return { x: m.e, y: m.f, opacity: Number(getComputedStyle(el).opacity) };
      });

  test("labels the rooms", async ({ page }) => {
    await open(page);
    expect(await band(page).locator("[data-room]").allTextContents()).toEqual(en.hero.rooms.map((r) => r.toUpperCase()));
  });

  test("Sam walks the links, and the floor is scanned around him", async ({ page }) => {
    await open(page);
    await band(page).scrollIntoViewIfNeeded();
    await expect.poll(async () => (await walkerAt(page)).opacity, { timeout: 8_000 }).toBe(1);
    const first = await walkerAt(page);
    await expect.poll(async () => Math.hypot((await walkerAt(page)).x - first.x, (await walkerAt(page)).y - first.y)).toBeGreaterThan(20);
    // the scan glow is on him
    const { walker, glow } = await band(page).evaluate((svg) => {
      const m = svg.querySelector<SVGGElement>("[data-walker]")!.transform.baseVal.consolidate()!.matrix;
      const g = svg.querySelector("[data-scan-glow]")!;
      return { walker: { x: m.e, y: m.f }, glow: { x: Number(g.getAttribute("cx")), y: Number(g.getAttribute("cy")), opacity: Number(getComputedStyle(g).opacity) } };
    });
    expect(glow.opacity).toBe(1);
    expect(Math.hypot(walker.x - glow.x, walker.y - glow.y)).toBeLessThan(2);
  });

  test("he walks in front of the pins and is never cut off", async ({ page }) => {
    await open(page);
    await band(page).scrollIntoViewIfNeeded();
    const inFront = await band(page).evaluate((svg) => {
      const walker = svg.querySelector("[data-walker]")!;
      return [...svg.querySelectorAll("[data-node]")].every((n) => n.compareDocumentPosition(walker) & Node.DOCUMENT_POSITION_FOLLOWING);
    });
    expect(inFront).toBe(true);
    await expect.poll(async () => (await walkerAt(page)).opacity, { timeout: 8_000 }).toBe(1);
    // every frame for 10s (one-frame blips count): the sprite stays inside the band
    const worst = await band(page).evaluate(
      (svg) =>
        new Promise<{ top: number; bottom: number }>((resolve) => {
          const box = svg.getBoundingClientRect();
          const sprite = svg.querySelector("[data-walker] g[transform]")!;
          let top = Infinity;
          let bottom = -Infinity;
          const end = performance.now() + 10_000;
          const tick = () => {
            const r = sprite.getBoundingClientRect();
            top = Math.min(top, r.top - box.top);
            bottom = Math.max(bottom, r.bottom - box.bottom);
            if (performance.now() < end) requestAnimationFrame(tick);
            else resolve({ top, bottom });
          };
          tick();
        }),
    );
    expect(worst.top).toBeGreaterThanOrEqual(-2);
    expect(worst.bottom).toBeLessThanOrEqual(2);
  });

  test("only one Sam at a time: his circle is empty while he is out walking, and he is full size", async ({ page }) => {
    await open(page);
    await band(page).scrollIntoViewIfNeeded();
    const state = () =>
      band(page).evaluate((svg) => {
        const op = (sel: string) => Number(getComputedStyle(svg.querySelector(sel)!).opacity);
        const size = (sel: string) => (svg.querySelector(sel)!.firstElementChild as SVGGraphicsElement).getBoundingClientRect().height;
        return { walker: op("[data-walker]"), home: op("[data-home-sam]"), walkerSize: size("[data-walker] g[transform]"), homeSize: size("[data-home-sam]") };
      });
    await expect.poll(async () => (await state()).walker, { timeout: 8_000 }).toBe(1);
    const s = await state();
    expect(s.home).toBe(0);
    expect(Math.abs(s.walkerSize - s.homeSize)).toBeLessThan(2);
  });

  test("coming home, he lands exactly where Sam sits in his circle", async ({ browser }) => {
    const context = await browser.newContext({ reducedMotion: "reduce" }); // a still page: the walker rests at home
    const page = await context.newPage();
    await prepare(page);
    await open(page);
    await band(page).evaluate((svg) => {
      const w = svg.querySelector<SVGGElement>("[data-walker]")!;
      w.setAttribute("transform", "translate(520 120) scale(1 1)"); // the hub, where the walk ends
    });
    const walker = (await band(page).locator("[data-walker] g[transform]").boundingBox())!;
    const home = (await band(page).locator("[data-home-sam]").boundingBox())!;
    expect(Math.abs(walker.x - home.x)).toBeLessThan(1);
    expect(Math.abs(walker.y - home.y)).toBeLessThan(1);
    await context.close();
  });

  test("reaching the keys pings them, and their card says “just now” for a moment", async ({ page }) => {
    await open(page);
    await band(page).scrollIntoViewIfNeeded();
    const chips = () => band(page).locator("[data-time-chip]").allTextContents();
    await expect.poll(chips, { timeout: 15_000, intervals: [200] }).toContain(en.hero.justNow);
    expect(await band(page).locator('[data-ping="key"]').evaluate((el) => Number(getComputedStyle(el).opacity))).toBeGreaterThan(0);
    const keysSeen = en.feed.posts.find((p) => p.id === "keys")!.seen;
    await expect.poll(chips, { timeout: 6_000 }).toContain(keysSeen);
  });

  test("with reduced motion there is no walk and no scan", async ({ browser }) => {
    const context = await browser.newContext({ reducedMotion: "reduce" });
    const page = await context.newPage();
    await prepare(page);
    await open(page);
    await page.waitForTimeout(5_000);
    expect((await walkerAt(page)).opacity).toBe(0);
    const lit = await band(page)
      .locator("[data-scan-glow], [data-trail]")
      .evaluateAll((els) => els.filter((el) => Number(getComputedStyle(el).opacity) > 0).length);
    expect(lit).toBe(0);
    await context.close();
  });
});

test.describe("hero floaters", () => {
  const floaters = (page: import("@playwright/test").Page) => page.locator("#top [data-floater]");
  const inner = (page: import("@playwright/test").Page) => page.locator("#top [data-floater] > span");

  test("sit in the side margins of a wide screen, faint over the content", async ({ browser }) => {
    const context = await browser.newContext({ viewport: { width: 1920, height: 1080 } });
    const page = await context.newPage();
    await prepare(page);
    await open(page);
    await expect(page.locator("#top [data-floaters]")).toHaveAttribute("aria-hidden", "true");
    await page.waitForTimeout(1_800); // after their entrance
    const margin = (1920 - 1152) / 2;
    const centres = await floaters(page).evaluateAll((els) =>
      els.map((el) => {
        const r = el.getBoundingClientRect();
        return r.x + r.width / 2;
      }),
    );
    expect(centres.filter((x) => x < margin).length).toBeGreaterThanOrEqual(8);
    expect(centres.filter((x) => x > 1920 - margin).length).toBeGreaterThanOrEqual(8);
    expect(centres.filter((x) => x > margin && x < 1920 - margin).length).toBeGreaterThan(0);
    // the mask is bold beyond the content column and faint over it
    const mask = await page.locator("#top [data-floaters]").evaluate((el) => getComputedStyle(el).maskImage || getComputedStyle(el).webkitMaskImage);
    expect(mask).toMatch(/^linear-gradient\(to right, rgba\(0, 0, 0, 0\.35\) calc\(50% - 608px\), rgba\(0, 0, 0, 0\.14\)/);
    await context.close();
  });

  test("drift while the hero is on screen", async ({ page }) => {
    await open(page);
    await page.waitForTimeout(1_800);
    const transform = () => inner(page).first().evaluate((el) => getComputedStyle(el).transform);
    const first = await transform();
    await expect.poll(transform).not.toBe(first);
  });

  test("with reduced motion they are still", async ({ browser }) => {
    const context = await browser.newContext({ reducedMotion: "reduce" });
    const page = await context.newPage();
    await prepare(page);
    await open(page);
    const transforms = () => inner(page).evaluateAll((els) => els.map((el) => getComputedStyle(el).transform));
    const first = await transforms();
    expect(new Set(first)).toEqual(new Set(["none"]));
    await page.waitForTimeout(1_000);
    expect(await transforms()).toEqual(first);
    await context.close();
  });

  test("are hidden in high contrast", async ({ page }) => {
    await open(page);
    await page.evaluate(() => (document.documentElement.dataset.contrast = "high"));
    await expect(page.locator("#top [data-floaters]")).toBeHidden();
  });
});

test.describe("Ask Recall card", () => {
  test("each question shows its answer", async ({ page }) => {
    await open(page, "/");
    const card = page.locator("#ask");
    await expect(card.getByText(en.ask.questions[0].a)).toBeVisible();
    for (const item of en.ask.questions) {
      const button = card.getByRole("button", { name: `“${item.q}”` });
      await button.click();
      await expect(button).toHaveAttribute("aria-pressed", "true");
      await expect(card.getByText(item.a)).toBeVisible();
    }
    await expect(card.getByText(en.ask.disclaimer)).toBeVisible();
  });

  test("“Hear it” speaks the chosen answer with the browser's own voice", async ({ page }) => {
    await stubSpeech(page);
    await open(page, "/");
    const card = page.locator("#ask");
    await card.getByRole("button", { name: `“${en.ask.questions[2].q}”` }).click();
    // the answers cross-fade: use the "Hear it" of the answer now showing, not the one fading out
    await card.locator("figure", { hasText: en.ask.questions[2].a }).getByRole("button", { name: en.ask.hear }).click();
    await expect.poll(() => spokenTexts(page)).toEqual([en.ask.questions[2].a]);
  });

  test("without a microphone it says so", async ({ page }) => {
    await page.addInitScript(() => {
      Object.defineProperty(navigator, "mediaDevices", { value: { getUserMedia: () => Promise.reject(new Error("no mic")) } });
    });
    await open(page, "/");
    await page.locator("#ask").getByRole("button", { name: en.ask.voice }).click();
    await expect(page.locator("#ask").getByText(en.ask.errors.microphone)).toBeVisible();
  });

  test.describe("asking out loud", () => {
    // the browser's fake microphone (playwright.config.ts) stands in for a real one
    test.use({ permissions: ["microphone"] });

    test("a spoken question picks the matching answer and Recall says it", async ({ page }) => {
      await stubSpeech(page);
      // the speech service is faked here; the route itself is covered in api.spec.ts
      await page.route("**/api/voice/transcribe", (route) => route.fulfill({ json: { transcript: "Where did I leave my glasses?" } }));
      await open(page, "/");
      const card = page.locator("#ask");
      await card.getByRole("button", { name: en.ask.voice }).click();
      await expect(card.getByRole("button", { name: en.ask.listening })).toBeVisible();
      await page.waitForTimeout(600);
      await card.getByRole("button", { name: en.ask.listening }).click();
      await expect(card.getByText(en.ask.youAsked)).toBeVisible();
      await expect(card.getByRole("button", { name: `“${en.ask.questions[1].q}”` })).toHaveAttribute("aria-pressed", "true");
      await expect.poll(() => spokenTexts(page)).toEqual([en.ask.questions[1].a]);
    });

    test("an unrelated question gets the honest fallback", async ({ page }) => {
      await stubSpeech(page);
      await page.route("**/api/voice/transcribe", (route) => route.fulfill({ json: { transcript: "What's the weather?" } }));
      await open(page, "/");
      const card = page.locator("#ask");
      await card.getByRole("button", { name: en.ask.voice }).click();
      await page.waitForTimeout(400);
      await card.getByRole("button", { name: en.ask.listening }).click();
      await expect(card.getByText(en.ask.noMatch)).toBeVisible();
      await expect.poll(() => spokenTexts(page)).toEqual([en.ask.noMatch]);
    });

    test("a server error is shown in plain words", async ({ page }) => {
      await page.route("**/api/voice/transcribe", (route) => route.fulfill({ status: 429, json: { error: "rate_limited" } }));
      await open(page, "/");
      const card = page.locator("#ask");
      await card.getByRole("button", { name: en.ask.voice }).click();
      await page.waitForTimeout(400);
      await card.getByRole("button", { name: en.ask.listening }).click();
      await expect(card.getByText(en.ask.errors.rate_limited)).toBeVisible();
    });
  });
});

test.describe("hero icons", () => {
  test("the floaters include a 'found it' glass and a clock, the product's two moments", async ({ page }) => {
    await prepare(page);
    await open(page);
    await expect(page.locator("#top [data-floater='found']")).toHaveCount(1);
    await expect(page.locator("#top [data-floater='clock']")).toHaveCount(1);
  });
});
