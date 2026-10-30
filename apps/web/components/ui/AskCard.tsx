"use client";

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useRef, useState } from "react";
import { useT } from "@/i18n/I18nProvider";
import { sayLine, stopSpeaking } from "@/lib/speech";
import { startRecording, type Recording } from "@/lib/wav-recorder";

// Illustrative answers (t.ask.questions); not real output.
const MAX_MS = 15_000;
type VoiceError = keyof ReturnType<typeof useT>["ask"]["errors"];

/** The old sign-up box, reborn as a question box. Pick a question, or ask it out loud. */
export function AskCard() {
  const t = useT();
  const QUESTIONS = t.ask.questions;
  // Recall's voice: the browser's speech synthesis in the "assistant" role
  const sayAnswer = (i: number | null) => void sayLine(i === null ? t.ask.noMatch : QUESTIONS[i].a, "assistant");
  const [picked, setPicked] = useState<number | null>(0);
  const [fallback, setFallback] = useState(false);
  const [voice, setVoice] = useState<"idle" | "listening" | "sending">("idle");
  const [heard, setHeard] = useState<string | null>(null);
  const [voiceError, setVoiceError] = useState<VoiceError | null>(null);
  const recording = useRef<Recording | null>(null);
  const autoStop = useRef(0);
  const answer = picked !== null ? QUESTIONS[picked].a : fallback ? t.ask.noMatch : null;

  // a recording in progress is thrown away if the card unmounts
  useEffect(() => () => recording.current?.cancel(), []);

  const answerHeard = (transcript: string) => {
    setHeard(transcript);
    const said = transcript.toLowerCase();
    // each question lists the words that point to it, e.g. "keys|key"
    const i = QUESTIONS.findIndex((item) => new RegExp(`\\b(${item.words})\\b`).test(said));
    setPicked(i >= 0 ? i : null);
    setFallback(i < 0);
    sayAnswer(i >= 0 ? i : null);
  };

  const finish = async () => {
    window.clearTimeout(autoStop.current);
    const rec = recording.current;
    if (!rec) return;
    recording.current = null;
    setVoice("sending");
    try {
      const wav = await rec.stop();
      const res = await fetch("/api/voice/transcribe", { method: "POST", headers: { "Content-Type": "audio/wav" }, body: wav });
      const data = (await res.json()) as { transcript?: string; error?: VoiceError };
      if (!res.ok) setVoiceError(data.error && data.error in t.ask.errors ? data.error : "failed");
      else if (!data.transcript) setVoiceError("empty");
      else answerHeard(data.transcript);
    } catch {
      setVoiceError("unreachable");
    } finally {
      setVoice("idle");
    }
  };

  const toggleVoice = async () => {
    if (voice === "listening") return finish();
    if (voice === "sending") return;
    setVoiceError(null);
    stopSpeaking();
    try {
      recording.current = await startRecording();
      setVoice("listening");
      autoStop.current = window.setTimeout(finish, MAX_MS);
    } catch {
      setVoiceError("microphone");
    }
  };

  return (
    <div id="ask" className="card w-full max-w-md scroll-mt-28 p-6 sm:p-7">
      <h2 className="font-serif text-3xl font-bold text-ink">{t.ask.title}</h2>
      <p className="mt-1 font-classic text-[0.95rem] text-muted">{t.ask.subtitle}</p>

      <fieldset className="mt-5">
        <legend className="mb-2 font-classic text-sm font-bold text-ink">{t.ask.pick}</legend>
        <div className="grid gap-2">
          {QUESTIONS.map((item, i) => (
            <button
              key={item.q}
              type="button"
              aria-pressed={picked === i}
              onClick={() => {
                setPicked(i);
                setFallback(false);
                setHeard(null);
              }}
              className={`min-h-11 rounded-lg border px-3 py-2 text-left text-[1.02rem] transition-colors ${
                picked === i
                  ? "border-fb-blue bg-fb-blue-pale font-bold text-fb-blue-dark"
                  : "border-fb-line bg-white text-ink hover:border-fb-blue"
              }`}
            >
              “{item.q}”
            </button>
          ))}
        </div>
      </fieldset>

      <div className="mt-3">
        <button
          type="button"
          onClick={toggleVoice}
          aria-pressed={voice === "listening"}
          disabled={voice === "sending"}
          className={`btn w-full ${voice === "listening" ? "btn-green" : "btn-ghost"}`}
        >
          <motion.span
            aria-hidden="true"
            animate={voice === "listening" ? { scale: [1, 1.25, 1] } : { scale: 1 }}
            transition={voice === "listening" ? { repeat: Infinity, duration: 1 } : { duration: 0.2 }}
          >
            🎙️
          </motion.span>
          {voice === "listening" ? t.ask.listening : voice === "sending" ? t.ask.working : t.ask.voice}
        </button>
        <p className="mt-1.5 font-classic text-xs text-muted">
          {t.ask.voiceNote}
        </p>
      </div>

      <div aria-live="polite" className="mt-4 min-h-28">
        {voiceError && <p className="mb-2 rounded-lg bg-fb-blue-pale px-3 py-2 text-ink">{t.ask.errors[voiceError]}</p>}
        {heard && (
          <p className="mb-2 text-sm text-muted">
            {t.ask.youAsked} <span className="font-bold text-ink">“{heard}”</span>
          </p>
        )}
        <AnimatePresence mode="wait">
          {answer && (
            <motion.figure
              key={answer}
              initial={{ opacity: 0, y: 12, scale: 0.98 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ type: "spring", stiffness: 380, damping: 30 }}
              className="rounded-xl bg-fb-grey p-4"
            >
              <figcaption className="mb-1 flex items-center justify-between gap-2 text-xs font-bold uppercase tracking-wide text-muted">
                <span className="flex items-center gap-2">
                  <span aria-hidden="true">🔊</span> {t.ask.says}
                </span>
                <button
                  type="button"
                  onClick={() => sayAnswer(picked)}
                  className="min-h-11 rounded-md px-2 normal-case tracking-normal text-fb-blue-dark hover:underline"
                >
                  {t.ask.hear}
                </button>
              </figcaption>
              <blockquote className="text-lg leading-snug text-ink">{answer}</blockquote>
            </motion.figure>
          )}
        </AnimatePresence>
      </div>

      <p className="mt-3 border-t border-fb-line pt-3 font-classic text-xs text-muted">
        {t.ask.disclaimer}
      </p>
    </div>
  );
}
