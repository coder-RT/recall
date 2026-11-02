/**
 * The contact form's rules, kept apart from the route so each is tested on its own (e2e/lib.spec.ts).
 * The recipient address is a server env var (CONTACT_TO) and never reaches the page.
 */

import { z } from "zod";

/** Faster than this, a person can't have typed a message: a bot filled the form. */
export const MIN_FILL_MS = 3_000;

export const contactMessage = z.object({
  name: z.string().trim().min(1).max(80),
  email: z.email().max(200),
  message: z.string().trim().min(10).max(2_000),
  // the honeypot: hidden from people and screen readers, so only a bot fills it
  website: z.string().max(200).default(""),
  startedAt: z.number().int().nonnegative(),
});

export type ContactMessage = z.infer<typeof contactMessage>;

/** CONTACT_FORM=off turns the form off at once, without a deploy. */
export function contactDisabled(env: Record<string, string | undefined>): boolean {
  return (env.CONTACT_FORM ?? "").toLowerCase() === "off";
}

/** A filled honeypot, or a form sent too soon after it appeared. */
export function looksAutomated(msg: ContactMessage, now = Date.now()): boolean {
  return msg.website.trim() !== "" || now - msg.startedAt < MIN_FILL_MS;
}

/** The email's subject: the sender's name on one line, so it can't add headers. */
export function subjectFor(name: string): string {
  return `Recall site: ${name.replace(/[\r\n]+/g, " ").trim()}`;
}
