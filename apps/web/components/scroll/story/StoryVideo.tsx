"use client";

import { useRef, useState, type ChangeEvent } from "react";
import { PixelIcon } from "@/components/ui/PixelIcon";
import { captionTimes, STORY_SECONDS } from "@/content/story";
import { format } from "@/i18n";
import { useLocale, useT } from "@/i18n/I18nProvider";
import { gsap, MOTION_OK, ScrollTrigger, useGSAP } from "@/lib/gsap";
import { useMotionPrefs } from "@/lib/motion-prefs";
import { sayLine } from "@/lib/speech";
import { SAM_FRAMES, SAM_PALETTE } from "@/lib/pixel-sprites";
import { useReactions } from "@/lib/reactions";
import { stopSpeaking } from "@/lib/speech";
import { HappyMug } from "./HappyMug";
import { PixelSprite } from "./PixelSprite";

// scene layout, in the 640 × 360 frame
const FLOOR = 300; // where feet stand
const SAM_SCALE = 4; // 16 × 24 cells → 64 × 96
const SAM_TOP = FLOOR - 24 * SAM_SCALE;
// Sam starts inside the room (by the window), so he is on screen when the first line is spoken
const SAM_AT = { start: 8, sofa: 90, shelf: 270, table: 440 };
const TABLE_TOP = 250;
const MUG_AT = { hidden: 520, found: 580 };
const MUG_SCALE = 0.8;
const MUG_RIM = TABLE_TOP - 70 * MUG_SCALE; // top of the mug (HappyMug is 70 units tall)
// left edges of the three hearts, spread over the mug's width (mug body is ±25 units)
const HEART_X = [MUG_AT.found - 18, MUG_AT.found - 9, MUG_AT.found];
// along the floor at foot level, kept above the caption bar
const ROUTE = `M${SAM_AT.shelf + 40} ${FLOOR - 2} C ${SAM_AT.shelf + 90} ${FLOOR + 14}, ${SAM_AT.table - 20} ${FLOOR + 14}, ${SAM_AT.table + 30} ${FLOOR - 2}`;

