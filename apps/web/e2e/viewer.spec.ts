import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";
import { en } from "../i18n/dictionaries/en";
import { testFiles, testMeta as meta } from "./fixtures/test-room";
import { open as openPage, prepare } from "./helpers";

/**
 * The 3D viewer at /homes/<home>/viewer: that home's export on this computer (public/local-scan/<home>/), or the steps.
 * The tests serve a made-up room (fixtures/test-room.ts) instead of anything on disk, so they never see a real home.
 */

const PAGE = "/homes/flat/viewer";
const s = en.app.viewer.scan;
const steps = en.app.viewer.steps;

/** Serve the made-up room as this computer's export, or say there is none. */
async function serveScan(page: Page, present: boolean) {
  await page.route("**/local-scan/**", (route) => {
    const url = new URL(route.request().url());
    if (!url.pathname.startsWith("/local-scan/flat/")) return route.fulfill({ status: 404, body: "" }); // other homes: none
    const file = url.pathname.split("/").pop() ?? "";
    const body = present ? testFiles[file] : undefined;
    return body ? route.fulfill({ status: 200, body }) : route.fulfill({ status: 404, body: "" });
  });
}

/** Open the viewer with the made-up room present (the default) or absent. */
async function open(page: Page, path: string, { scan = true } = {}) {
  await serveScan(page, scan);
  await openPage(page, path);
}
const progress = (page: Page) => page.locator("[data-viewer]").getAttribute("data-progress");
const formed = (page: Page) => page.waitForFunction(() => document.querySelector<HTMLElement>("[data-viewer]")?.dataset.progress === "1");
const canvas = (page: Page) => page.locator("[data-viewer] canvas");

/** Share of drawn pixels that look blue (our tokens); high contrast swaps them for white and yellow. */
const tint = (page: Page) =>
  page.evaluate(() => {
    const source = document.querySelector<HTMLCanvasElement>("[data-viewer] canvas")!;
    const copy = document.createElement("canvas");
    copy.width = source.width;
    copy.height = source.height;
    const ctx = copy.getContext("2d")!;
    ctx.drawImage(source, 0, 0);
    const { data } = ctx.getImageData(0, 0, copy.width, copy.height);
    let drawn = 0;
    let blue = 0;
    for (let i = 0; i < data.length; i += 4) {
      if (data[i + 3] < 40) continue;
      drawn++;
      const [r, b] = [data[i], data[i + 2]];
      if (b > r + 20) blue++;
    }
    return { drawn, blue: blue / (drawn || 1) };
  });

test.describe("3D viewer: no scan on this computer", () => {
  test("another home on this computer has no scan: its page lists the steps", async ({ page }) => {
    await prepare(page);
    await open(page, "/homes/kitchen-test/viewer");
    await expect(page.getByRole("heading", { name: steps.title })).toBeVisible();
    await expect(page.locator("[data-viewer]")).toHaveCount(0);
  });

  test("lists the steps to scan your own room, and shows no viewer", async ({ page }) => {
    await prepare(page);
    await open(page, PAGE, { scan: false });
    await expect(page.getByRole("heading", { name: steps.title })).toBeVisible();
    await expect(page.locator("[data-no-scan] li")).toHaveCount(steps.items.length);
    await expect(page.getByText("make viewer")).toBeVisible();
    await expect(page.locator("[data-viewer]")).toHaveCount(0);
  });

  test("without JavaScript the steps are still there", async ({ browser }) => {
    const context = await browser.newContext({ javaScriptEnabled: false });
    const page = await context.newPage();
    await page.goto(PAGE);
    await expect(page.getByRole("heading", { name: steps.title })).toBeVisible();
    await expect(page.locator("[data-viewer]")).toHaveCount(0);
    await context.close();
  });

  test("the steps pass an automated WCAG 2.2 AA audit", async ({ page }) => {
    await prepare(page);
    await open(page, PAGE, { scan: false });
    await expect(page.getByRole("heading", { name: steps.title })).toBeVisible();
    const results = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa", "wcag22aa"]).analyze();
    expect(results.violations).toEqual([]);
  });
});

