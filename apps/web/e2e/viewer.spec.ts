import fs from "node:fs";
import path from "node:path";
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";
import { en } from "../i18n/dictionaries/en";
import { testFiles, testMeta as meta } from "./fixtures/test-room";
import { open as openPage, prepare } from "./helpers";

/**
 * The 3D viewer at /homes/<home>/viewer: that home's export on this computer (public/local-scan/<home>/), or the steps.
 * The tests serve a made-up room (fixtures/test-room.ts) instead of anything on disk, so they never see a real home.
 */

const PAGE = "/homes/my-home/viewer";  // a home of your own, exported on this computer (flat is the published scan)
const s = en.app.viewer.scan;
const steps = en.app.viewer.steps;

/** Serve the made-up room as this computer's export, or say there is none. */
async function serveScan(page: Page, present: boolean) {
  await page.route("**/local-scan/**", (route) => {
    const url = new URL(route.request().url());
    if (!url.pathname.startsWith("/local-scan/my-home/")) return route.fulfill({ status: 404, body: "" }); // other homes: none
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

/** Pixels within a few steps of one exact colour (the arrows use unlit materials, so they keep their token). */
const exact = (page: Page, hex: string) =>
  page.evaluate((hex) => {
    const want = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
    const source = document.querySelector<HTMLCanvasElement>("[data-viewer] canvas")!;
    const copy = document.createElement("canvas");
    copy.width = source.width;
    copy.height = source.height;
    const ctx = copy.getContext("2d")!;
    ctx.drawImage(source, 0, 0);
    const { data } = ctx.getImageData(0, 0, copy.width, copy.height);
    let n = 0;
    for (let i = 0; i < data.length; i += 4) {
      if (data[i + 3] > 200 && want.every((w, c) => Math.abs(data[i + c] - w) <= 6)) n++;
    }
    return n;
  }, hex);

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
    const caption = page.locator("figure", { has: page.locator("[data-viewer]") }).locator("figcaption");
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
    const photo = page.getByRole("radio", { name: s.modes.photo, exact: true });
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
      await page.getByRole("button", { name: s.more }).click();
      await page.getByRole("checkbox", { name: s.axes }).uncheck();  // the axes are token blue as well
      const photo = page.getByRole("radio", { name: s.modes.photo, exact: true });
      if (await photo.count()) {
        await photo.check();
        await expect(page.locator("[data-viewer]")).toHaveAttribute("data-mode", "photo");
        await expect.poll(blueShare).toBeLessThan(0.25);
      }
      await page.getByRole("radio", { name: s.modes.confidence, exact: true }).check();
      await expect.poll(blueShare).toBeLessThan(0.05);
      await page.getByRole("radio", { name: s.modes.height, exact: true }).check();
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
    await expect(page.getByRole("radio", { name: s.modes.height, exact: true })).toHaveCount(0); // point colours only apply to dots
    await expect.poll(async () => (await tint(page)).drawn).toBeGreaterThan(1000);

    await page.getByRole("radio", { name: s.views.surface }).check();
    await expect(viewer).toHaveAttribute("data-view", "surface");
    await expect(page.getByText(s.viewNotes.surface)).toBeVisible();
    await expect.poll(async () => (await tint(page)).drawn).toBeGreaterThan(1000);
  });

  test("the photo room and the architect's regenerated room draw, and the drawings are listed", async ({ page }) => {
    await prepare(page);
    await open(page, PAGE);
    await formed(page);
    const viewer = page.locator("[data-viewer]");
    for (const view of ["photo", "architect"] as const) {
      await page.getByRole("radio", { name: new RegExp(`^${s.views[view]}`) }).check();
      await expect(viewer).toHaveAttribute("data-view", view);
      await expect(page.getByText(s.viewNotes[view])).toBeVisible();
      await expect.poll(async () => (await tint(page)).drawn).toBeGreaterThan(1000);
    }
    const sheets = page.getByRole("region", { name: new RegExp(s.drawings.title) });
    await expect(sheets.locator(`img[alt="${meta.drawings[0].summary}"]`)).toBeVisible();
    await expect(sheets.getByRole("link", { name: "Download A1.1" })).toHaveAttribute("href", /sheet-a1-1\.svg$/);
    // a sheet enlarges in place, never in a new tab, and Escape puts it back with focus on its card
    const enlarge = sheets.getByRole("button", { name: "Enlarge A1.1" });
    await enlarge.click();
    const dialog = page.getByRole("dialog", { name: /A1\.1/ });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByRole("button", { name: s.drawings.close })).toBeFocused();
    expect(page.context().pages()).toHaveLength(1);
    await page.keyboard.press("Escape");
    await expect(dialog).toBeHidden();
    await expect(enlarge).toBeFocused();
  });

  test("Facebook-blue arrows point down at the things in every room view; the chosen one turns dark blue", async ({ page }) => {
    await prepare(page);
    await page.emulateMedia({ reducedMotion: "reduce" });
    await open(page, PAGE);
    await formed(page);
    for (const view of ["model", "photo", "architect", "surface"] as const) {
      await page.getByRole("radio", { name: new RegExp(`^${s.views[view]}`) }).check();
      await expect.poll(() => exact(page, "#3b5998"), { message: view }).toBeGreaterThan(40);
    }
    const dark = await exact(page, "#29487d");
    await page.getByRole("region", { name: new RegExp(s.found.title) }).locator("li button").first().click();
    await expect.poll(() => exact(page, "#29487d")).toBeGreaterThan(dark + 40);
  });

  test("lists everything Recall found; choosing one highlights its arrow", async ({ page }) => {
    await prepare(page);
    await page.emulateMedia({ reducedMotion: "reduce" });
    await open(page, PAGE);
    await formed(page);
    const list = page.getByRole("region", { name: new RegExp(s.found.title) });
    const items = list.locator("li button");
    await expect(items).toHaveCount(meta.objects.length);
    // grouped by room, like the app: the group folds closed and open again
    const group = list.getByRole("button", { name: new RegExp(`^${(meta.room as { name?: string }).name ?? s.found.thisRoom} · ${meta.objects.length}`) });
    await expect(group).toHaveAttribute("aria-expanded", "true");
    await group.click();
    await expect(group).toHaveAttribute("aria-expanded", "false");
    await expect(items).toHaveCount(0);
    await group.click();
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


/** The published real scan at /homes/flat/viewer: served from /real-scan/flat/; the tests swap in the made-up room. */
async function openPublic(page: Page, path = "/homes/flat/viewer") {
  await page.route("**/real-scan/flat/**", (route) => {
    const file = new URL(route.request().url()).pathname.split("/").pop() ?? "";
    if (file === "meta.json") {
      const m = JSON.parse(testFiles["meta.json"].toString());
      m.public = true;
      m.objects = m.objects.map((o: object, i: number) => ({ ...o, photos: i === 0 ? 1 : 4 }));
      return route.fulfill({ status: 200, body: JSON.stringify(m) });
    }
    const body = testFiles[file];
    return body ? route.fulfill({ status: 200, body }) : route.fulfill({ status: 404, body: "" });
  });
  await openPage(page, path);
}

test.describe("3D viewer: the published real scan", () => {
  const story = en.app.viewer.story;
  const real = en.app.viewer.real;

  test("says it is a real scan, not a simulation, with big section headings", async ({ page }) => {
    await prepare(page);
    await openPublic(page);
    await expect(page.locator("[data-real-badge]")).toHaveText(real.badge);
    await expect(page.getByRole("heading", { level: 1, name: real.title })).toBeVisible();
    for (const title of [story.models.title, story.measured.title, story.robots.title, story.how.title]) {
      const h = page.getByRole("heading", { level: 2, name: title });
      await expect(h).toBeVisible();
      expect(parseFloat(await h.evaluate((e) => getComputedStyle(e).fontSize))).toBeGreaterThanOrEqual(30);
    }
  });

  test("names the Meta model behind each part, and lists what SAM 3.1 found with its photos", async ({ page }) => {
    await prepare(page);
    await openPublic(page);
    const models = page.locator("[data-story=models-title] tbody tr");
    await expect(models).toHaveCount(story.models.rows.length);
    await expect(models.first()).toContainText("MapAnything");
    const found = page.locator("[data-story=found-title] tbody tr");
    await expect(found).toHaveCount(meta.objects.length);
    await expect(found.first()).toContainText(story.found.waits);  // seen in one photo: waits for the owner
    await expect(found.nth(1)).toContainText(story.found.told);
  });

  test("lists Recall's agents and the Meta model each runs, then the robot files to download", async ({ page }) => {
    await prepare(page);
    await openPublic(page);
    const agents = page.locator("[data-story=agents-title] tbody tr");
    await expect(agents).toHaveCount(story.agents.rows.length);
    await expect(agents.first()).toContainText("Muse Spark Open");
    for (const f of ["map.yaml", "map.pgm", "objects.json", "room.json", "cloud.ply", "README.md"]) {
      await expect(page.locator(`[data-robot-file="${f}"]`)).toHaveAttribute("href", `/real-scan/flat/robot/${f}`);
    }
    await expect(page.locator("[data-robot-zip]")).toHaveAttribute("href", "/real-scan/flat/robot/recall-living-room.zip");
    const note = page.locator("[data-privacy-note]");
    await expect(note.getByRole("heading", { name: story.privacyTitle })).toBeVisible();
    await expect(note).toContainText(story.privacyNever);
  });

  test("the measured numbers are computed from the scan itself", async ({ page }) => {
    await prepare(page);
    await openPublic(page);
    const rows = page.locator("[data-story=measured-title] tbody tr");
    const row = (label: string) => rows.filter({ has: page.getByRole("rowheader", { name: label, exact: true }) });
    // the made-up room's floor is 4 × 3 m
    await expect(row(story.measured.floor)).toContainText("12.0 m²");
    await expect(row(story.measured.perimeter)).toContainText("14.0 m");
    await expect(row(story.measured.size)).toContainText("4.00 × 3.00 m");
    await expect(row(story.measured.waiting)).toContainText("1");  // the one seen in a single photo
  });

  test("Dots and Architect are marked as the best views, and More options holds each view's settings", async ({ page }) => {
    await prepare(page);
    await openPublic(page);
    const best = page.locator("[data-best]");
    await expect(best).toHaveCount(2);
    await expect(best.first()).toContainText(s.best);
    await page.getByRole("button", { name: s.more }).click();
    const more = page.locator("[data-more-options]");
    for (const p of Object.values(s.presets)) await expect(more.getByRole("radio", { name: p, exact: true })).toBeVisible();
    await expect(more.getByRole("checkbox", { name: s.axes })).toBeChecked();
    await page.getByRole("radio", { name: new RegExp(`^${s.views.architect}`) }).check();
    await expect(more.getByRole("slider", { name: s.cut })).toBeVisible();
    await page.getByRole("radio", { name: new RegExp(`^${s.views.model}`) }).check();
    await expect(more.getByRole("slider", { name: s.wallOpacity })).toBeVisible();
  });

  test("choosing Surface selects the 3D camera, the axes and the wireframe", async ({ page }) => {
    await prepare(page);
    await openPublic(page);
    await page.getByRole("radio", { name: new RegExp(`^${s.views.surface}`) }).check();
    await page.getByRole("button", { name: s.more }).click();
    const more = page.locator("[data-more-options]");
    await expect(more.getByRole("radio", { name: s.presets.iso, exact: true })).toBeChecked();
    await expect(more.getByRole("checkbox", { name: s.axes })).toBeChecked();
    await expect(more.getByRole("checkbox", { name: s.wireframe })).toBeChecked();
  });

  test("choosing Architect selects the Top camera and a 1.5 m wall cut", async ({ page }) => {
    await prepare(page);
    await openPublic(page);
    await page.getByRole("radio", { name: new RegExp(`^${s.views.architect}`) }).check();
    await page.getByRole("button", { name: s.more }).click();
    const more = page.locator("[data-more-options]");
    await expect(more.getByRole("radio", { name: s.presets.top, exact: true })).toBeChecked();
    await expect(more.getByRole("slider", { name: s.cut })).toHaveValue("1.5");
  });

  test("the old demo address opens the real scan", async ({ page }) => {
    await prepare(page);
    await openPublic(page, "/homes/demo-flat/viewer");
    await expect(page).toHaveURL(/\/homes\/flat\/viewer$/);
    await expect(page.locator("[data-real-badge]")).toBeVisible();
  });

  test("passes an automated WCAG 2.2 AA audit", async ({ page }) => {
    await prepare(page);
    await openPublic(page);
    await formed(page);
    const results = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa", "wcag22aa"]).analyze();
    expect(results.violations).toEqual([]);
  });
});

test("the published scan holds geometry only: no photo, no photo colours", () => {
  const dir = path.join(__dirname, "..", "public", "real-scan");
  if (!fs.existsSync(dir)) return;  // nothing published yet, so nothing to leak
  for (const home of fs.readdirSync(dir)) {
    const files = fs.readdirSync(path.join(dir, home));
    expect(files.filter((f) => f === "colors.bin" || f.startsWith("photo") || /\.(jpe?g|png|heic|mov|mp4)$/i.test(f))).toEqual([]);
    const m = JSON.parse(fs.readFileSync(path.join(dir, home, "meta.json"), "utf8"));
    expect(m.public).toBe(true);
    expect(m.photo).toBeUndefined();
  }
});

test("the published robot files hold geometry and labels only: no paths, keys or photos", () => {
  const dir = path.join(__dirname, "..", "public", "real-scan", "flat", "robot");
  if (!fs.existsSync(dir)) return;
  for (const f of fs.readdirSync(dir)) {
    expect(f).not.toMatch(/\.(jpe?g|png|heic|mov|mp4)$/i);
    if (/\.(json|yaml|md)$/.test(f)) {
      const text = fs.readFileSync(path.join(dir, f), "utf8");
      expect(text, f).not.toMatch(/\/Users\/|\/home\/[a-z]|[A-Z_]+_KEY|Bearer |token/i);
    }
  }
  const objects = JSON.parse(fs.readFileSync(path.join(dir, "objects.json"), "utf8"));
  for (const o of objects.objects) expect(o.aliases, "never the owner's own names").toEqual([]);
});

test("the site's install guide is the repo's docs/install/README.md, word for word", () => {
  const root = path.join(__dirname, "..", "..", "..");
  const guide = fs.readFileSync(path.join(root, "docs", "install", "README.md"), "utf8");
  const served = fs.readFileSync(path.join(__dirname, "..", "public", "INSTALL.md"), "utf8");
  expect(served).toBe(guide);
  expect(fs.readFileSync(path.join(root, "INSTALL.md"), "utf8")).toContain("docs/install/README.md");
});

test("the public install guide carries no keys, no home paths and no private links", () => {
  const root = path.join(__dirname, "..", "..", "..");
  const guide = fs.readFileSync(path.join(root, "docs", "install", "README.md"), "utf8");
  expect(guide).not.toMatch(/\/Users\/|\/home\/[a-z]|docs\/private/);
  // every key line is empty: KEY= followed by spaces and a comment, never a value
  for (const line of guide.split("\n").filter((l) => /^[A-Z_]*KEY=/.test(l))) expect(line).toMatch(/^[A-Z_]*KEY=\s*(#|$)/);
  expect(guide).not.toMatch(/sk-[A-Za-z0-9]{10}|re_[A-Za-z0-9]{10}|[0-9a-f]{40,}/);
});
