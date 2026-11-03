"use client";

import { useEffect, useId, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { format, getDictionary } from "@/i18n";
import { gsap, MOTION_OK, SplitText, useGSAP } from "@/lib/gsap";
import { useMotionPrefs } from "@/lib/motion-prefs";
import { canSpeak, sayLine, stopSpeaking } from "@/lib/speech";
import type { Walk } from "./Layers";
import { type ScanMeta, viewerStrings } from "./LocalScan";
import { RecordedPhone, SimulatedPhone, useClips } from "./PhonePanel";
import { RoomViewer } from "./RoomViewer";

/** A walk to one thing: the planner's clock-face steps from where the scan began (walks.json, `make demo-walks`). */
export interface WalkOption {
  label: string;
  /** the colour and the place, from the Guide's own tool output: "grey", "near the table · waist height" */
  color?: string | null;
  place?: string;
  /** the thing, in the viewer's frame */
  target: number[];
  /** "landmarks" when no clear path exists: one step that names the place instead */
  mode: "route" | "landmarks";
  steps: { clock: number; metres: number; say: string }[];
  arrive: string;
  /** floor points from where the scan began to the thing (empty without a clear path) */
  path: [number, number][];
}

/** One recorded question: the Guide's answer, then one walk, or the choices when it asks "which one?". */
export interface WalkItem extends Partial<WalkOption> {
  question: string;
  answer: string;
  grounded: boolean;
  model: string;
  choices?: WalkOption[];
}

export interface Walks {
  label: string;
  recorded_at: string;
  captured_at: string;
  room: string;
  walks: WalkItem[];
}

const t = getDictionary().app.demo;

function optionOf(item: WalkItem, pick: number): WalkOption | null {
  if (item.choices) return item.choices[Math.min(pick, item.choices.length - 1)];
  return item.steps && item.label ? (item as WalkOption) : null;
}

/** The thing's arrow in the viewer: the one with this label nearest the walk's target. */
function thingIndex(meta: ScanMeta | null, option: WalkOption | null): number | null {
  if (!meta || !option) return null;
  const [x, y] = option.target;
  let best: number | null = null;
  let bestD = Infinity;
  for (const [i, o] of meta.objects.entries()) {
    const d = Math.hypot(o.at[0] - x, o.at[1] - y);
    if (o.label === option.label && d < bestD) {
      best = i;
      bestD = d;
    }
  }
  return best;
}

const metresOf = (o: WalkOption) => o.steps.reduce((sum, s) => sum + s.metres, 0);

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

const noSubscribe = () => () => {};
const watchMotion = (change: () => void) => {
  const mq = window.matchMedia(MOTION_OK);
  mq.addEventListener("change", change);
  return () => mq.removeEventListener("change", change);
};

/**
 * Ask, then walk: pick a recorded question, read (or hear) Recall's answer, and watch the walk. GSAP writes the answer
 * in word by word, draws the route on the floor of the 3D room (two views side by side on a wide screen), moves "you"
 * along it and brings in each spoken step as the route reaches it, while the phone beside it shows that step. When
 * this computer has a real screen recording of that walk, the phone plays it and the route follows the video instead.
 * Everything is in the page's HTML first, so it reads the same without JavaScript or with motion reduced.
 */
export function WalkDemo({ walks, src }: { walks: Walks; src: string }) {
  const id = useId();
  const root = useRef<HTMLDivElement>(null);
  const { reduced } = useMotionPrefs();
  const motionOk = useSyncExternalStore(watchMotion, () => window.matchMedia(MOTION_OK).matches, () => true);
  const still = reduced || !motionOk;
  const [chosen, setChosen] = useState(0);
  const [pick, setPick] = useState(0);
  const [replays, setReplays] = useState(0);
  const [meta, setMeta] = useState<ScanMeta | null>(null);
  const [speaking, setSpeaking] = useState(false);
  const [phone, setPhone] = useState<"recording" | "simulated">("recording");
  // the step the phone is speaking: -1 before the walk, steps.length once there (and from the start without motion)
  const [step, setStep] = useState(() => optionOf(walks.walks[0], 0)?.steps.length ?? 0);
  const [asked, setAsked] = useState(false);
  // speech synthesis exists only in the browser: the server (and the first render) draws no Hear button
  const speech = useSyncExternalStore(noSubscribe, canSpeak, () => false);
  const clips = useClips();
  const item = walks.walks[chosen];
  const option = optionOf(item, pick);
  const clip = clips?.clips.find((c) => c.kind === "find" && option && c.thing === option.label) ?? null;
  const scanClip = clips?.clips.find((c) => c.kind === "scan") ?? null;
  const playing = Boolean(clip) && phone === "recording";

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

  // a new box per walk (and per replay): the route redraws from its start; full when motion is reduced
  const walk: Walk | null = useMemo(
    () => (option && option.path.length > 1 ? { path: option.path, progress: { value: 1 } } : null),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- a replay asks for a fresh box on purpose
    [option, replays],
  );
  const selected = thingIndex(meta, option);

  useGSAP(
    () => {
      const el = root.current;
      if (still) {
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
      if (walk && option && !playing) {
        // the route draws at walking pace on screen; each step arrives when the route reaches its start
        const metres = option.steps.map((s) => Math.max(s.metres, 0.2));
        const total = metres.reduce((a, b) => a + b, 0);
        const span = Math.min(5, 1.2 + total * 0.5);
        const at = tl.duration();
        tl.call(() => setStep(-1), [], 0);
        tl.fromTo(walk.progress, { value: 0 }, { value: 1, duration: span, ease: "none", immediateRender: true }, at);
        let done = 0;
        steps.forEach((s, i) => {
          const start = at + (span * done) / total;
          tl.from(s, { opacity: 0, x: -14, duration: 0.4 }, start);
          tl.from(s.querySelector("[data-hand]"), { rotation: 0, svgOrigin: "20 20", duration: 0.5, ease: "back.out(2)" }, start);
          tl.call(() => setStep(i), [], start);
          done += metres[i] ?? 0;
        });
        tl.call(() => setStep(option.steps.length), [], at + span);
        tl.from("[data-walk-arrive]", { opacity: 0, y: 8, duration: 0.4 }, at + span);
      } else {
        tl.from("[data-walk-note], [data-walk-step]", { opacity: 0, y: 8, duration: 0.4, stagger: 0.05 });
      }
      return () => {
        words.revert();
        if (walk) gsap.set(walk.progress, { value: 1 });
      };
    },
    { scope: root, dependencies: [walk, still, playing], revertOnUpdate: true },
  );

  useEffect(() => () => stopSpeaking(), []);
  const quiet = () => {
    stopSpeaking();
    setSpeaking(false);
  };
  const choose = (i: number) => {
    quiet();
    setChosen(i);
    setPick(0);
    setAsked(true);
    setStep(optionOf(walks.walks[i], 0)?.steps.length ?? 0);
  };
  const choosePick = (i: number) => {
    quiet();
    setPick(i);
    setStep(item.choices?.[i]?.steps.length ?? 0);
  };
  const hear = async () => {
    if (speaking) return quiet();
    setSpeaking(true);
    const lines = [item.answer, ...(option ? [t.start, ...option.steps.map((s) => s.say), option.arrive] : [])];
    await sayLine(lines.join(" "), "assistant", { long: true });
    setSpeaking(false);
  };

  const viewer = (props: { start: { view: "dots" | "architect"; preset: "iso" | "top"; distance: number; spin: boolean }; controls: boolean; label: string }) =>
    meta ? (
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
        start={props.start}
        controls={props.controls}
        t={{ ...viewerStrings(), label: `${t.viewerAlt} ${props.label}.` }}
      />
    ) : (
      <p className="grid aspect-[4/3] place-items-center text-sm text-muted">{viewerStrings().loading}</p>
    );
  const architect = { view: "architect", preset: "top", distance: 1.45, spin: false } as const;

  return (
    <div ref={root} className="mt-8 grid gap-6" data-walk-demo>
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
              <input type="radio" name={`${id}-question`} value={i} checked={chosen === i} onChange={() => choose(i)} className="sr-only" data-question />
              {w.question}
            </label>
          ))}
        </div>
      </fieldset>

      {/* one view with its switch on smaller screens; every point and the architect's room side by side on wide ones */}
      <div className="card self-start overflow-hidden xl:hidden" data-viewer-single>
        {viewer({ start: architect, controls: true, label: t.architect })}
        <p className="border-t border-fb-line px-4 py-2 text-sm text-muted">{t.legend}</p>
      </div>
      <div className="hidden gap-6 xl:grid xl:grid-cols-2" data-viewer-pair>
        {[
          { start: { view: "dots", preset: "iso", distance: 1.05, spin: false } as const, label: t.dots },
          { start: architect, label: t.architect },
        ].map((v) => (
          <figure key={v.label} className="card overflow-hidden">
            {viewer({ start: v.start, controls: false, label: v.label })}
            <figcaption className="border-t border-fb-line px-4 py-2 text-sm text-muted">
              <span className="font-semibold text-ink">{v.label}.</span> {t.legend}
            </figcaption>
          </figure>
        ))}
      </div>

      <div className="grid gap-6 lg:grid-cols-[1fr_300px]">
        <div className="flex flex-col gap-6">
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
            {item.choices && (
              <fieldset className="mt-4" data-choices>
                <legend className="text-sm font-bold text-ink">{t.choices}</legend>
                <div className="mt-2 flex flex-col gap-2">
                  {item.choices.map((c, i) => (
                    <label
                      key={i}
                      className="flex min-h-11 cursor-pointer items-center gap-2 rounded-xl border border-fb-line bg-white px-3.5 py-2 text-sm text-ink has-checked:border-fb-blue has-checked:bg-fb-blue-pale has-checked:font-semibold has-focus-visible:outline-2 has-focus-visible:outline-fb-blue"
                    >
                      <input type="radio" name={`${id}-choice`} value={i} checked={pick === i} onChange={() => choosePick(i)} className="size-4 accent-fb-blue" data-choice />
                      <span>
                        {[c.color, c.label].filter(Boolean).join(" ")} · {c.place}
                        {c.mode === "route" && <span className="text-muted"> · {format(t.walkAway, { m: metresOf(c).toFixed(1) })}</span>}
                      </span>
                    </label>
                  ))}
                </div>
              </fieldset>
            )}
            <div className="mt-4 flex flex-wrap gap-3">
              {speech && (
                <button type="button" onClick={hear} className="btn btn-ghost min-h-11" aria-pressed={speaking} data-hear>
                  {speaking ? t.stop : t.hear}
                </button>
              )}
              {walk && !playing && (
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
            {option ? (
              <ol className="mt-3 grid gap-2.5" key={`${chosen}-${pick}-${replays}`}>
                <li className="text-base text-muted">{t.start}</li>
                {option.mode === "landmarks" && (
                  <li data-walk-note className="text-base text-muted">
                    {t.noPath}
                  </li>
                )}
                {option.steps.map((s, i) => (
                  <li key={i} data-walk-step className="flex items-center gap-3 text-lg font-semibold text-ink">
                    <span className="text-fb-blue-dark">
                      <Clock hour={s.clock} />
                    </span>
                    {s.say}
                  </li>
                ))}
                {option.mode === "route" && (
                  <li data-walk-arrive className="mt-1 rounded-lg bg-fb-blue-pale px-3 py-2 text-base text-ink">
                    <span className="font-bold">{t.arrive}: </span>
                    {option.arrive}
                  </li>
                )}
              </ol>
            ) : (
              <p data-walk-note key={chosen} className="mt-3 text-base text-muted">
                {t.notSeen}
              </p>
            )}
          </section>

          <p className="text-sm text-muted" data-recorded>
            {format(t.recorded, { date: walks.recorded_at.slice(0, 10) })}
          </p>
        </div>

        <aside aria-labelledby={`${id}-phone`} className="flex flex-col gap-3" data-phone>
          <h2 id={`${id}-phone`} className="text-sm font-bold text-ink">
            {t.phone.title}
          </h2>
          {clip && (
            <fieldset className="flex flex-wrap gap-2" data-phone-mode>
              <legend className="sr-only">{t.phone.view}</legend>
              {(["recording", "simulated"] as const).map((m) => (
                <label key={m} className="flex min-h-11 cursor-pointer items-center gap-2 rounded-full border border-fb-line bg-white px-3 text-sm text-ink has-checked:border-fb-blue has-checked:bg-fb-blue-pale">
                  <input type="radio" name={`${id}-phone`} checked={phone === m} onChange={() => setPhone(m)} className="size-4 accent-fb-blue" />
                  {m === "recording" ? t.phone.showRecording : t.phone.showSimulated}
                </label>
              ))}
            </fieldset>
          )}
          {clip && clips && playing ? (
            <>
              <RecordedPhone clip={clip} base={clips.base} walk={walk} still={still} autoPlay={asked} />
              <p className="text-xs text-muted">
                {format(t.phone.recordedNote, { date: clip.recorded })} {clips.source === "local" && t.phone.localOnly}
              </p>
            </>
          ) : option ? (
            <SimulatedPhone thing={[option.color, option.label].filter(Boolean).join(" ")} steps={option.steps} arrive={option.arrive} step={still ? option.steps.length : step} />
          ) : null}
        </aside>
      </div>

      {scanClip && clips && (
        <section aria-labelledby={`${id}-scan`} className="card grid gap-6 p-5 md:grid-cols-[1fr_300px]" data-scan-clip>
          <div>
            <h2 id={`${id}-scan`} className="text-2xl font-bold text-ink">
              {t.scanClip.title}
            </h2>
            <p className="mt-2 text-base text-muted">{format(t.scanClip.body, { date: scanClip.recorded })}</p>
            <ol className="mt-4 grid gap-2 text-sm text-ink">
              {scanClip.captions.map(([at, line]) => (
                <li key={at}>
                  <span className="tabular-nums text-muted">{`${Math.floor(at / 60)}:${String(at % 60).padStart(2, "0")}`}</span> {line}
                </li>
              ))}
            </ol>
            {clips.source === "local" && <p className="mt-3 text-xs text-muted">{t.phone.localOnly}</p>}
          </div>
          <RecordedPhone clip={scanClip} base={clips.base} still={still} autoPlay={false} />
        </section>
      )}
    </div>
  );
}
