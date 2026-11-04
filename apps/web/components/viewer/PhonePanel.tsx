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

/** An arrow pointing the way a clock-face turn says (12 is straight ahead), as the app's camera view shows it. */
function TurnArrow({ hour }: { hour: number }) {
  return (
    <svg viewBox="0 0 100 100" aria-hidden className="size-28 drop-shadow">
      <g transform={`rotate(${(hour % 12) * 30} 50 50)`}>
        <path d="M50 8 L80 46 H62 V88 H38 V46 H20 Z" fill="currentColor" stroke="white" strokeWidth="4" strokeLinejoin="round" />
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
export function SimulatedPhone({ thing, steps, arrive, step }: { thing: string; steps: { clock: number; say: string }[]; arrive: string; step: number }) {
  const before = step < 0;
  const there = step >= steps.length;
  const now = steps[Math.min(Math.max(step, 0), steps.length - 1)];
  return (
    <Frame label={t.simulated}>
      <div aria-hidden data-simulated-phone data-step={step} className="flex h-full flex-col">
        <div className="flex items-center gap-1.5 px-4 pt-4 text-[0.65rem] font-bold tracking-widest text-ink">RECALL</div>
        <div className="grid flex-1 place-items-center text-fb-blue">
          {before ? (
            <p className="px-6 text-center text-sm font-semibold text-ink">{t.startHere}</p>
          ) : there ? (
            <ClockFace hour={12} done />
          ) : (
            <TurnArrow hour={now.clock} />
          )}
        </div>
        <div className="m-2.5 rounded-2xl bg-fb-blue-dark p-3 text-white">
          <div className="flex items-center gap-3">
            <ClockFace hour={before ? 12 : now.clock} done={there} />
            <div className="min-w-0">
              <p className="text-[0.7rem] opacity-90">{thing.charAt(0).toUpperCase() + thing.slice(1)}</p>
              <p className="text-[0.95rem] font-bold leading-snug">{before ? t.takeMeThere : there ? arrive : now.say}</p>
            </div>
          </div>
        </div>
        <div className="mx-2.5 mb-3 grid grid-cols-2 gap-2 text-center text-xs font-bold">
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
