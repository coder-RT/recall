"use client";

import { useEffect, useId, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { format, getDictionary } from "@/i18n";
import { gsap, MOTION_OK, SplitText, useGSAP } from "@/lib/gsap";
import { useMotionPrefs } from "@/lib/motion-prefs";
import { canSpeak, sayLine, stopSpeaking } from "@/lib/speech";
import type { Walk } from "./Layers";
import { type ScanMeta, viewerStrings } from "./LocalScan";
import { RoomViewer } from "./RoomViewer";

/** One recorded question: the Guide's answer and, when it names one thing, the walk to it (walks.json, `make demo-walks`). */
export interface WalkItem {
  question: string;
  answer: string;
  grounded: boolean;
  model: string;
  label?: string;
  /** the thing, in the viewer's frame */
  target?: number[];
  mode?: "route" | "landmarks";
  steps?: { clock: number; metres: number; say: string }[];
  arrive?: string;
  /** floor points from where the scan began to the thing */
  path?: [number, number][];
  /** several alike were found: the answer asks which one, so there is no walk yet */
  asks_which?: boolean;
}

export interface Walks {
  label: string;
  recorded_at: string;
  captured_at: string;
  room: string;
  walks: WalkItem[];
}

const t = getDictionary().app.demo;

/** The thing's arrow in the viewer: the one with this label nearest the walk's target. */
function thingIndex(meta: ScanMeta | null, item: WalkItem): number | null {
  if (!meta || !item.target || !item.label) return null;
  const [x, y] = item.target;
  let best: number | null = null;
  let bestD = Infinity;
  for (const [i, o] of meta.objects.entries()) {
    const d = Math.hypot(o.at[0] - x, o.at[1] - y);
    if (o.label === item.label && d < bestD) {
      best = i;
      bestD = d;
    }
  }
  return best;
}

/** A small clock face with its hand on the step's hour (12 is straight ahead). */
function Clock({ hour }: { hour: number }) {
  return (
    <svg viewBox="0 0 40 40" aria-hidden className="size-10 shrink-0">
      <circle cx="20" cy="20" r="17" fill="white" stroke="currentColor" strokeWidth="2.5" />
      <circle cx="20" cy="5.5" r="1.8" fill="currentColor" />
      <line data-hand x1="20" y1="20" x2="20" y2="8" stroke="currentColor" strokeWidth="3" strokeLinecap="round" transform={`rotate(${(hour % 12) * 30} 20 20)`} />
      <circle cx="20" cy="20" r="2.5" fill="currentColor" />
    </svg>
  );
}

/**
 * Ask, then walk: pick a recorded question, read (or hear) Recall's answer, and watch the walk: GSAP writes the answer
 * in word by word, draws the route on the floor of the 3D room and brings in each spoken step as the route reaches it.
 * Everything is in the page's HTML first, so it reads the same without JavaScript or with motion reduced.
 */
export function WalkDemo({ walks, src }: { walks: Walks; src: string }) {
  const id = useId();
  const root = useRef<HTMLDivElement>(null);
  const { reduced } = useMotionPrefs();
  const [chosen, setChosen] = useState(0);
  const [replays, setReplays] = useState(0);
  const [meta, setMeta] = useState<ScanMeta | null>(null);
  const [speaking, setSpeaking] = useState(false);
  // speech synthesis exists only in the browser: the server (and the first render) draws no Hear button
  const speech = useSyncExternalStore(noSubscribe, canSpeak, () => false);
  const item = walks.walks[chosen];

  useEffect(() => {
    let cancelled = false;
    fetch(`${src}/meta.json`)
      .then((r) => (r.ok ? r.json() : null))
      .catch(() => null)
      .then((m) => !cancelled && setMeta(m));
    return () => {
      cancelled = true;
    };
  }, [src]);

  // a new box per question (and per replay): the route redraws from its start; full when motion is reduced
  const walk: Walk | null = useMemo(
    () => (item.path && item.path.length > 1 ? { path: item.path, progress: { value: 1 } } : null),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- a replay asks for a fresh box on purpose
    [item, replays],
  );
  const selected = thingIndex(meta, item);

  useGSAP(
    () => {
      const el = root.current;
      if (reduced || !window.matchMedia(MOTION_OK).matches) {
        if (el) el.dataset.played = "true";
        return;
      }
      if (el) el.dataset.played = "false";
      const steps = gsap.utils.toArray<HTMLElement>("[data-walk-step]");
      const words = SplitText.create("[data-answer-text]", { type: "words", aria: "none" });
      const tl = gsap.timeline({
        defaults: { ease: "power2.out" },
        onComplete: () => {
          if (el) el.dataset.played = "true";
        },
      });
      tl.from(words.words, { opacity: 0, y: 6, duration: 0.35, stagger: 0.035 });
      if (walk && item.steps) {
        // the route draws at walking pace on screen; each step arrives when the route reaches its start
        const metres = item.steps.map((s) => Math.max(s.metres, 0.2));
        const total = metres.reduce((a, b) => a + b, 0);
        const span = Math.min(4, 0.9 + total * 0.45);
        const at = tl.duration();
        tl.fromTo(walk.progress, { value: 0 }, { value: 1, duration: span, ease: "none", immediateRender: true }, at);
        let done = 0;
        steps.forEach((el, i) => {
          const start = at + (span * done) / total;
          tl.from(el, { opacity: 0, x: -14, duration: 0.4 }, start);
          tl.from(el.querySelector("[data-hand]"), { rotation: 0, svgOrigin: "20 20", duration: 0.5, ease: "back.out(2)" }, start);
          done += metres[i] ?? 0;
        });
        tl.from("[data-walk-arrive]", { opacity: 0, y: 8, duration: 0.4 }, at + span);
      } else {
        tl.from("[data-walk-note]", { opacity: 0, y: 8, duration: 0.4 });
      }
      return () => {
        words.revert();
        if (walk) gsap.set(walk.progress, { value: 1 });
      };
    },
    { scope: root, dependencies: [walk, reduced], revertOnUpdate: true },
  );

  useEffect(() => () => stopSpeaking(), []);
  const hear = async () => {
    if (speaking) {
      stopSpeaking();
      setSpeaking(false);
      return;
    }
    setSpeaking(true);
    const lines = [item.answer, ...(item.steps ? [t.start, ...item.steps.map((s) => s.say), item.arrive ?? ""] : [])].filter(Boolean);
    await sayLine(lines.join(" "), "assistant", { long: true });
    setSpeaking(false);
  };

  return (
    <div ref={root} className="mt-8 grid gap-6 lg:grid-cols-[1.35fr_1fr]" data-walk-demo>
      <div className="card self-start overflow-hidden">
        {meta ? (
          <RoomViewer
            src={src}
            bounds={meta.bounds}
            surfaces={meta.surfaces}
            room={meta.room}
            furniture={meta.furniture}
            things={meta.objects}
            selected={selected}
            hasMesh={Boolean(meta.mesh)}
            hasArchitect={Boolean(meta.architect)}
            walk={walk}
            start={{ view: "architect", preset: "top", distance: 1.45, spin: false }}
            t={{ ...viewerStrings(), label: t.viewerAlt }}
          />
        ) : (
          <p className="grid aspect-[4/3] place-items-center text-sm text-muted">{viewerStrings().loading}</p>
        )}
        <p className="border-t border-fb-line px-4 py-2 text-sm text-muted">{t.legend}</p>
      </div>

      <div className="flex flex-col gap-5">
        <fieldset className="card p-5">
          <legend className="sr-only">{t.ask}</legend>
          <p aria-hidden className="text-sm font-bold text-ink">
            {t.ask}
          </p>
          <div className="mt-3 flex flex-wrap gap-2">
            {walks.walks.map((w, i) => (
              <label
                key={w.question}
                className="flex min-h-11 cursor-pointer items-center rounded-full border border-fb-line bg-white px-3.5 text-sm text-ink has-checked:border-fb-blue has-checked:bg-fb-blue-pale has-checked:font-semibold has-focus-visible:outline-2 has-focus-visible:outline-fb-blue"
              >
                <input
                  type="radio"
                  name={`${id}-question`}
                  value={i}
                  checked={chosen === i}
                  onChange={() => {
                    stopSpeaking();
                    setSpeaking(false);
                    setChosen(i);
                  }}
                  className="sr-only"
                  data-question
                />
                {w.question}
              </label>
            ))}
          </div>
        </fieldset>

        <section aria-labelledby={`${id}-answer`} aria-live="polite" className="card p-5" data-answer>
          <p className="text-sm text-muted">
            {t.youAsked} <span className="font-semibold text-ink">“{item.question}”</span>
          </p>
          <h2 id={`${id}-answer`} className="mt-3 text-sm font-bold text-ink">
            {t.answer}
          </h2>
          {/* screen readers get the sentence whole; the copy on screen is split into words for the animation */}
          <p className="sr-only">{item.answer}</p>
          <p key={`${chosen}-${replays}`} aria-hidden data-answer-text className="mt-1 text-xl font-semibold leading-snug text-fb-blue-dark">
            {item.answer}
          </p>
          <div className="mt-4 flex flex-wrap gap-3">
            {speech && (
              <button type="button" onClick={hear} className="btn btn-ghost min-h-11" aria-pressed={speaking} data-hear>
                {speaking ? t.stop : t.hear}
              </button>
            )}
            {walk && (
              <button type="button" onClick={() => setReplays((n) => n + 1)} className="btn btn-ghost min-h-11" data-replay>
                {t.replay}
              </button>
            )}
          </div>
        </section>

        <section aria-labelledby={`${id}-walk`} className="card p-5" data-walk>
          <h2 id={`${id}-walk`} className="text-sm font-bold text-ink">
            {t.walkTitle}
          </h2>
          {item.steps && item.path ? (
            <ol className="mt-3 grid gap-2.5" key={`${chosen}-${replays}`}>
              <li className="text-base text-muted">{t.start}</li>
              {item.steps.map((s, i) => (
                <li key={i} data-walk-step className="flex items-center gap-3 text-lg font-semibold text-ink">
                  <span className="text-fb-blue-dark">
                    <Clock hour={s.clock} />
                  </span>
                  {s.say}
                </li>
              ))}
              <li data-walk-arrive className="mt-1 rounded-lg bg-fb-blue-pale px-3 py-2 text-base text-ink">
                <span className="font-bold">{t.arrive}: </span>
                {item.arrive}
              </li>
            </ol>
          ) : (
            <p data-walk-note key={chosen} className="mt-3 text-base text-muted">
              {item.asks_which ? t.asksWhich : t.notSeen}
            </p>
          )}
        </section>

        <p className="text-sm text-muted" data-recorded>
          {format(t.recorded, { date: walks.recorded_at.slice(0, 10) })}
        </p>
      </div>
    </div>
  );
}

const noSubscribe = () => () => {};