test.describe("3D viewer: your scan", () => {
  test("names the scan and says when it was made", async ({ page }) => {
    await prepare(page);
    await open(page, PAGE);
    await expect(page.getByRole("img", { name: s.alt })).toBeVisible();
    const caption = page.locator("figcaption");
    await expect(caption).toContainText(s.alt);
    await expect(caption).toContainText(meta.stats.captured);
  });

  test("loads the point cloud with its colours and confidence, and gathers it into the room", async ({ page }) => {
    await prepare(page);
    const sizes: Record<string, number> = {};
    page.on("response", async (r) => {
      const file = r.url().match(/local-scan\/[^/]+\/(\w+\.bin)$/)?.[1];
      if (file && r.ok()) sizes[file] = (await r.body()).byteLength;
    });
    await open(page, PAGE);
    await page.waitForFunction(() => document.querySelector<HTMLElement>("[data-viewer]")?.dataset.progress === "0");
    await formed(page);
    expect(sizes["points.bin"]).toBe(meta.count * 12);
    expect(sizes["conf.bin"]).toBe(meta.count);
    // colors.bin is gitignored: "Photo" is offered only when it was served
    const photo = page.getByRole("radio", { name: s.modes.photo });
    if (sizes["colors.bin"] === undefined) await expect(photo).toHaveCount(0);
    else {
      expect(sizes["colors.bin"]).toBe(meta.count * 3);
      await expect(photo).toBeVisible();
    }
    expect((await tint(page)).blue).toBeGreaterThan(0.5);
  });

  test("reduced motion shows the formed room at once, still", async ({ browser }) => {
    const context = await browser.newContext({ reducedMotion: "reduce" });
    const page = await context.newPage();
    await prepare(page);
    await open(page, PAGE);
    await formed(page);
    expect(await progress(page)).toBe("1");
    // nothing moves: two frames a moment apart are identical
    const a = await canvas(page).screenshot();
    await page.waitForTimeout(800);
    const b = await canvas(page).screenshot();
    expect(a.equals(b)).toBe(true);
    await context.close();
  });

  test.describe("colour modes and layers", () => {
    test.use({ reducedMotion: "reduce" }); // a still room, so only the layer change differs between frames

    test("photo colours replace the blue, and confidence greys it", async ({ page }) => {
      await prepare(page);
      await open(page, PAGE);
      await formed(page);
      const blueShare = async () => (await tint(page)).blue;
      // only the points: the grid, walls and pins are drawn in token colours too
      for (const layer of ["grid", "room", "things"] as const) await page.getByRole("checkbox", { name: s[layer] }).uncheck();
      const photo = page.getByRole("radio", { name: s.modes.photo });
      if (await photo.count()) {
        await photo.check();
        await expect(page.locator("[data-viewer]")).toHaveAttribute("data-mode", "photo");
        await expect.poll(blueShare).toBeLessThan(0.25);
      }
      await page.getByRole("radio", { name: s.modes.confidence }).check();
      await expect.poll(blueShare).toBeLessThan(0.05);
      await page.getByRole("radio", { name: s.modes.height }).check();
      await expect.poll(blueShare).toBeGreaterThan(0.5);
    });

    for (const layer of ["room", "things", "grid", "bands", "surfaces"] as const) {
      test(`the ${layer} layer changes the picture and can be switched back`, async ({ page }) => {
        await prepare(page);
        await open(page, PAGE);
        await formed(page);
        const before = await canvas(page).screenshot();
        const box = page.getByRole("checkbox", { name: s[layer] });
        const initial = await box.isChecked(); // room, things and the floor grid start on, the others off
        await box.setChecked(!initial);
        await expect.poll(async () => (await canvas(page).screenshot()).equals(before)).toBe(false);
        await box.setChecked(initial);
        await expect.poll(async () => (await canvas(page).screenshot()).equals(before)).toBe(true);
      });
    }
  });

  test("the room, the things and the floor grid are on by default, the other layers off", async ({ page }) => {
    await prepare(page);
    await open(page, PAGE);
    await formed(page);
    await expect(page.getByRole("checkbox", { name: s.room })).toBeChecked();
    await expect(page.getByRole("checkbox", { name: s.things })).toBeChecked();
    await expect(page.getByRole("checkbox", { name: s.grid })).toBeChecked();
    await expect(page.getByRole("checkbox", { name: s.bands })).not.toBeChecked();
    await expect(page.getByRole("checkbox", { name: s.surfaces })).not.toBeChecked();
  });

  test("three views: dots, the room model with a legend of kinds, and the measured surface", async ({ page }) => {
    await prepare(page);
    await open(page, PAGE);
    await formed(page);
    const viewer = page.locator("[data-viewer]");
    await expect(page.getByRole("radio", { name: s.views.dots })).toBeChecked();
    await expect(page.getByText(s.viewNotes.dots)).toBeVisible();

    await page.getByRole("radio", { name: s.views.model }).check();
    await expect(viewer).toHaveAttribute("data-view", "model");
    await expect(page.getByText(s.viewNotes.model)).toBeVisible();
    await expect(page.getByRole("list", { name: s.room }).getByRole("listitem")).toHaveText(["desk", "shelf"]);
    await expect(page.getByRole("radio", { name: s.modes.height })).toHaveCount(0); // point colours only apply to dots
    await expect.poll(async () => (await tint(page)).drawn).toBeGreaterThan(1000);

    await page.getByRole("radio", { name: s.views.surface }).check();
    await expect(viewer).toHaveAttribute("data-view", "surface");
    await expect(page.getByText(s.viewNotes.surface)).toBeVisible();
    await expect.poll(async () => (await tint(page)).drawn).toBeGreaterThan(1000);
  });

  test("lists everything Recall found; choosing one highlights its pin", async ({ page }) => {
    await prepare(page);
    await page.emulateMedia({ reducedMotion: "reduce" });
    await open(page, PAGE);
    await formed(page);
    const list = page.getByRole("region", { name: new RegExp(s.found.title) });
    const items = list.getByRole("button");
    await expect(items).toHaveCount(meta.objects.length);
    const first = meta.objects[0];
    await expect(items.first()).toContainText([first.color, first.label].filter(Boolean).join(" "));
    const before = await canvas(page).screenshot();
    await items.first().click();
    await expect(items.first()).toHaveAttribute("aria-pressed", "true");
    await expect.poll(async () => (await canvas(page).screenshot()).equals(before)).toBe(false);
    await items.first().click();
    await expect(items.first()).toHaveAttribute("aria-pressed", "false");
  });

  test("stats show the run's measured numbers", async ({ page }) => {
    await prepare(page);
    await open(page, PAGE);
    const stats = page.getByRole("region", { name: s.stats.label });
    await expect(stats.locator("[data-stat]")).toHaveText([
      `${s.stats.frames}${meta.stats.frames}`,
      `${s.stats.rebuild}${Math.round(meta.stats.total_s)}`,
      `${s.stats.sam}${meta.stats.sam_calls}`,
      `${s.stats.points}${Math.round(meta.count / 1000)}k`,
    ]);
  });

  test("lists the height bands and every flat surface the export found", async ({ page }) => {
    await prepare(page);
    await open(page, PAGE);
    await expect(page.locator("[data-band]")).toHaveText([
      `${s.bandNames.floor}under 0.3 m`,
      `${s.bandNames.knee}0.3 to 0.7 m`,
      `${s.bandNames.waist}0.7 to 1.1 m`,
      `${s.bandNames.chest}1.1 to 1.5 m`,
      `${s.bandNames.head}over 1.5 m`,
    ]);
    const rows = page.locator("[data-surface]");
    await expect(rows).toHaveCount(meta.surfaces.length);
    const first = meta.surfaces[0];
    await expect(rows.first()).toContainText(`${(first.max[0] - first.min[0]).toFixed(2)} × ${(first.max[1] - first.min[1]).toFixed(2)} m at ${first.z.toFixed(2)} m`);
  });

  test("high contrast redraws the room in its tokens (no blue left)", async ({ page }) => {
    await prepare(page, { a11y: { contrast: true } });
    await open(page, PAGE);
    await formed(page);
    await expect.poll(async () => (await tint(page)).blue).toBeLessThan(0.02);
    expect((await tint(page)).drawn).toBeGreaterThan(1000);
  });

  test("passes an automated WCAG 2.2 AA audit", async ({ page }) => {
    await prepare(page);
    await open(page, PAGE);
    await formed(page);
    const results = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa", "wcag22aa"]).analyze();
    expect(results.violations).toEqual([]);
  });
});
