"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { format, getDictionary } from "@/i18n";
import { gsap } from "@/lib/gsap";
import type { Walk } from "./Layers";

const t = getDictionary().app.demo.phone;

/** One cut of a real iPhone screen recording (make demo-clips → public/local-video/clips.json; gitignored). */
export interface Clip {
  id: string;
  kind: "find" | "scan" | "image";
  /** the thing a find clip walks to, by label */
  thing?: string;
  title: string;
  /** when it was recorded, YYYY-MM-DD */
  recorded: string;
  /** the seconds of the clip in which the person walks: the route follows them */
  walk?: [number, number];
  captions: [number, string][];
  file: string;
  seconds: number;
}

export interface Clips {
  /** "local": cut on this computer, never on the hosted site; "published": reviewed and published by the owner */
  source: "local" | "published";
  base: string;
  clips: Clip[];
}

/** This computer's clips if there are any (make demo-clips), else published ones; none on the hosted site today. */
export function useClips(): Clips | null {
  const [clips, setClips] = useState<Clips | null>(null);
  useEffect(() => {
    let cancelled = false;
    const get = (base: string) =>
      fetch(`${base}/clips.json`, { cache: "no-store" })
        .then((r) => (r.ok ? r.json() : null))
        .then((j) => (j && Array.isArray(j.clips) && j.clips.length ? ({ ...j, base } as Clips) : null))
        .catch(() => null);
    get("/local-video")
      .then((local) => local ?? get("/demo-video"))
      .then((c) => !cancelled && setClips(c));
    return () => {
      cancelled = true;
    };
  }, []);
  return clips;
}

/** A phone outline around a screen; decorative, so its text is repeated in the page for screen readers. */
function Frame({ children, label }: { children: ReactNode; label: string }) {
  return (
    <figure className="mx-auto w-full max-w-[270px]">
      <div className="overflow-hidden rounded-[2.4rem] border-[9px] border-ink bg-ink shadow-xl">
        <div className="relative aspect-[9/19.5] overflow-hidden rounded-[1.7rem] bg-fb-grey">{children}</div>
      </div>
      <figcaption className="mt-2 text-center text-sm text-muted">{label}</figcaption>
    </figure>
  );
}

/**
 * The AR camera view, drawn as a plain room: no photo of the home is needed for it. The floor chevrons lean the way the
 * clock-face step says; the thing's tag grows as the walk nears it; on arrival the app's blue arrow points down at it.
 */
function ArScene({ thing, hour, progress, before, there }: { thing: string; hour: number; progress: number; before: boolean; there: boolean }) {
  const lean = ((hour % 12 > 6 ? hour % 12 - 12 : hour % 12) * 18).toFixed(0);
  const name = thing.toUpperCase();
  const scale = there ? 1.15 : 0.65 + progress * 0.35;
  const width = name.length * 8.6 + 26;
  return (
    <svg viewBox="0 0 270 340" preserveAspectRatio="xMidYMid slice" aria-hidden className="absolute inset-0 size-full">
      <defs>
        <linearGradient id="ar-wall" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#f3ecdd" />
          <stop offset="1" stopColor="#ddd3bf" />
        </linearGradient>
        <linearGradient id="ar-floor" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#c4924f" />
          <stop offset="1" stopColor="#9c6c33" />
        </linearGradient>
      </defs>
      <rect width="270" height="176" fill="url(#ar-wall)" />
      <rect y="176" width="270" height="164" fill="url(#ar-floor)" />
      <rect y="170" width="270" height="7" fill="#fbf7ee" />
      <g stroke="#7a4f1f" strokeOpacity="0.28">
        {[-260, -170, -90, -30, 30, 90, 170, 260].map((x) => (
          <line key={x} x1={135 + x * 0.35} y1="177" x2={135 + x * 1.9} y2="340" />
        ))}
      </g>
      {!before && !there && (
        <g transform={`rotate(${lean} 135 340)`} fill="none" stroke="#4a78e0" strokeLinecap="round" strokeLinejoin="round">
          {[
            { y: 310, s: 1, o: 0.95 },
            { y: 268, s: 0.74, o: 0.8 },
            { y: 236, s: 0.54, o: 0.65 },
            { y: 212, s: 0.38, o: 0.5 },
          ].map((c) => (
            <path key={c.y} d="M-34 14 L0 -14 L34 14" strokeWidth="11" strokeOpacity={c.o} transform={`translate(135 ${c.y}) scale(${c.s})`} />
          ))}
        </g>
      )}
      <g transform={`translate(135 ${there ? 190 : 176}) scale(${scale.toFixed(2)})`}>
        <ellipse cy="54" rx="40" ry="12" fill="none" stroke="#2fa84a" strokeWidth="3.5" />
        {there && <path d="M-15 -12 H15 V14 H29 L0 44 L-29 14 H-15 Z" fill="#3b5998" stroke="white" strokeWidth="3" strokeLinejoin="round" />}
        <g transform={`translate(${-width / 2} ${there ? -48 : -14})`}>
          <rect width={width} height="28" rx="4" fill="#0d1424" fillOpacity="0.92" stroke="#2fa84a" strokeWidth="2" />
          <rect width="4" height="28" fill="#2fa84a" />
          <text x="13" y="19" fill="white" fontFamily="ui-monospace, monospace" fontSize="14" fontWeight="700">
            {name}
          </text>
        </g>
      </g>
    </svg>
  );
}

