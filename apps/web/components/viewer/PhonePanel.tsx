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
 * The AR camera view, drawn: no photo of the home goes on the public page, so the room is a floor grid. The chevrons
 * lean the way the clock-face step says; the thing's tag grows as the walk nears it, as the labels do in the camera.
 */
function ArScene({ thing, hour, progress, before, there }: { thing: string; hour: number; progress: number; before: boolean; there: boolean }) {
  const lean = ((hour % 12 > 6 ? hour % 12 - 12 : hour % 12) * 18).toFixed(0);
  const name = thing.toUpperCase();
  const scale = there ? 1.2 : 0.65 + progress * 0.4;
  const width = name.length * 8.6 + 26;
  return (
    <svg viewBox="0 0 270 320" preserveAspectRatio="xMidYMid slice" aria-hidden className="absolute inset-0 size-full">
      <defs>
        <linearGradient id="ar-wall" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#3b4f78" />
          <stop offset="1" stopColor="#2a3a5c" />
        </linearGradient>
        <linearGradient id="ar-floor" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#1f2c47" />
          <stop offset="1" stopColor="#141d31" />
        </linearGradient>
      </defs>
      <rect width="270" height="150" fill="url(#ar-wall)" />
      <rect y="150" width="270" height="170" fill="url(#ar-floor)" />
      <g stroke="white" strokeOpacity="0.12">
        {[-200, -110, -40, 40, 110, 200, 320, -320].map((x) => (
          <line key={x} x1="135" y1="150" x2={135 + x * 1.6} y2="320" />
        ))}
        {[166, 190, 226, 276].map((y) => (
          <line key={y} x1="0" y1={y} x2="270" y2={y} />
        ))}
      </g>
      {!before && !there && (
        <g transform={`rotate(${lean} 135 320)`} fill="none" stroke="#7ea6ff" strokeLinecap="round" strokeLinejoin="round">
          {[
            { y: 286, s: 1, o: 1 },
            { y: 244, s: 0.74, o: 0.8 },
            { y: 212, s: 0.54, o: 0.6 },
            { y: 190, s: 0.38, o: 0.4 },
          ].map((c) => (
            <path key={c.y} d="M-34 14 L0 -14 L34 14" strokeWidth="10" strokeOpacity={c.o} transform={`translate(135 ${c.y}) scale(${c.s})`} />
          ))}
        </g>
      )}
      <g transform={`translate(135 ${there ? 176 : 150}) scale(${scale.toFixed(2)})`}>
        <ellipse cy="46" rx="42" ry="12" fill="none" stroke={there ? "#6fe08a" : "#42b72a"} strokeWidth="3" />
        {there && <path d="M-14 -4 L-4 8 L16 -16" transform="translate(0 24)" fill="none" stroke="#6fe08a" strokeWidth="6" strokeLinecap="round" strokeLinejoin="round" />}
        <g transform={`translate(${-width / 2} -44)`}>
          <rect width={width} height="28" rx="4" fill="#0d1424" fillOpacity="0.92" stroke="#42b72a" strokeWidth="2" />
          <rect width="4" height="28" fill="#42b72a" />
          <text x="13" y="19" fill="white" fontFamily="ui-monospace, monospace" fontSize="14" fontWeight="700">
            {name}
          </text>
        </g>
      </g>
    </svg>
  );
}

function ClockFace({ hour, done }: { hour: number; done?: boolean }) {
  return (
    <svg viewBox="0 0 40 40" aria-hidden className="size-14 shrink-0">
      <circle cx="20" cy="20" r="18" fill="white" />
      {done ? (
        <path d="M11 21 L17.5 27 L29 14" fill="none" stroke="var(--color-cta-dark)" strokeWidth="4" strokeLinecap="round" strokeLinejoin="round" />
      ) : (
        <>
          <line x1="20" y1="20" x2="20" y2="7" stroke="var(--color-fb-blue-dark)" strokeWidth="3.5" strokeLinecap="round" transform={`rotate(${(hour % 12) * 30} 20 20)`} />
          <circle cx="20" cy="20" r="2.5" fill="var(--color-fb-blue-dark)" />
        </>
      )}
    </svg>
  );
}

/**
 * The guidance screen as the app lays it out (the arrow, then a card with the clock face, the thing and the step),
 * drawn in HTML for the walks no one recorded. `step` is the step being spoken: -1 before the walk, steps.length
 * once there.
 */
export function SimulatedPhone({ thing, heard, steps, arrive, step }: { thing: string; heard?: string; steps: { clock: number; say: string }[]; arrive: string; step: number }) {
  const before = step < 0;
  const there = step >= steps.length;
  const now = steps[Math.min(Math.max(step, 0), steps.length - 1)];
  const progress = there ? 1 : Math.max(step + 1, 0) / Math.max(steps.length, 1);
  return (
    <Frame label={t.simulated}>
      <div aria-hidden data-simulated-phone data-step={step} className="flex h-full flex-col">
        <div className="relative min-h-0 flex-1 overflow-hidden">
          <ArScene thing={thing} hour={now?.clock ?? 12} progress={progress} before={before} there={there} />
          <div className="absolute inset-x-2.5 top-3 flex items-center justify-between gap-2 text-[0.6rem] font-bold text-white">
            <span className="truncate rounded-full bg-black/60 px-2.5 py-1">{format(t.walkingTo, { thing })}</span>
            <span className="rounded-full bg-white/90 px-2.5 py-1 text-ink">{t.done}</span>
          </div>
          <div className="absolute inset-x-0 top-11 flex justify-center gap-1.5 text-[0.55rem] font-bold">
            <span className="rounded-full bg-white px-2.5 py-1 text-ink">{t.camera}</span>
            <span className="rounded-full bg-black/60 px-2.5 py-1 text-white">{t.edges}</span>
          </div>
          {before && <p className="absolute inset-x-6 bottom-16 text-center text-xs font-semibold text-white">{t.startHere}</p>}
          {heard && (
            <p className="absolute inset-x-3 bottom-2 truncate rounded-xl bg-black/55 px-2.5 py-1 text-center text-[0.6rem] italic text-white">“{heard}”</p>
          )}
        </div>
        <div className="mx-2 mt-2 rounded-2xl bg-fb-blue-dark p-2.5 text-white">
          <div className="flex items-center gap-2.5">
            <ClockFace hour={before ? 12 : now.clock} done={there} />
            <div className="min-w-0">
              <p className="text-[0.65rem] opacity-90">{thing.charAt(0).toUpperCase() + thing.slice(1)}</p>
              <p className="text-[0.82rem] font-bold leading-snug">{before ? t.takeMeThere : there ? arrive : now.say}</p>
            </div>
          </div>
        </div>
        <div className="mx-2 mb-2.5 mt-2 grid grid-cols-2 gap-2 text-center text-xs font-bold">
          <span className="rounded-full bg-[#f3e3c3] py-2 text-ink">{t.repeat}</span>
          <span className={`rounded-full py-2 text-white ${there ? "bg-cta-dark" : "bg-ink"}`}>{there ? t.done : t.stop}</span>
        </div>
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
