"use client";

import { useRef } from "react";
import { PixelIcon } from "@/components/ui/PixelIcon";
import { PostCard } from "@/components/ui/PostCard";
import { useT } from "@/i18n/I18nProvider";
import { gsap, MOTION_OK, ScrollTrigger, useGSAP } from "@/lib/gsap";
import { useA11yPrefs } from "@/lib/a11y-prefs";
import { useMotionPrefs } from "@/lib/motion-prefs";
import { oncePerPass } from "@/lib/once-per-pass";
import { useReactions } from "@/lib/reactions";
import { objectIcon } from "@/lib/pixel-icons";

const MAX_TURN = 38; // degrees a card turns away at the screen edge
const MAX_LEAN = 10; // extra degrees while scrolling fast

/**
 * The feed. Wide screens with motion: the section pins and the cards travel sideways as you scroll,
 * as a 3D coverflow (the middle card faces you, the rest turn away). Otherwise: a plain grid. GSAP only moves the <li> wrappers;
 * Motion owns everything inside a card.
 */
export function MemoryFeed() {
  const root = useRef<HTMLElement>(null);
  const track = useRef<HTMLDivElement>(null);
  const { reduced } = useMotionPrefs();
  const burst = useReactions();
  const t = useT();
  const posts = t.feed.posts;
  // large text would not fit the pinned row, so it gets the grid
  const largeText = useA11yPrefs().prefs.textScale > 1.25;

  useGSAP(
    () => {
      if (reduced) return;
      const section = root.current!;
      const mm = gsap.matchMedia();
      mm.add({ horizontal: `(min-width: 1024px) and (min-height: 640px) and ${MOTION_OK}`, motion: MOTION_OK }, (ctx) => {
        if (!ctx.conditions?.horizontal || largeText) {
          gsap.from("[data-feed-head] > *", {
            y: 20,
            autoAlpha: 0,
            stagger: 0.08,
            duration: 0.6,
            ease: "power2.out",
            scrollTrigger: { trigger: section, start: "top 75%", once: true },
          });
          ScrollTrigger.batch("[data-post]", {
            start: "top 88%",
            once: true,
            onEnter: (batch) =>
              gsap.from(batch, { y: 70, rotation: (i) => (i % 2 ? 2 : -2), autoAlpha: 0, stagger: 0.12, duration: 0.8, ease: "expo.out" }),
          });
          return;
        }

        // switch the markup to one long row (CSS keys off this attribute), then measure it
        section.dataset.horizontal = "true";
        const row = track.current!;
        const cards = gsap.utils.toArray<HTMLElement>("[data-post]");
        const count = section.querySelector<HTMLElement>("[data-count]")!;
        const distance = () => row.scrollWidth - document.documentElement.clientWidth;

        // fast scrolling adds a little extra turn in the scroll direction, then settles
        const motion = { lean: 0 };
        const setLean = gsap.quickTo(motion, "lean", { duration: 0.5, ease: "power3.out" });
        const settle = gsap.delayedCall(0.12, () => setLean(0)).pause();

        // companion: the object of the card in the middle floats on that card's corner, like a
        // sticker, and swaps when the next card arrives
        const companion = section.querySelector<HTMLElement>("[data-companion]")!;
        const stickers = gsap.utils.toArray<HTMLElement>("[data-sticker]");
        let active = -1;
        // finale: reaching the last memory sets off a crowd of reactions, once per pass; going back
        // to the first half of the row re-arms it
        const finale = oncePerPass();
        const swap = (next: number) => {
          if (next === active) return;
          if (next >= 0 && next <= 2) finale.rearm();
          if (next === cards.length - 1)
            finale.fire(() =>
              burst({
                from: { x: window.innerWidth / 2, y: window.innerHeight },
                items: ["heartHands", "mug", "cool", "love", "star", "heart", "like", "key", "phone"],
                count: 22,
                celebrate: true,
                until: section,
              }),
            );
          if (active >= 0) gsap.to(stickers[active], { scale: 0, y: 16, autoAlpha: 0, duration: 0.25, ease: "power2.in", overwrite: true });
          if (next >= 0)
            gsap.fromTo(
              stickers[next],
              { scale: 0, y: -10, rotation: -20, autoAlpha: 0 },
              { scale: 1, y: 0, rotation: 0, autoAlpha: 1, duration: 0.45, ease: "back.out(2.5)", overwrite: true },
            );
          active = next;
        };
        gsap.to("[data-bob]", { y: -8, rotation: 5, duration: 1.2, yoyo: true, repeat: -1, ease: "sine.inOut" });

        // card centres along the row, measured on refresh so the frame loop never reads layout
        let centres: number[] = [];
        let cardHalf = 0;
        const measure = () => {
          // offsetLeft is relative to the <ul> (its 3D perspective makes it the offset parent), so
          // add where the list starts inside the row; both rects carry the same x, which cancels
          const list = cards[0].parentElement!;
          const listLeft = list.getBoundingClientRect().left - row.getBoundingClientRect().left;
          centres = cards.map((c) => listLeft + c.offsetLeft + c.offsetWidth / 2);
          // the sticker rides the top-right corner of whichever card is nearest the middle
          cardHalf = cards[0].offsetWidth / 2;
          gsap.set(companion, { top: section.clientHeight / 2 - cards[0].offsetHeight / 2 - 36 });
        };
        measure();

        // coverflow: the card at the middle of the screen faces you, the others turn away and sink back
        const render = () => {
          const half = document.documentElement.clientWidth / 2;
          const x = Number(gsap.getProperty(row, "x"));
          let nearest = -1;
          let nearestD = Infinity;
          cards.forEach((card, i) => {
            const d = gsap.utils.clamp(-1, 1, (centres[i] + x - half) / half);
            if (Math.abs(d) < nearestD) {
              nearestD = Math.abs(d);
              nearest = i;
            }
            gsap.set(card, {
              rotationY: -d * MAX_TURN + motion.lean,
              z: -Math.abs(d) * 220,
              opacity: 1 - 0.4 * Math.abs(d),
              zIndex: Math.round(10 - Math.abs(d) * 10),
            });
          });
          swap(nearestD < 0.35 ? nearest : -1);
          if (nearest >= 0) gsap.set(companion, { x: centres[nearest] + x + cardHalf - 44 });
        };

        // the pin runs a little past the last card, so the final card (and its sticker) holds in
        // the middle before the section scrolls away; the row stops moving at `distance`
        const hold = () => window.innerHeight * 0.35;
        gsap.to(row, {
          x: () => -(distance() + hold()),
          ease: "none",
          modifiers: { x: (x: string) => `${Math.max(parseFloat(x), -distance())}px` },
          scrollTrigger: {
            trigger: section,
            start: "top top",
            end: () => `+=${distance() + hold()}`,
            pin: true,
            scrub: 0.6,
            invalidateOnRefresh: true,
            onRefresh: measure,
            onUpdate: (self) => {
              // lean into the scroll: direction gives the side, velocity how far
              const lean = gsap.utils.clamp(0, MAX_LEAN, Math.abs(self.getVelocity()) / 200);
              setLean(-self.direction * lean);
              settle.restart(true);
              const moving = distance() / (distance() + hold()); // share of the pin spent scrolling
              count.textContent = String(Math.round(Math.min(1, self.progress / moving) * (cards.length - 1)) + 1);
            },
          },
        });

        gsap.fromTo("[data-feed-progress]", { scaleX: 0 }, {
          scaleX: 1,
          ease: "none",
          scrollTrigger: { trigger: section, start: "top top", end: () => `+=${distance()}`, scrub: true, invalidateOnRefresh: true },
        });

        // run the coverflow only while the feed is on screen
        render();
        const visible = ScrollTrigger.create({
          trigger: section,
          start: "top bottom",
          end: () => `+=${distance() + window.innerHeight * 2}`,
          onToggle: (self) => (self.isActive ? gsap.ticker.add(render) : gsap.ticker.remove(render)),
        });

        return () => {
          gsap.ticker.remove(render);
          visible.kill();
          settle.kill();
          // the stickers are tweened from the frame loop, outside this context, so reset by hand
          gsap.killTweensOf(stickers);
          gsap.set(stickers, { clearProps: "all" });
          gsap.set(cards, { clearProps: "transform,opacity,zIndex" });
          delete section.dataset.horizontal;
          count.textContent = "1";
        };
      });
      return () => mm.revert();
    },
    { scope: root, dependencies: [reduced, largeText, burst], revertOnUpdate: true },
  );

  return (
    <section
      ref={root}
      id="feed"
      aria-labelledby="feed-title"
      className="group relative scroll-mt-20 overflow-hidden py-24 data-[horizontal=true]:flex data-[horizontal=true]:h-dvh data-[horizontal=true]:flex-col data-[horizontal=true]:justify-center data-[horizontal=true]:py-0"
    >
      <div
        ref={track}
        className="mx-auto max-w-6xl px-4 group-data-[horizontal=true]:mx-0 group-data-[horizontal=true]:flex group-data-[horizontal=true]:w-max group-data-[horizontal=true]:max-w-none group-data-[horizontal=true]:items-center group-data-[horizontal=true]:gap-8 group-data-[horizontal=true]:pl-[max(1rem,calc((100vw-72rem)/2+1rem))] group-data-[horizontal=true]:pr-[calc(50vw-12rem)]"
      >
        <div data-feed-head className="max-w-2xl group-data-[horizontal=true]:w-[26rem] group-data-[horizontal=true]:shrink-0">
          <p className="classic-label">{t.feed.eyebrow}</p>
          <h2 id="feed-title" className="mt-4 text-4xl font-extrabold text-ink sm:text-5xl">
            {t.feed.title}
          </h2>
          <p className="mt-4 text-lg leading-relaxed text-muted">
            {t.feed.intro}
          </p>
          <p aria-hidden="true" className="mt-6 hidden font-classic text-sm font-bold text-fb-blue-dark group-data-[horizontal=true]:block">
            {t.feed.keepScrolling} <span className="inline-block">→</span>
          </p>
        </div>

        <ul className="mt-12 grid gap-8 md:grid-cols-2 lg:grid-cols-3 group-data-[horizontal=true]:mt-0 group-data-[horizontal=true]:flex group-data-[horizontal=true]:[perspective:1400px]">
          {posts.map((post) => (
            <li key={post.id} data-post data-object={post.id} className="group-data-[horizontal=true]:w-[24rem] group-data-[horizontal=true]:shrink-0">
              <PostCard post={post} />
            </li>
          ))}
        </ul>
      </div>

      {/* the floating sticker for the card in the middle (coverflow only) */}
      <div data-companion aria-hidden="true" className="pointer-events-none absolute left-0 top-0 z-20 hidden size-[72px] group-data-[horizontal=true]:block">
        <div data-bob className="relative size-full">
          {posts.map((post) => (
            <div
              key={post.id}
              data-sticker
              className="invisible absolute inset-0 grid place-items-center rounded-full border-4 border-white bg-fb-blue-pale shadow-[var(--shadow-lift)]"
            >
              <PixelIcon name={objectIcon[post.id]} size={44} />
            </div>
          ))}
        </div>
      </div>

      <div
        aria-hidden="true"
        className="absolute inset-x-0 bottom-8 mx-auto hidden max-w-6xl items-center gap-4 px-4 group-data-[horizontal=true]:flex"
      >
        <div className="h-1 flex-1 overflow-hidden rounded-full bg-fb-blue-pale">
          <div data-feed-progress className="h-full origin-left rounded-full bg-fb-blue" />
        </div>
        <p className="font-classic text-sm font-bold tabular-nums text-fb-blue-dark">
          <span data-count>1</span> / {posts.length}
        </p>
      </div>
    </section>
  );
}