/** The app's direction dial: a white face with 12, 3, 6, 9, and a blue hand on the hour, or a green tick on arrival. */
function ClockFace({ hour, done }: { hour: number; done?: boolean }) {
  return (
    <svg viewBox="0 0 48 48" aria-hidden className="size-[3.75rem] shrink-0">
      <circle cx="24" cy="24" r="23" fill="white" />
      {[12, 3, 6, 9].map((h) => {
        const a = (h % 12) * (Math.PI / 6);
        return (
          <text key={h} x={24 + 16.5 * Math.sin(a)} y={24 - 16.5 * Math.cos(a) + 2.4} textAnchor="middle" fontSize="6.5" fontWeight="800" fill="var(--color-fb-blue-dark)">
            {h}
          </text>
        );
      })}
      {done ? (
        <path d="M14 25 L21 32 L34 16" fill="none" stroke="var(--color-cta-dark)" strokeWidth="4.5" strokeLinecap="round" strokeLinejoin="round" />
      ) : (
        <>
          <path d="M24 9 L29 19 H26 V25 H22 V19 H19 Z" fill="#3b5998" stroke="white" strokeWidth="1" strokeLinejoin="round" transform={`rotate(${(hour % 12) * 30} 24 24)`} />
          <circle cx="24" cy="24" r="2" fill="var(--color-fb-blue-dark)" />
        </>
      )}
    </svg>
  );
}

/**
 * The guidance screen as the app lays it out (the camera with its labels, the card with the dial and the step, then
 * Repeat and Stop or Done), drawn in HTML for the walks no one recorded. `step` is the step being spoken: -1 before the
 * walk, steps.length once there.
 */
export function SimulatedPhone({ thing, heard, steps, arrive, step }: { thing: string; heard?: string; steps: { clock: number; say: string }[]; arrive: string; step: number }) {
  const before = step < 0;
  const there = step >= steps.length;
  const now = steps[Math.min(Math.max(step, 0), steps.length - 1)];
  const progress = there ? 1 : Math.max(step + 1, 0) / Math.max(steps.length, 1);
  return (
    <Frame label={t.simulated}>
      <div aria-hidden data-simulated-phone data-step={step} className="flex h-full flex-col bg-fb-grey">
        <div className="relative min-h-0 flex-1 overflow-hidden">
          <ArScene thing={thing} hour={now?.clock ?? 12} progress={progress} before={before} there={there} />
          <div className="absolute inset-x-5 top-2.5 flex items-center justify-between text-[0.62rem] font-bold text-ink">
            <span>9:41</span>
            <span className="h-[1.1rem] w-[4.6rem] rounded-full bg-black" />
            <span className="flex items-end gap-0.5">
              {[3, 5, 7, 9].map((h) => (
                <span key={h} className="w-[0.15rem] rounded-sm bg-ink" style={{ height: h }} />
              ))}
            </span>
          </div>
          <div className="absolute inset-x-3 top-10 flex items-center justify-between gap-2 text-[0.62rem] font-semibold">
            <span className="truncate rounded-full bg-black/65 px-2.5 py-1.5 text-white">{format(t.walkingTo, { thing })}</span>
            <span className="rounded-full bg-white/85 px-2.5 py-1.5 text-fb-blue-dark">{t.done}</span>
          </div>
          <div className="absolute inset-x-0 top-[4.75rem] flex justify-center gap-1.5 text-[0.58rem] font-semibold">
            <span className="rounded-full bg-white px-2.5 py-1 text-ink">{t.camera}</span>
            <span className="rounded-full bg-black/60 px-2.5 py-1 text-white">{t.edges}</span>
          </div>
          {before && <p className="absolute inset-x-6 bottom-12 rounded-xl bg-black/55 px-2 py-1 text-center text-xs font-semibold text-white">{t.startHere}</p>}
          {heard && (
            <p className="absolute inset-x-4 bottom-2 truncate rounded-xl bg-black/55 px-2.5 py-1 text-center text-[0.62rem] italic text-white">“{heard}”</p>
          )}
        </div>
        <div className="mx-3 mt-3 rounded-[1.25rem] bg-[#2b436f] p-3 text-white">
          <div className="flex items-center gap-3">
            <ClockFace hour={before ? 12 : now.clock} done={there} />
            <div className="min-w-0">
              <p className="text-[0.68rem] font-semibold">{thing.charAt(0).toUpperCase() + thing.slice(1)}</p>
              <p className="text-[0.85rem] font-bold leading-snug">{before ? t.takeMeThere : there ? arrive : now.say}</p>
            </div>
          </div>
        </div>
        <div className="mx-3 mb-3 mt-2.5 grid grid-cols-2 gap-2.5 text-xs font-bold">
          <span className="flex items-center justify-center gap-1.5 rounded-full bg-white py-2.5 text-fb-blue-dark shadow-sm ring-1 ring-black/5">
            <svg viewBox="0 0 16 16" className="size-3.5" fill="currentColor">
              <path d="M2 6v4h3l4 3V3L5 6H2Z" />
              <path d="M11 5.5a3.5 3.5 0 0 1 0 5" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
            </svg>
            {t.repeat}
          </span>
          <span className={`flex items-center justify-center gap-1.5 rounded-full py-2.5 text-white shadow-sm ${there ? "bg-[#2f6b1f]" : "bg-[#8f1d1d]"}`}>
            {there ? (
              <svg viewBox="0 0 16 16" className="size-3.5" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M3 8.5 6.5 12 13 4.5" />
              </svg>
            ) : (
              <span className="size-2.5 rounded-[2px] bg-white" />
            )}
            {there ? t.done : t.stop}
          </span>
        </div>
        <span className="mx-auto mb-1.5 h-1 w-20 rounded-full bg-ink/70" />
      </div>
    </Frame>
  );
}

