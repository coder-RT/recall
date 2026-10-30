"use client";

import { createContext, useCallback, useContext, useEffect, useRef, type ReactNode } from "react";
import { gsap } from "./gsap";
import { useMotionPrefs } from "./motion-prefs";
import { pixelSvg, type PixelIconName } from "./pixel-icons";

export type ReactionItem = PixelIconName | { emoji: string };

export interface BurstOptions {
  /** Where the burst starts: an element (its centre) or a viewport point. */
  from: Element | { x: number; y: number };
  /** Icons to pick from, cycled. */
  items: ReactionItem[];
  count?: number;
  /** One large icon that leads the burst, e.g. the object that was just found. */
  hero?: PixelIconName;
  /**
   * A celebration: reactions rise as a crowd from the whole bottom edge. With a hero (a "found"
   * moment), the hero first flies to the middle of the screen, grows and pops, then floats away.
   */
  celebrate?: boolean;
  /**
   * The section this burst belongs to: once it is mostly off screen, the burst fades out, so
   * reactions never drift over the next section after the visitor scrolls on.
   */
  until?: Element;
}

const MAX_LIVE = 40;

const ReactionsContext = createContext<(options: BurstOptions) => void>(() => {});

/**
 * Teams-style floating reactions: icons rise up the whole screen from where something happened.
 * One fixed overlay for the page; GSAP animates the particles and nothing else touches them.
 * Off under reduced motion.
 */