// what the voice says: the caption without its quotation marks
const unquote = (text: string) => text.replace(/[“”"]/g, "");

/** Circular arrow, for Replay. */
function ReplayIcon({ className }: { className: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 12a8 8 0 1 0 2.4-5.7" />
      <path d="M4 4v4.5h4.5" />
    </svg>
  );
}
const SPEAK_AFTER = 0.01; // seconds after a line's moment that its speech is triggered
const time = (s: number) => `0:${String(Math.floor(s)).padStart(2, "0")}`;

/**
 * "One morning, one mug": a Facebook-style video post. One GSAP timeline plays the story while
 * it's on screen, with a real pause button. The markup is the last frame (Sam next to the happy
 * mug), so reduced motion and no-JS show the ending plus the transcript. Illustrative only.
 */
export function StoryVideo() {
  const root = useRef<HTMLElement>(null);
  const story = useRef<gsap.core.Timeline | null>(null);
  const userPaused = useRef(false);
  // narration: off by default (like a muted feed video); refs so timeline callbacks see the latest
  const soundOn = useRef(false);
  const onScreen = useRef(false);
  const [sound, setSound] = useState(false);
  const likeButton = useRef<HTMLButtonElement>(null);
  const [playing, setPlaying] = useState(true);
  // plays once; at the end it holds the last frame and offers Replay
  const [ended, setEnded] = useState(false);
  const endedRef = useRef(false);
  // lines already spoken in this run, so resuming at a held line never repeats it
  const spoken = useRef(new Set<string>());
  // the seek slider: its element, whether it's being dragged, and whether to resume afterwards
  const slider = useRef<HTMLInputElement>(null);
  const dragging = useRef(false);
  const wasPlaying = useRef(false);
  // brings the slider, clock and caption in line with the playhead (set up with the timeline)
  const sync = useRef<() => void>(() => {});
  // where the playhead was on the previous frame, to notice it crossing a line's moment
  const lastTime = useRef(0);
  const [liked, setLiked] = useState(false);
  const { reduced } = useMotionPrefs();
  const burst = useReactions();
  const t = useT().story;
  const locale = useLocale();

  useGSAP(
    () => {
      if (reduced) return;
      const mm = gsap.matchMedia();
      mm.add(MOTION_OK, () => {
        const q = gsap.utils.selector(root);
        const caption = q("[data-caption]")[0] as HTMLElement;
        const clock = q("[data-clock]")[0] as HTMLElement;
        const sam = "[data-sam]";
        const mug = "[data-mug]";

        const tl = gsap.timeline({
          paused: true,
          onUpdate: () => {
            const now = tl.time();
            // with sound on, a line whose moment the playhead has just crossed is spoken, holding
            // the story on that line's frame until it ends (its recording, else a device voice of
            // the same kind), once per run. Crossings are tracked here rather than with timeline
            // callbacks, so seeking (which only moves lastTime) never triggers or skips a line.
            const line = soundOn.current && !dragging.current
              ? captionTimes.find((c) => lastTime.current < c.at + SPEAK_AFTER && now >= c.at + SPEAK_AFTER && !spoken.current.has(c.key))
              : undefined;
            lastTime.current = now;
            sync.current();
            if (!line) return;
            spoken.current.add(line.key);
            // back to this line's own frame: a dropped frame can't let later tweens run first
            tl.pause(line.at + SPEAK_AFTER);
            lastTime.current = line.at + SPEAK_AFTER;
            sync.current();
            sayLine(unquote(t.captions[line.key]), line.voice).then(() => {
              if (!userPaused.current && onScreen.current && !dragging.current) tl.play();
            });
          },
          onComplete: () => {
            endedRef.current = true;
            setEnded(true);
            setPlaying(false);
          },
        });
        story.current = tl;

        // slider, clock and caption all follow the playhead, so seeking always shows the right line
        sync.current = () => {
          const now = tl.time();
          clock.textContent = `${time(now)} / ${time(STORY_SECONDS)}`;
          const el = slider.current;
          if (el && !dragging.current) el.value = String(Math.round(now * 10));
          el?.setAttribute("aria-valuetext", format(t.positionValue, { current: time(now), total: time(STORY_SECONDS) }));
          const current = [...captionTimes].reverse().find((c) => c.at <= now) ?? captionTimes[0];
          const line = t.captions[current.key];
          if (caption.textContent !== line) caption.textContent = line;
        };

        const show = (frame: keyof typeof SAM_FRAMES, at: number) =>
          tl.set("[data-frame]", { opacity: 0 }, at).set(`[data-frame="${frame}"]`, { opacity: 1 }, at);
        // walk: slide across while the legs alternate every 0.15s, then stand
        const walk = (to: number, at: number, duration: number) => {
          tl.to(sam, { x: to, duration, ease: "none" }, at);
          for (let k = 0; k * 0.15 < duration; k++) show(k % 2 ? "walkB" : "walkA", at + k * 0.15);
          show("stand", at + duration);
        };
        // the opening frame: Sam by the window, mug asleep behind the plant, nothing drawn yet.
        // Rule for every step below: each animated property has explicit start and end values in
        // the same tween (or one owner), so seeking backwards and Replay restore it correctly.
        tl.set(sam, { x: SAM_AT.start }, 0)
          .set(mug, { x: MUG_AT.hidden }, 0)
          .set("[data-route]", { drawSVG: "0%" }, 0)
          .set("[data-cross], [data-phone]", { opacity: 0 }, 0)
          .set("[data-bubble]", { opacity: 1, scale: 1 }, 0);

        // 1. walks in, thinking of the mug
        // the first line is spoken over this opening frame: Sam by the window, thinking of his mug
        walk(SAM_AT.sofa, 0.5, 1.1);
        // 2. not on the sofa, not on the shelf
        tl.to("[data-cross='sofa']", { opacity: 1, duration: 0.2 }, 1.9);
        walk(SAM_AT.shelf, 2.7, 1.2);
        tl.to("[data-cross='shelf']", { opacity: 1, duration: 0.2 }, 4.0)
          .to("[data-cross], [data-bubble]", { opacity: 0, duration: 0.3 }, 4.7);
        // 3. asks Recall; the answer draws a route
        tl.to("[data-phone]", { opacity: 1, duration: 0.2 }, 5.0)
          .fromTo("[data-wave]", { scale: 0.6, opacity: 1, transformOrigin: "0% 50%" }, { scale: 1.6, opacity: 0, duration: 0.5, stagger: 0.18, repeat: 1 }, 5.1)
          .to("[data-route]", { drawSVG: "100%", duration: 1, ease: "power1.inOut" }, 6.2)
          .to("[data-phone]", { opacity: 0, duration: 0.2 }, 7.1);
        // 4. walks the route; the mug wakes up, pops out and waves
        walk(SAM_AT.table, 7.2, 1.2);
        tl.to(mug, { x: MUG_AT.found, duration: 0.5, ease: "back.out(2)" }, 8.3)
          // the mug wakes: sleepy eyes off, open eyes and smile grow in
          .fromTo("[data-eyes-closed]", { opacity: 1 }, { opacity: 0, duration: 0.05 }, 8.45)
          .fromTo("[data-eyes], [data-smile]", { opacity: 0, scale: 0, transformOrigin: "50% 50%" }, { opacity: 1, scale: 1, duration: 0.3, ease: "back.out(3)" }, 8.45)
          // the mug's "Over here!" plays at 8.9 (content/story.ts); then it bounces and waves
          .to("[data-mug-body]", { y: -12, duration: 0.18, yoyo: true, repeat: 5, ease: "power1.out" }, 9.0)
          .to("[data-arm-l]", { rotation: 35, transformOrigin: "100% 0%", duration: 0.25, yoyo: true, repeat: 3, ease: "sine.inOut" }, 9.0)
          .to("[data-arm-r]", { rotation: -35, transformOrigin: "0% 0%", duration: 0.25, yoyo: true, repeat: 3, ease: "sine.inOut" }, 9.0)
          // hearts: hidden until 9.1 (in both directions), then rise and fade
          .fromTo("[data-heart]", { y: 0, scale: 0.4, opacity: 0, transformOrigin: "50% 100%" }, { opacity: 1, duration: 0.05 }, 9.1)
          .to("[data-heart]", { y: -70, scale: 1, opacity: 0, duration: 1.6, stagger: 0.25, ease: "power1.out" }, 9.15);
        // 5. they wave at each other (Sam's "There you are!" at 10.1, the mug's "You found me!" at 10.9)
        show("wave", 9.6);
        tl.set({}, {}, STORY_SECONDS); // hold to the full length

        ScrollTrigger.create({
          trigger: q("[data-frame-box]")[0],
          start: "top 80%",
          end: "bottom 20%",
          onToggle: (self) => {
            onScreen.current = self.isActive;
            // plays the first time it comes into view; once ended, it waits for Replay
            if (self.isActive && !userPaused.current && !endedRef.current) tl.play();
            else {
              tl.pause();
              stopSpeaking();
            }
          },
        });

        return () => {
          story.current = null;
          sync.current = () => {};
          stopSpeaking();
        };
      });
      return () => mm.revert();
    },
    { scope: root, dependencies: [reduced, t, locale], revertOnUpdate: true },
  );

  const replay = () => {
    const tl = story.current;
    if (!tl) return;
    stopSpeaking();
    spoken.current.clear();
    endedRef.current = false;
    setEnded(false);
    userPaused.current = false;
    setPlaying(true);
    lastTime.current = 0;
    tl.restart();
  };

  const toggle = () => {
    const tl = story.current;
    if (!tl) return;
    if (endedRef.current) return replay();
    // the visitor's choice decides, not tl.paused(): the timeline is also paused while a line is
    // spoken and while the story is off screen
    if (userPaused.current) {
      userPaused.current = false;
      setPlaying(true);
      if (onScreen.current) tl.play();
    } else {
      userPaused.current = true;
      tl.pause();
      stopSpeaking();
      setPlaying(false);
    }
  };

  // seeking: pause and stop speaking while dragging; resume afterwards if it was playing
  const seekStart = () => {
    const tl = story.current;
    if (!tl || dragging.current) return;
    dragging.current = true;
    wasPlaying.current = !userPaused.current && !endedRef.current;
    tl.pause();
    stopSpeaking();
  };
  const seek = (e: ChangeEvent<HTMLInputElement>) => {
    const tl = story.current;
    if (!tl) return;
    seekStart(); // keyboard arrows seek without a pointerdown first
    const at = Number(e.target.value) / 10;
    tl.time(at, true); // silently, and lastTime moves too, so a seek never counts as crossing a line
    lastTime.current = at;
    // lines from here on will be spoken again when played through
    captionTimes.forEach((c) => c.at >= at && spoken.current.delete(c.key));
    sync.current();
  };
  const seekEnd = () => {
    const tl = story.current;
    if (!tl || !dragging.current) return;
    dragging.current = false;
    const atEnd = tl.progress() >= 1;
    endedRef.current = atEnd;
    setEnded(atEnd);
    if (wasPlaying.current && !atEnd) {
      userPaused.current = false;
      tl.play();
      setPlaying(true);
    } else setPlaying(false);
  };

  const toggleSound = () => {
    const next = !soundOn.current;
    soundOn.current = next;
    setSound(next);
    // turning sound off lets a held line's promise resolve, and the story carries on silently
    if (!next) stopSpeaking();
  };

  const like = () => {
    if (!liked && likeButton.current) burst({ from: likeButton.current, items: ["like", "heart", "like"], count: 10 });
    setLiked((v) => !v);
  };

  return (
    <section ref={root} id="story" aria-labelledby="story-title" className="scroll-mt-20 bg-fb-grey py-24">
      <div className="mx-auto max-w-3xl px-4">
        <p className="classic-label">{t.eyebrow}</p>
        <h2 id="story-title" className="mt-4 text-4xl font-extrabold text-ink sm:text-5xl">
          {t.title}
        </h2>

        <article className="card mt-10 overflow-hidden" aria-label={t.postLabel}>
          <header className="flex items-center gap-3 px-4 py-3">
            <span className="ig-ring grid size-12 shrink-0 place-items-center rounded-full p-[3px]">
              <span className="grid size-full place-items-center rounded-full bg-white">
                <PixelIcon name="mug" size={26} />
              </span>
            </span>
            <div>
              <p className="font-bold text-ink">{t.author}</p>
              <p className="text-sm text-muted">{t.meta}</p>
            </div>
          </header>

          <div data-frame-box className="relative aspect-video bg-[#fbe9dc]">
            <svg
              viewBox="0 0 640 360"
              className="absolute inset-0 size-full"
              role="img"
              aria-label={t.sceneLabel}
            >
              <defs>
                <mask id="story-route">
                  <path data-route d={ROUTE} fill="none" stroke="white" strokeWidth="12" strokeLinecap="round" />
                </mask>
              </defs>

              {/* room */}
              <rect width="640" height={FLOOR - 50} fill="#fbe9dc" />
              <rect y={FLOOR - 50} width="640" height="110" fill="#ead6c3" />
              <rect y={FLOOR - 54} width="640" height="6" fill="#d9bfa8" />
              <rect x="60" y="50" width="110" height="90" rx="6" fill="#cfe6f7" stroke="#fff" strokeWidth="6" />
              <path d="M115 50 V140 M60 95 H170" stroke="#fff" strokeWidth="4" />
              {/* sofa */}
              <rect x="30" y="205" width="150" height="45" rx="12" fill="#a8574a" />
              <rect x="30" y="240" width="150" height="45" rx="10" fill="#b8665a" />
              <rect x="22" y="228" width="22" height="60" rx="8" fill="#9a4e42" />
              <rect x="166" y="228" width="22" height="60" rx="8" fill="#9a4e42" />
              {/* bookshelf */}
              <rect x="250" y="120" width="96" height="180" rx="4" fill="#8a5a3c" />
              {[160, 205, 250].map((y) => (
                <rect key={y} x="256" y={y} width="84" height="5" fill="#6e452c" />
              ))}
              {[
                [262, 132, "#3b5998"],
                [276, 138, "#c2185b"],
                [290, 128, "#f2b632"],
                [306, 136, "#7b2cbf"],
                [266, 180, "#42b72a"],
                [282, 176, "#3f4fc4"],
                [300, 184, "#a8431a"],
              ].map(([x, y, fill]) => (
                <rect key={`${x}-${y}`} x={x as number} y={y as number} width="12" height={(y as number) < 160 ? 160 - (y as number) : 205 - (y as number)} fill={fill as string} />
              ))}
              {/* kitchen table; the mug sits on it, the plant in front of where it hides */}
              <rect x="430" y={TABLE_TOP} width="190" height="10" rx="3" fill="#c48a5c" />
              <rect x="444" y={TABLE_TOP + 10} width="8" height={FLOOR - TABLE_TOP - 10} fill="#a8724a" />
              <rect x="598" y={TABLE_TOP + 10} width="8" height={FLOOR - TABLE_TOP - 10} fill="#a8724a" />

              <g data-mug transform={`translate(${MUG_AT.found} ${TABLE_TOP}) scale(${MUG_SCALE})`}>
                <g data-mug-body>
                  <HappyMug />
                </g>
              </g>
              <g data-plant>
                <path d="M522 214 q-18 -26 -4 -44 q10 16 4 44 M522 214 q16 -30 34 -30 q-6 22 -34 30 M522 214 q-26 -10 -36 -30 q24 2 36 30" fill="#42b72a" />
                <path d="M506 222 h32 l-4 28 h-24 z" fill="#d0743c" />
              </g>
              {[0, 1, 2].map((i) => (
                // placed by the outer group (just above the rim, across the mug); GSAP moves the inner one
                <g key={i} transform={`translate(${HEART_X[i]} ${MUG_RIM - 18})`}>
                  <g data-heart opacity="0">
                    <PixelIcon name="heart" size={18} />
                  </g>
                </g>
              ))}

              {/* "not here" marks */}
              <g data-cross="sofa" opacity="0" stroke="#c2185b" strokeWidth="6" strokeLinecap="round">
                <path d="M92 196 l20 20 M112 196 l-20 20" />
              </g>
              <g data-cross="shelf" opacity="0" stroke="#c2185b" strokeWidth="6" strokeLinecap="round">
                <path d="M288 92 l20 20 M308 92 l-20 20" />
              </g>

              {/* the route Recall gives, dotted, revealed by drawing the mask */}
              <path d={ROUTE} mask="url(#story-route)" fill="none" stroke="#3b5998" strokeWidth="5" strokeLinecap="round" strokeDasharray="0.1 12" />

              {/* Sam, with what he carries: thought bubble, phone and voice waves */}
              <g data-sam transform={`translate(${SAM_AT.table} ${SAM_TOP})`}>
                <g transform={`scale(${SAM_SCALE})`}>
                  <PixelSprite frames={SAM_FRAMES} palette={SAM_PALETTE} visible="wave" />
                </g>
                <g data-bubble opacity="0">
                  <circle cx="58" cy="-6" r="4" fill="#fff" />
                  <circle cx="68" cy="-18" r="6" fill="#fff" />
                  <rect x="70" y="-74" width="76" height="52" rx="18" fill="#fff" />
                  <g transform="translate(80 -66)">
                    <PixelIcon name="mug" size={34} />
                  </g>
                  <text x="128" y="-40" textAnchor="middle" dominantBaseline="central" fontSize="26" fontWeight="800" fill="#3b5998">
                    ?
                  </text>
                </g>
                <g data-phone opacity="0">
                  <rect x="60" y="40" width="12" height="20" rx="2" fill="#1c1e21" />
                  <rect x="62" y="43" width="8" height="12" fill="#8b9dc3" />
                  {[0, 1, 2].map((i) => (
                    <path key={i} data-wave d={`M${78 + i * 8} 40 q6 10 0 20`} fill="none" stroke="#3b5998" strokeWidth="3" strokeLinecap="round" />
                  ))}
                </g>
              </g>
            </svg>

            <p aria-hidden="true" className="pointer-events-none absolute inset-x-0 bottom-3 flex justify-center px-4">
              <span data-caption className="rounded-md bg-[#000000bf] px-3 py-1 text-center text-base font-bold text-[#fff] sm:text-lg">
                {t.captions.found}
              </span>
            </p>
            {ended && !reduced && (
              <button
                type="button"
                onClick={replay}
                className="absolute left-1/2 top-1/2 flex -translate-x-1/2 -translate-y-1/2 flex-col items-center gap-1 rounded-2xl bg-black/65 px-6 py-4 font-bold text-white hover:bg-black/80"
              >
                <ReplayIcon className="size-9" />
                {t.replay}
              </button>
            )}
          </div>

          {!reduced && (
            <div className="flex items-center gap-3 bg-ink px-4 py-2 text-white">
              <button
                type="button"
                onClick={toggle}
                aria-pressed={ended ? undefined : !playing}
                aria-label={ended ? t.replay : playing ? t.pause : t.play}
                className="grid size-11 place-items-center rounded-full hover:bg-white/15"
              >
                {ended ? (
                  <ReplayIcon className="size-5" />
                ) : (
                  <svg viewBox="0 0 16 16" className="size-4" aria-hidden="true" fill="currentColor">
                    {playing ? <path d="M3 2h4v12H3zM9 2h4v12H9z" /> : <path d="M4 2l10 6-10 6z" />}
                  </svg>
                )}
              </button>
              <button
                type="button"
                onClick={toggleSound}
                aria-pressed={sound}
                aria-label={sound ? t.soundOff : t.soundOn}
                className="grid size-11 place-items-center rounded-full hover:bg-white/15"
              >
                <svg viewBox="0 0 16 16" className="size-5" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M2 6h3l4-3v10l-4-3H2z" fill="currentColor" />
                  {sound ? <path d="M11.5 5.5a3.5 3.5 0 0 1 0 5M13.5 3.5a6.5 6.5 0 0 1 0 9" /> : <path d="M11 6l4 4M15 6l-4 4" />}
                </svg>
              </button>
              <input
                ref={slider}
                type="range"
                min={0}
                max={STORY_SECONDS * 10}
                step={1}
                defaultValue={STORY_SECONDS * 10}
                aria-label={t.position}
                aria-valuetext={format(t.positionValue, { current: time(STORY_SECONDS), total: time(STORY_SECONDS) })}
                onPointerDown={seekStart}
                onChange={seek}
                onPointerUp={seekEnd}
                onKeyUp={seekEnd}
                onBlur={seekEnd}
                className="h-11 min-w-0 flex-1 cursor-pointer accent-white"
              />
              <span data-clock className="font-classic text-sm tabular-nums" aria-hidden="true">
                {time(STORY_SECONDS)} / {time(STORY_SECONDS)}
              </span>
            </div>
          )}

          {reduced && (
            <div className="px-4 pt-4">
              <button type="button" onClick={() => sayLine(t.transcript, "narrator", { long: true })} className="btn btn-blue">
                <span aria-hidden="true">🔊</span> {t.listen}
              </button>
            </div>
          )}
          <p className={reduced ? "px-4 pt-4 text-lg leading-relaxed text-ink" : "sr-only"}>
            <span className="font-bold">{t.transcriptLabel} </span>
            {t.transcript}
          </p>

          <div className="mx-4 mt-3 flex items-center justify-between border-b border-fb-line pb-2.5 text-sm text-muted">
            <span className="flex items-center gap-1.5">
              <span aria-hidden="true">👍❤️</span>
              {128 + (liked ? 1 : 0)}
            </span>
            <span>{t.shares}</span>
          </div>
          <div className="mx-4 grid grid-cols-2 py-1">
            <button
              ref={likeButton}
              type="button"
              aria-pressed={liked}
              onClick={like}
              className={`flex min-h-11 items-center justify-center gap-2 rounded-lg font-bold hover:bg-fb-grey ${liked ? "text-fb-blue-dark" : "text-muted"}`}
            >
              <span aria-hidden="true">👍</span> {t.like}
            </button>
            <button type="button" className="flex min-h-11 items-center justify-center gap-2 rounded-lg font-bold text-muted hover:bg-fb-grey">
              <span aria-hidden="true">↗</span> {t.share}
            </button>
          </div>
        </article>
      </div>
    </section>
  );
}