function captionAt(clip: Clip, time: number) {
  let line = clip.captions[0]?.[1] ?? "";
  for (const [at, text] of clip.captions) if (at <= time) line = text;
  return line;
}

/**
 * A real screen recording. For a find clip the route on the 3D views follows the video: while it plays, the walker
 * is where the person is in the clip's walking seconds; paused or before playing, the whole route shows.
 */
export function RecordedPhone({ clip, base, walk, still, autoPlay }: { clip: Clip; base: string; walk?: Walk | null; still: boolean; autoPlay: boolean }) {
  const video = useRef<HTMLVideoElement>(null);
  const [caption, setCaption] = useState(clip.captions[0]?.[1] ?? "");

  useEffect(() => {
    const v = video.current;
    if (!v) return;
    let frame = 0;
    const follow = () => {
      if (walk && clip.walk && !still) {
        const [a, b] = clip.walk;
        gsap.set(walk.progress, { value: Math.min(1, Math.max(0, (v.currentTime - a) / (b - a))) });
      }
      if (!v.paused) frame = requestAnimationFrame(follow);
    };
    const play = () => {
      cancelAnimationFrame(frame);
      follow();
    };
    const rest = () => {
      cancelAnimationFrame(frame);
      if (walk && v.ended) gsap.set(walk.progress, { value: 1 });
    };
    const time = () => setCaption(captionAt(clip, v.currentTime));
    v.addEventListener("play", play);
    v.addEventListener("pause", rest);
    v.addEventListener("ended", rest);
    v.addEventListener("seeked", follow);
    v.addEventListener("timeupdate", time);
    if (autoPlay && !still) v.play().catch(() => {});
    return () => {
      cancelAnimationFrame(frame);
      v.removeEventListener("play", play);
      v.removeEventListener("pause", rest);
      v.removeEventListener("ended", rest);
      v.removeEventListener("seeked", follow);
      v.removeEventListener("timeupdate", time);
      if (walk) gsap.set(walk.progress, { value: 1 });
    };
  }, [clip, walk, still, autoPlay]);

  return (
    <div data-recorded-phone={clip.id}>
      <Frame label={format(t.recorded, { date: clip.recorded })}>
        {/* muted until the viewer turns the sound on with the player's own control */}
        <video ref={video} src={`${base}/${clip.file}`} className="size-full object-cover" controls muted playsInline preload="metadata" aria-label={clip.title} />
      </Frame>
      <p data-clip-caption className="mx-auto mt-2 max-w-[270px] text-center text-sm font-semibold text-ink" aria-live="off">
        {caption}
      </p>
    </div>
  );
}
