"use client";

import { AnimatePresence, motion } from "motion/react";
import { useId, useRef, useState } from "react";
import type { MemoryPost } from "@/content/posts";
import { format } from "@/i18n";
import { useT } from "@/i18n/I18nProvider";
import { useReactions, type ReactionItem } from "@/lib/reactions";
import { SceneTile } from "./SceneTile";

/** A memory as a social post: the object is the author, its last sighting is the update. */
export function PostCard({ post }: { post: MemoryPost }) {
  const [trayOpen, setTrayOpen] = useState(false);
  const t = useT();
  const reactions = t.feed.reactions;
  const [reaction, setReaction] = useState<(typeof reactions)[number] | null>(null);
  const closeTimer = useRef<number | undefined>(undefined);
  const trayId = useId();
  const likeButton = useRef<HTMLButtonElement>(null);
  const burst = useReactions();

  const open = () => {
    window.clearTimeout(closeTimer.current);
    setTrayOpen(true);
  };
  const closeSoon = () => {
    window.clearTimeout(closeTimer.current);
    closeTimer.current = window.setTimeout(() => setTrayOpen(false), 220);
  };
  const pick = (r: (typeof reactions)[number]) => {
    setReaction(r);
    // the reaction floats up the screen from the Like button, like a meeting reaction
    if (likeButton.current) {
      const items: ReactionItem[] =
        r.id === "like" ? ["like", "like", "like", "like", "heart"] : r.id === "love" ? ["love", "heart", "heart"] : [{ emoji: r.emoji }];
      burst({ from: likeButton.current, items, count: 10 });
    }
    setTrayOpen(false);
  };

  const [a, b, ...rest] = post.tiles;

  return (
    <article aria-label={format(t.feed.postLabel, { object: post.object, seen: post.seen })} className="card flex h-full flex-col overflow-hidden">
      <header className="flex items-center gap-3 px-4 pt-4">
        <span className="ig-ring grid size-12 shrink-0 place-items-center rounded-full p-[3px]">
          <span className="grid size-full place-items-center rounded-full bg-white text-2xl" aria-hidden="true">
            {post.emoji}
          </span>
        </span>
        <div className="min-w-0">
          <p className="flex items-center gap-1.5 font-bold text-ink">
            {post.object}
            <svg viewBox="0 0 16 16" className="size-4 text-fb-blue" aria-label={t.feed.seenBy} role="img">
              <circle cx="8" cy="8" r="8" fill="currentColor" />
              <path d="M4.5 8.2 7 10.5l4.5-5" stroke="white" strokeWidth="1.8" fill="none" strokeLinecap="round" />
            </svg>
          </p>
          <p className="text-sm text-muted">
            {post.seen} · <span aria-hidden="true">🏠</span> {post.room}
          </p>
        </div>
        <span aria-hidden="true" className="ml-auto text-xl tracking-widest text-muted">
          ···
        </span>
      </header>

      <p className="flex-1 px-4 pt-3 text-[1.05rem] leading-relaxed text-ink">
        {post.text}{" "}
        {post.tags.map((t) => (
          <span key={t} className="font-bold text-fb-blue-dark">
            #{t}{" "}
          </span>
        ))}
      </p>

      <div className="mt-3 grid grid-cols-6 gap-0.5 bg-white" aria-hidden="true">
        <div className="col-span-3 aspect-square overflow-hidden">
          <SceneTile scene={a} />
        </div>
        <div className="col-span-3 aspect-square overflow-hidden">
          <SceneTile scene={b} />
        </div>
        {rest.map((scene, i) => (
          <div key={i} className="relative col-span-2 aspect-square overflow-hidden">
            <SceneTile scene={scene} />
            {i === rest.length - 1 && post.more > 0 && (
              <span className="absolute inset-0 grid place-items-center bg-black/45 text-3xl font-bold text-white">
                +{post.more}
              </span>
            )}
          </div>
        ))}
      </div>

      <div className="flex items-center justify-between px-4 py-2.5 text-sm text-muted">
        <span className="flex items-center gap-1.5">
          <span aria-hidden="true">👍❤️</span>
          {post.reactions + (reaction ? 1 : 0)}
        </span>
        <span>
          {format(t.feed.stats, { asks: post.asks, sightings: post.more + post.tiles.length })}
        </span>
      </div>

      <div className="relative mx-4 grid grid-cols-3 border-t border-fb-line py-1">
        <div className="relative" onMouseEnter={open} onMouseLeave={closeSoon}>
          <AnimatePresence>
            {trayOpen && (
              <motion.div
                id={trayId}
                role="group"
                aria-label={t.feed.reactionsLabel}
                variants={{
                  hidden: { opacity: 0, y: 12, scale: 0.85 },
                  shown: { opacity: 1, y: 0, scale: 1, transition: { type: "spring", stiffness: 520, damping: 28, staggerChildren: 0.035 } },
                }}
                initial="hidden"
                animate="shown"
                exit="hidden"
                onMouseEnter={open}
                onMouseLeave={closeSoon}
                onKeyDown={(e) => e.key === "Escape" && setTrayOpen(false)}
                className="absolute bottom-full left-0 z-10 mb-2 flex gap-1 rounded-full bg-white p-1.5 shadow-[var(--shadow-lift)]"
              >
                {reactions.map((r) => (
                  <motion.button
                    key={r.id}
                    type="button"
                    aria-label={r.label}
                    variants={{ hidden: { y: 14, opacity: 0 }, shown: { y: 0, opacity: 1 } }}
                    whileHover={{ scale: 1.35, y: -6 }}
                    whileFocus={{ scale: 1.35, y: -6 }}
                    onClick={() => pick(r)}
                    className="grid size-11 place-items-center rounded-full text-[1.7rem]"
                  >
                    <span aria-hidden="true">{r.emoji}</span>
                  </motion.button>
                ))}
              </motion.div>
            )}
          </AnimatePresence>
          <button
            ref={likeButton}
            type="button"
            aria-expanded={trayOpen}
            aria-controls={trayId}
            onClick={() => (reaction ? setReaction(null) : setTrayOpen((v) => !v))}
            onFocus={open}
            className={`flex min-h-11 w-full items-center justify-center gap-2 rounded-lg font-bold hover:bg-fb-grey ${
              reaction ? "text-fb-blue-dark" : "text-muted"
            }`}
          >
            <span aria-hidden="true">{reaction ? reaction.emoji : "👍"}</span>
            {reaction ? reaction.label : reactions[0].label}
          </button>
        </div>
        <button type="button" className="flex min-h-11 items-center justify-center gap-2 rounded-lg font-bold text-muted hover:bg-fb-grey">
          <span aria-hidden="true">🧭</span> {t.feed.guideMe}
        </button>
        <button type="button" className="flex min-h-11 items-center justify-center gap-2 rounded-lg font-bold text-muted hover:bg-fb-grey">
          <span aria-hidden="true">↗</span> {t.feed.share}
        </button>
      </div>
    </article>
  );
}
