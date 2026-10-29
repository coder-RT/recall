"use client";

/**
 * Speech output: the browser's own speech synthesis, nothing else (no speech model runs; Muse Voice
 * only does speech-to-text). Roles: a narrator, an "assistant" voice for Recall's own lines, and a
 * male and a female character voice. Quality depends on the device; we pick the most natural voice
 * available. Call only after a user action.
 */

export type VoiceRole = "narrator" | "assistant" | "male" | "female";

// Most natural-sounding voices first, by name fragment (Chrome, Safari/macOS, Edge/Windows).
const PREFERRED = ["Google US English", "Samantha", "Ava", "Aria Online", "Jenny Online", "Natural", "Google UK English Female", "Daniel"];
// Speech voices don't report gender, so the character voices go by well-known names.
const MALE = ["Google UK English Male", "Daniel", "Alex", "Aaron", "Arthur", "Tom", "Fred", "Guy Online", "Andrew Online", "Microsoft David", "Microsoft Mark"];
const FEMALE = ["Samantha", "Google UK English Female", "Ava", "Karen", "Moira", "Victoria", "Jenny Online", "Aria Online", "Microsoft Zira"];

const synth = () => (typeof window !== "undefined" && "speechSynthesis" in window ? window.speechSynthesis : null);

function pickVoices(): Record<VoiceRole, SpeechSynthesisVoice | null> {
  // voices for the page's language (<html lang>, set from i18n/config)
  const lang = (document.documentElement.lang || "en").toLowerCase().split("-")[0];
  const voices = synth()?.getVoices().filter((v) => v.lang.toLowerCase().startsWith(lang)) ?? [];
  const ranked = [...voices].sort((a, b) => rank(a) - rank(b));
  const narrator = ranked[0] ?? null;
  // Recall gets a different voice when there is one, so its answers stand apart
  const assistant = ranked.find((v) => v !== narrator) ?? narrator;
  const byName = (names: string[]) => names.map((n) => voices.find((v) => v.name.includes(n))).find(Boolean) ?? null;
  return { narrator, assistant, male: byName(MALE) ?? narrator, female: byName(FEMALE) ?? narrator };
}

function rank(v: SpeechSynthesisVoice) {
  const i = PREFERRED.findIndex((name) => v.name.includes(name));
  return i < 0 ? PREFERRED.length + (v.lang === "en-US" ? 0 : 1) : i;
}

let voices: Record<VoiceRole, SpeechSynthesisVoice | null> = { narrator: null, assistant: null, male: null, female: null };
if (synth()) {
  voices = pickVoices();
  // voices load asynchronously in Chrome
  synth()!.addEventListener?.("voiceschanged", () => (voices = pickVoices()));
}

export const canSpeak = () => synth() !== null;

// bumped by every new request, so an older long reading stops between sentences
let run = 0;

/** Speak a line; resolves when it ends (or is cancelled). Cancels anything already speaking. */
export function speak(text: string, options: { voice?: VoiceRole } = {}): Promise<void> {
  run++;
  return say(text, options);
}

/**
 * Speak a longer passage sentence by sentence (some voices cut off long utterances).
 * Stops early when anything else is spoken or stopSpeaking() is called.
 */
export async function speakLong(text: string, options: { voice?: VoiceRole } = {}) {
  const id = ++run;
  const sentences = text.match(/[^.!?]+[.!?]*\s*/g) ?? [text];
  for (const sentence of sentences) {
    if (id !== run) return;
    await say(sentence, options);
  }
}

function say(text: string, { voice = "narrator" }: { voice?: VoiceRole }): Promise<void> {
  const s = synth();
  if (!s || !text.trim()) return Promise.resolve();
  s.cancel();
  return new Promise((resolve) => {
    const u = new SpeechSynthesisUtterance(text);
    const v = voices[voice];
    if (v) u.voice = v;
    u.lang = v?.lang ?? (document.documentElement.lang || "en");
    u.rate = voice === "assistant" ? 1.04 : 0.98;
    u.pitch = voice === "assistant" ? 1.08 : 1;
    u.onend = () => resolve();
    u.onerror = () => resolve();
    s.speak(u);
  });
}

export function stopSpeaking() {
  run++;
  synth()?.cancel();
}

/** Say one of the site's fixed lines in the given voice; `long` reads it sentence by sentence. */
export function sayLine(text: string, voice: VoiceRole, { long = false } = {}): Promise<void> {
  return long ? speakLong(text, { voice }) : speak(text, { voice });
}

/** The text a person would hear for an element: its aria-label, else its visible text. */
export function textOf(el: Element) {
  return (el.getAttribute("aria-label") || (el as HTMLElement).innerText || el.textContent || "").replace(/\s+/g, " ").trim();
}
