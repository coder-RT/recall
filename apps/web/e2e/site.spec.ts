import { expect, test } from "@playwright/test";
import { en } from "../i18n/dictionaries/en";
import { site } from "../lib/site";
import { open, expectNoBrokenText, prepare } from "./helpers";

/** Page-wide: language, title, navigation, footer, the privacy note and the voice API's guards. */

test("is in English with the right title, and no unfilled text", async ({ page }) => {
  await prepare(page);
  await open(page, "/");
  await expect(page.locator("html")).toHaveAttribute("lang", "en");
  await expect(page).toHaveTitle(en.meta.title);
  await expectNoBrokenText(page);
});

test("every nav link has a section, and clicking one goes there", async ({ page }) => {
  await prepare(page);
  await open(page, "/");
  const nav = page.getByRole("navigation", { name: en.nav.sections });
  for (const link of en.nav.links) {
    await expect(nav.getByRole("link", { name: link.label })).toHaveAttribute("href", link.href);
    await expect(page.locator(link.href)).toBeAttached();
  }
  await nav.getByRole("link", { name: en.nav.links[3].label }).click(); // Models
  await expect(page.locator("#models")).toBeInViewport({ timeout: 5_000 });
});

test("a reload starts at the top, even after following a nav link", async ({ page }) => {
  await prepare(page);
  await open(page, "/#feed");
  await page.reload();
  await page.waitForFunction(() => document.documentElement.dataset.hydrated === "true");
  await page.waitForTimeout(800); // late re-measuring must not move it either
  expect(await page.evaluate(() => window.scrollY)).toBeLessThan(5);
  expect(new URL(page.url()).hash).toBe("");
});

test("opening a shared link to a section lands on that section", async ({ page }) => {
  await prepare(page);
  await open(page, "/#faq");
  await expect(page.getByRole("heading", { name: en.faq.title })).toBeInViewport({ timeout: 5_000 });
});

test("the first Tab reaches “Skip to content”, which jumps to the main content", async ({ page }) => {
  await prepare(page);
  await open(page, "/");
  await page.keyboard.press("Tab");
  const skip = page.getByRole("link", { name: en.nav.skip });
  await expect(skip).toBeFocused();
  await expect(skip).toHaveAttribute("href", "#main");
  await expect(page.locator("main#main")).toBeAttached();
});

test("the footer links to the code and says it is not affiliated with Meta", async ({ page }) => {
  await prepare(page);
  await open(page, "/");
  const footer = page.locator("footer");
  await expect(footer.getByRole("link", { name: en.footer.source })).toHaveAttribute("href", site.repo);
  await expect(footer).toContainText("Not affiliated with or endorsed by Meta");
  // 2009 layout: copyright left, links right, the author's profiles after the separator
  await expect(footer).toContainText(`${site.name} © 2026`);
  await expect(footer).toContainText(`Built by ${site.author.name}`);
  await expect(footer.getByRole("link", { name: en.footer.linkedin })).toHaveAttribute("href", site.author.linkedin);
  await expect(footer.getByRole("link", { name: en.footer.github, exact: true })).toHaveAttribute("href", site.author.github);
});

test.describe("privacy note", () => {
  test("appears for a new visitor, explains what is stored, and stays dismissed", async ({ page }) => {
    await prepare(page, { notice: true });
    await open(page, "/");
    const note = page.getByRole("region", { name: en.cookie.region });
    await expect(note).toBeVisible({ timeout: 4_000 });
    await expect(note).toContainText(en.cookie.title);
    await expect(note.getByRole("link", { name: en.cookie.privacy })).toHaveAttribute("href", "/privacy");
    await note.getByRole("button", { name: en.cookie.gotIt }).click();
    await expect(note).toBeHidden();
    await page.reload();
    await page.waitForTimeout(2_500);
    await expect(note).toBeHidden();
  });

  test("Escape dismisses it while focus is inside", async ({ page }) => {
    await prepare(page, { notice: true });
    await open(page, "/");
    const note = page.getByRole("region", { name: en.cookie.region });
    await note.getByRole("button", { name: en.cookie.gotIt }).focus();
    await page.keyboard.press("Escape");
    await expect(note).toBeHidden();
  });
});

test.describe("voice API", () => {
  // a browser always sends Origin on a POST; the route answers only this site's own pages
  const own = (baseURL?: string) => new URL(baseURL ?? "http://localhost:3000").origin;

  test("refuses calls that don't come from this site's pages", async ({ request, baseURL }) => {
    const wav = { "content-type": "audio/wav" };
    for (const headers of [wav, { ...wav, origin: "https://elsewhere.example" }]) {
      const res = await request.post("/api/voice/transcribe", { headers, data: Buffer.alloc(4000) });
      expect(res.status()).toBe(403);
      expect(await res.json()).toEqual({ error: "forbidden" });
    }
    const ok = await request.post("/api/voice/transcribe", { headers: { ...wav, origin: own(baseURL) }, data: Buffer.alloc(100) });
    expect(ok.status()).toBe(400); // past the check: too short, and no speech service was called
  });

  test("rejects anything that isn't a WAV", async ({ request, baseURL }) => {
    const res = await request.post("/api/voice/transcribe", { headers: { "content-type": "text/plain", origin: own(baseURL) }, data: "hello" });
    expect(res.status()).toBe(415);
    expect(await res.json()).toEqual({ error: "wrong_format" });
  });

  test("rejects an empty recording without calling the speech service", async ({ request, baseURL }) => {
    const res = await request.post("/api/voice/transcribe", { headers: { "content-type": "audio/wav", origin: own(baseURL) }, data: Buffer.alloc(100) });
    expect(res.status()).toBe(400);
    expect(await res.json()).toEqual({ error: "too_short" });
  });

  test("every error code it can return has a message for visitors", () => {
    for (const code of ["disabled", "not_configured", "forbidden", "wrong_format", "rate_limited", "daily_limit", "too_long", "too_short", "unreachable", "failed"]) {
      expect(en.ask.errors[code as keyof typeof en.ask.errors]).toBeTruthy();
    }
  });
});