export function ReactionsProvider({ children }: { children: ReactNode }) {
  const layer = useRef<HTMLDivElement>(null);
  const live = useRef<{ el: HTMLElement; tl: gsap.core.Timeline }[]>([]);
  const celebratingUntil = useRef(0);
  const { reduced } = useMotionPrefs();
  // read inside burst, so burst keeps one identity and callers can list it as a stable dependency
  const reducedRef = useRef(reduced);
  useEffect(() => {
    reducedRef.current = reduced;
  }, [reduced]);

  const remove = useCallback((el: HTMLElement) => {
    live.current = live.current.filter((p) => p.el !== el);
    el.remove();
  }, []);

  const run = useCallback(
    ({ items, count = 8, hero, celebrate, until }: BurstOptions, origin: { x: number; y: number }) => {
      const root = layer.current;
      if (!root) return;
      const { random } = gsap.utils;
      const W = window.innerWidth;
      const H = window.innerHeight;

      // everything this burst creates, so it can be faded out together
      const group: { el: HTMLElement; tl: gsap.core.Timeline }[] = [];
      const track = (el: HTMLElement, tl: gsap.core.Timeline) => {
        group.push({ el, tl });
        live.current.push({ el, tl });
        while (live.current.length > MAX_LIVE) {
          const oldest = live.current.shift()!;
          oldest.tl.kill();
          oldest.el.remove();
        }
      };

      const make = (item: ReactionItem, size: number) => {
        const el = document.createElement("div");
        el.style.cssText = `position:absolute;left:0;top:0;width:${size}px;height:${size}px;display:grid;place-items:center;will-change:transform`;
        if (typeof item === "string") el.innerHTML = pixelSvg(item, size);
        else {
          el.textContent = item.emoji;
          el.style.fontSize = `${size * 0.85}px`;
          el.style.lineHeight = "1";
        }
        root.appendChild(el);
        return el;
      };

      // one reaction: pops in at `start`, then rises a share of the screen height, swaying
      const launch = (item: ReactionItem, size: number, delay: number, start = origin, rise = random(0.55, 0.85)) => {
        const el = make(item, size);
        const x0 = start.x - size / 2 + random(-24, 24);
        const sway = random(18, 56) * (Math.random() < 0.5 ? -1 : 1);
        const duration = random(2.2, 3.2);
        gsap.set(el, { x: x0, y: start.y - size / 2, scale: 0 });
        const tl = gsap.timeline({ delay, onComplete: () => remove(el) });
        tl.to(el, { scale: 1, duration: 0.35, ease: "back.out(3)" }, 0)
          .to(el, { y: `-=${rise * H}`, duration, ease: "power1.out" }, 0)
          .to(el, { keyframes: { x: [x0 + sway, x0 - sway, x0 + sway * 0.5], rotation: [12, -12, 0] }, duration, ease: "sine.inOut" }, 0)
          .to(el, { opacity: 0, duration: duration * 0.3, ease: "power1.in" }, duration * 0.7);
        track(el, tl);
      };

      const celebrating = Boolean(celebrate);
      // one celebration at a time: a second while one plays would stack in the middle
      if (celebrating && performance.now() < celebratingUntil.current) return;
      if (celebrating) celebratingUntil.current = performance.now() + 2600;
      if (celebrating && hero) {
        // the found object travels to the middle of the screen, grows, pops, holds, then floats away
        const size = 72;
        const grow = 2.2;
        const centre = { x: W / 2, y: H / 2 };
        const el = make(hero, size);
        gsap.set(el, { x: origin.x - size / 2, y: origin.y - size / 2, scale: 0 });
        const tl = gsap.timeline({ onComplete: () => remove(el) });
        // x and y ease differently, so the flight bends into an arc
        tl.to(el, { scale: 1, duration: 0.3, ease: "back.out(3)" })
          .to(el, { x: centre.x - size / 2, duration: 0.9, ease: "power2.inOut" }, 0.25)
          .to(el, { y: centre.y - size / 2, duration: 0.9, ease: "power3.out" }, 0.25)
          .to(el, { scale: grow, duration: 0.9, ease: "power2.inOut" }, 0.25)
          .to(el, { scale: grow * 1.15, duration: 0.14, yoyo: true, repeat: 1, ease: "power1.out" })
          .to(el, { y: `-=${H * 0.6}`, opacity: 0, duration: 1.8, ease: "power1.in" }, "+=0.6");
        track(el, tl);

        // one soft ring when it lands
        const ringSize = size * grow;
        const ring = document.createElement("div");
        ring.style.cssText = `position:absolute;left:0;top:0;width:${ringSize}px;height:${ringSize}px;border:4px solid #3b5998;border-radius:9999px`;
        root.appendChild(ring);
        gsap.set(ring, { x: centre.x - ringSize / 2, y: centre.y - ringSize / 2, scale: 0.6, opacity: 0 });
        const ringTl = gsap.timeline({ delay: 1.15, onComplete: () => remove(ring) });
        ringTl.to(ring, { opacity: 0.6, duration: 0.05 }).to(ring, { scale: 1.8, opacity: 0, duration: 0.8, ease: "power2.out" });
        track(ring, ringTl);

      }
      if (celebrating) {
        // the crowd: reactions rising from the whole bottom edge (after the hero lands, if any)
        const start = hero ? 1.2 : 0;
        for (let i = 0; i < count; i++) {
          launch(items[i % items.length], random(30, 46, 1), start + i * 0.09 + random(0, 0.08), { x: random(0.05, 0.95) * W, y: H + 24 }, random(0.8, 1.1));
        }
      } else {
        if (hero) launch(hero, 72, 0);
        for (let i = 0; i < count; i++) launch(items[i % items.length], random(28, 42, 1), (hero ? 0.25 : 0) + i * 0.07 + random(0, 0.05));
      }

      if (until) {
        // fires once straight away (catching a fast scroll-past), then on every threshold change
        const watch = new IntersectionObserver(
          ([entry]) => {
            if (entry.intersectionRatio >= 0.25) return;
            watch.disconnect();
            if (celebrating) celebratingUntil.current = 0;
            group.forEach(({ el, tl }) => {
              tl.kill();
              gsap.to(el, { opacity: 0, duration: 0.3, onComplete: () => remove(el) });
            });
          },
          { threshold: [0, 0.25] },
        );
        watch.observe(until);
        window.setTimeout(() => watch.disconnect(), 6000); // the burst is over by then
      }
    },
    [remove],
  );

  const burst = useCallback(
    (options: BurstOptions) => {
      if (reducedRef.current || !options.items.length) return;
      // measure now, animate next frame: a caller may be inside a GSAP context (useGSAP,
      // matchMedia), and particles created there would be reverted, frozen, with that context
      const { from } = options;
      const box = from instanceof Element ? from.getBoundingClientRect() : null;
      const origin = box ? { x: box.left + box.width / 2, y: box.top + box.height / 2 } : (from as { x: number; y: number });
      requestAnimationFrame(() => run(options, origin));
    },
    [run],
  );

  useEffect(
    () => () => {
      live.current.forEach((p) => {
        p.tl.kill();
        p.el.remove();
      });
      live.current = [];
    },
    [],
  );

  return (
    <ReactionsContext.Provider value={burst}>
      {children}
      <div ref={layer} data-reactions aria-hidden="true" className="pointer-events-none fixed inset-0 z-40 overflow-hidden" />
    </ReactionsContext.Provider>
  );
}

/** Send a burst of floating reactions. A no-op outside ReactionsProvider or under reduced motion. */
export const useReactions = () => useContext(ReactionsContext);
