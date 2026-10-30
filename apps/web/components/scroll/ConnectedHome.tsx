"use client";

import { useId, useRef } from "react";
import { PixelSprite } from "@/components/scroll/story/PixelSprite";
import { PixelIcon } from "@/components/ui/PixelIcon";
import { useT } from "@/i18n/I18nProvider";
import { gsap, MOTION_OK, useGSAP } from "@/lib/gsap";
import { useMotionPrefs } from "@/lib/motion-prefs";
import type { PixelIconName } from "@/lib/pixel-icons";
import { SAM_FRAMES, SAM_PALETTE } from "@/lib/pixel-sprites";

/**
 * The hero's "connected home": Recall's take on the 2008 Facebook map of people joined by dotted
 * arcs. Sam sits in the middle of his home, linked to the things Recall remembers for him, with
 * today's Facebook touches: tilted memory cards with a time chip, and round emoji badges.
 * With motion on, Sam leaves his circle and walks the arcs from thing to thing while the floor lights up blue
 * around him like a LiDAR scan; each thing he reaches pings, and its card says "just now".
 * Decorative (the hero text says it all); the markup is the finished, still picture.
 */

const W = 1152;
const H = 230;
const SAM = { x: 520, y: 120 };

// the things around Sam, as avatar pins
const OBJECTS: { icon: PixelIconName; x: number; y: number }[] = [
  { icon: "key", x: 120, y: 78 },
  { icon: "wallet", x: 250, y: 178 },
  { icon: "remote", x: 330, y: 58 },
  { icon: "mug", x: 730, y: 172 },
  { icon: "glasses", x: 880, y: 70 },
  { icon: "phone", x: 1060, y: 92 },
];
// extra links between things, as index pairs
const SIDE_LINKS = [
  [0, 1],
  [0, 2],
  [3, 4],
  [4, 5],
];
// round emoji badges floating around the map
const EMOJIS: { icon: PixelIconName; x: number; y: number }[] = [
  { icon: "heartHands", x: 40, y: 168 },
  { icon: "cool", x: 420, y: 196 },
  { icon: "love", x: 810, y: 190 },
  { icon: "like", x: 1112, y: 196 },
];
// memory cards: which post's object and "last seen" time they show (feed.posts ids)
const CARDS = [
  { post: "keys", icon: "key" as PixelIconName, x: 588, y: 14, rotate: -5 },
  { post: "mug", icon: "mug" as PixelIconName, x: 900, y: 146, rotate: 4 },
];
// the rooms, and where their label sits (top corner clear of pins and arcs)
const ROOMS = [
  { x: 16, y: 26, width: 372, height: 188, label: { x: 36, y: 46, anchor: "start" } },
  { x: 404, y: 8, width: 352, height: 214, label: { x: 424, y: 28, anchor: "start" } },
  { x: 772, y: 30, width: 366, height: 186, label: { x: 1118, y: 50, anchor: "end" } },
] as const;

type Point = { x: number; y: number };

/** The control point of the arc between a and b (the same either way round). */
const bend = (a: Point, b: Point) => ({ x: (a.x + b.x) / 2, y: Math.min(a.y, b.y) - 46 });

/** A dotted arc from a to b, bowing upwards. */
const arc = (a: Point, b: Point) => {
  const c = bend(a, b);
  return `M${a.x} ${a.y} Q${c.x} ${c.y} ${b.x} ${b.y}`;
};

/** Points along the arc from a to b, with the distance walked to each. */
function arcPoints(a: Point, b: Point, steps = 48) {
  const c = bend(a, b);
  const points: (Point & { d: number })[] = [];
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    const x = (1 - t) ** 2 * a.x + 2 * (1 - t) * t * c.x + t ** 2 * b.x;
    const y = (1 - t) ** 2 * a.y + 2 * (1 - t) * t * c.y + t ** 2 * b.y;
    const prev = points[i - 1];
    points.push({ x, y, d: prev ? prev.d + Math.hypot(x - prev.x, y - prev.y) : 0 });
  }
  return points;
}

/** The point `d` along a walk from arcPoints. */
function pointAt(points: (Point & { d: number })[], d: number): Point {
  const found = points.findIndex((p) => p.d >= d);
  if (found === -1) return points[points.length - 1]; // at (or a rounding hair past) the end
  const i = Math.max(1, found);
  const a = points[i - 1];
  const b = points[i];
  const t = b.d > a.d ? (d - a.d) / (b.d - a.d) : 0;
  return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t };
}

// Sam's walk along the links, as stops (null = back home in the middle)
const WALK: (PixelIconName | null)[] = ["remote", "key", "wallet", null, "mug", "glasses", "phone", null];
const WALK_SPEED = 120; // svg units a second
const WALK_PAUSE = 0.45; // seconds at each stop
const TRAIL = 14; // scanned spots left behind him, reused in turn
const TRAIL_GAP = 34; // svg units walked between spots
const STEP = 9; // svg units per footstep (walk frames swap)
const JUST_NOW = 3; // seconds a card says "just now"

const DOT_GAP = 11; // dash period of the dotted links

/** Width of a card's time chip for its text. */
const chipWidth = (text: string) => 34 + text.length * 6.4;

export function ConnectedHome() {
  const root = useRef<SVGSVGElement>(null);
  const { reduced } = useMotionPrefs();
  const t = useT();
  const posts = t.feed.posts;
  const justNow = t.hero.justNow;
  const id = useId().replace(/:/g, "");

  useGSAP(
    () => {
      if (reduced) return;
      const mm = gsap.matchMedia();
      mm.add(MOTION_OK, () => {
        // appears once the wordmark has formed: pins from the middle out, then links, cards, emojis
        const intro = gsap.timeline({ delay: 2.4 });
        intro
          .from("[data-node] > g", { scale: 0, transformOrigin: "50% 50%", duration: 0.45, ease: "back.out(2.5)", stagger: { each: 0.07, from: "center" } })
          .from("[data-link]", { opacity: 0, duration: 0.5, stagger: 0.05 }, 0.2)
          .from("[data-mini-card] > g", { y: 24, opacity: 0, duration: 0.5, ease: "power3.out", stagger: 0.12 }, 0.35)
          .from("[data-emoji] > g", { scale: 0, transformOrigin: "50% 50%", duration: 0.4, ease: "back.out(3)", stagger: 0.08 }, 0.5);

        // always-on life, only while the hero is on screen: dots flow out from Sam, emojis bob
        const life = gsap.timeline({
          paused: true,
          scrollTrigger: { trigger: root.current, start: "top bottom", end: "bottom top", toggleActions: "play pause resume pause" },
        });
        life
          .to("[data-link]", { strokeDashoffset: -DOT_GAP, duration: 0.7, ease: "none", repeat: -1 }, 0)
          .to("[data-emoji] > g > g", { y: -6, duration: 1.4, ease: "sine.inOut", yoyo: true, repeat: -1, stagger: 0.35 }, 0);

        // Sam walks his home once the band is in, and the floor gets scanned around him
        const svg = root.current!;
        const all = <E extends Element>(selector: string) => [...svg.querySelectorAll<E>(selector)];
        const walker = svg.querySelector<SVGGElement>("[data-walker]")!;
        const home = svg.querySelector<SVGGElement>("[data-home-sam]")!;
        // only one Sam at a time: his circle is empty while he is out
        const out = (away: boolean) => {
          gsap.set(home, { opacity: away ? 0 : 1 });
          gsap.set(walker, { opacity: away ? 1 : 0 });
        };
        const [frameA, frameB] = ["walkA", "walkB"].map((f) => walker.querySelector(`[data-frame="${f}"]`)!);
        const glow = svg.querySelector<SVGCircleElement>("[data-scan-glow]")!;
        const trail = all<SVGCircleElement>("[data-trail]");
        const pings = all<SVGCircleElement>("[data-ping]");
        let spot = 0;

        const place = (p: Point, dir: number, walked: number) => {
          walker.setAttribute("transform", `translate(${p.x.toFixed(1)} ${p.y.toFixed(1)}) scale(${dir} 1)`);
          glow.setAttribute("cx", p.x.toFixed(1));
          glow.setAttribute("cy", p.y.toFixed(1));
          const left = Math.floor(walked / STEP) % 2 === 0;
          frameA.setAttribute("opacity", left ? "1" : "0");
          frameB.setAttribute("opacity", left ? "0" : "1");
        };
        const drop = (p: Point) => {
          const c = trail[spot++ % trail.length];
          gsap.fromTo(c, { attr: { cx: p.x, cy: p.y }, opacity: 0.9 }, { opacity: 0, duration: 2.5, ease: "power1.in", overwrite: true });
        };
        const chips = all<SVGGElement>("[data-chip]");
        const restore = (chip: SVGGElement) => {
          chip.querySelector("text")!.textContent = chip.dataset.seen ?? "";
          chip.querySelector("rect")!.setAttribute("width", chip.dataset.width ?? "");
        };
        const arrive = (stop: PixelIconName | null) => {
          if (!stop) {
            out(false);
            return;
          }
          gsap.fromTo(pings.filter((p) => p.dataset.ping === stop), { attr: { r: 30 }, opacity: 0.9 }, { attr: { r: 56 }, opacity: 0, duration: 0.9, ease: "power2.out" });
          const chip = chips.find((c) => c.dataset.icon === stop);
          if (!chip) return;
          chip.querySelector("text")!.textContent = justNow;
          chip.querySelector("rect")!.setAttribute("width", String(chipWidth(justNow)));
          gsap.killTweensOf(restore); // a call queued from an earlier visit
          gsap.delayedCall(JUST_NOW, restore, [chip]);
        };

        const walk = gsap.timeline({ repeat: -1 });
        walk.set(glow, { opacity: 1 }, 0);
        let from: Point = SAM;
        for (const stop of WALK) {
          const to = stop ? OBJECTS.find((o) => o.icon === stop)! : SAM;
          const points = arcPoints(from, to);
          const length = points[points.length - 1].d;
          const dir = to.x < from.x ? -1 : 1;
          const start = from;
          const step = { d: 0 };
          let dropped = 0;
          walk.to(step, {
            d: length,
            duration: length / WALK_SPEED,
            ease: "none",
            onStart: () => {
              step.d = 0;
              dropped = 0;
              if (start === SAM) out(true);
            },
            onUpdate: () => {
              const p = pointAt(points, step.d);
              place(p, dir, step.d);
              if (step.d - dropped >= TRAIL_GAP) {
                dropped = step.d;
                drop(p);
              }
            },
          });
          walk.call(arrive, [stop]).to({}, { duration: WALK_PAUSE });
          from = to;
        }
        life.add(walk, 3.9); // after the entrance

        return () => {
          gsap.killTweensOf([...trail, ...pings, restore]);
          gsap.set([...trail, ...pings, walker], { opacity: 0 });
          gsap.set(home, { opacity: 1 });
          chips.forEach(restore);
        };
      });
      return () => mm.revert();
    },
    { scope: root, dependencies: [reduced], revertOnUpdate: true },
  );

  const pin = (child: React.ReactNode) => (
    <>
      <circle r="30" fill={`url(#${id}-ring)`} />
      <circle r="26" fill="#fff" />
      {child}
    </>
  );

  return (
    <svg
      ref={root}
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="xMidYMid slice"
      aria-hidden="true"
      className="h-[200px] w-full sm:h-auto sm:overflow-visible"
    >
      <defs>
        <linearGradient id={`${id}-ring`} x1="0" y1="1" x2="1" y2="0">
          <stop offset="0" stopColor="#feda75" />
          <stop offset="0.35" stopColor="#fa7e1e" />
          <stop offset="0.6" stopColor="#d62976" />
          <stop offset="0.85" stopColor="#962fbf" />
          <stop offset="1" stopColor="#4f5bd5" />
        </linearGradient>
        <pattern id={`${id}-dots`} width="14" height="14" patternUnits="userSpaceOnUse">
          <circle cx="7" cy="7" r="1.4" fill="#d3d9e6" />
        </pattern>
        {/* the same dots, scanned: shown only where the scan mask is lit */}
        <pattern id={`${id}-scanned`} width="14" height="14" patternUnits="userSpaceOnUse">
          <circle cx="7" cy="7" r="2.2" fill="#1877f2" />
        </pattern>
        <radialGradient id={`${id}-glow`}>
          <stop offset="0" stopColor="#fff" />
          <stop offset="0.55" stopColor="#fff" stopOpacity="0.7" />
          <stop offset="1" stopColor="#fff" stopOpacity="0" />
        </radialGradient>
        <mask id={`${id}-scan`} maskUnits="userSpaceOnUse" x="0" y="0" width={W} height={H}>
          <circle data-scan-glow cx={SAM.x} cy={SAM.y} r="74" fill={`url(#${id}-glow)`} opacity="0" />
          {Array.from({ length: TRAIL }, (_, i) => (
            <circle key={i} data-trail cx={SAM.x} cy={SAM.y} r="40" fill={`url(#${id}-glow)`} opacity="0" />
          ))}
        </mask>
        <filter id={`${id}-shadow`} x="-20%" y="-20%" width="140%" height="160%">
          <feDropShadow dx="0" dy="4" stdDeviation="5" floodColor="#1c1e21" floodOpacity="0.14" />
        </filter>
      </defs>

      {/* the home's rooms, like the continents on the old map */}
      {[`#fff`, `url(#${id}-dots)`].map((fill) => (
        <g key={fill} fill={fill} opacity={fill === "#fff" ? 0.85 : 1}>
          {ROOMS.map((r) => (
            <rect key={r.x} x={r.x} y={r.y} width={r.width} height={r.height} rx="26" />
          ))}
        </g>
      ))}
      <g data-scan fill={`url(#${id}-scanned)`} mask={`url(#${id}-scan)`}>
        {ROOMS.map((r) => (
          <rect key={r.x} x={r.x} y={r.y} width={r.width} height={r.height} rx="26" />
        ))}
      </g>
      <g fontSize="10" fontWeight="700" letterSpacing="1.6" fill="#606770">
        {ROOMS.map((r, i) => (
          <text key={r.x} data-room x={r.label.x} y={r.label.y} textAnchor={r.label.anchor}>
            {t.hero.rooms[i].toUpperCase()}
          </text>
        ))}
      </g>

      {/* dotted links: Sam to each thing, and a few between things */}
      <g fill="none" stroke="#8b9dc3" strokeWidth="4" strokeLinecap="round" strokeDasharray={`0.1 ${DOT_GAP}`}>
        {OBJECTS.map((o) => (
          <path key={o.icon} data-link d={arc(SAM, o)} />
        ))}
        {SIDE_LINKS.map(([a, b]) => (
          <path key={`${a}-${b}`} data-link d={arc(OBJECTS[a], OBJECTS[b])} />
        ))}
      </g>

      {/* memory cards with a time chip */}
      {CARDS.map((c) => {
        const seen = posts.find((p) => p.id === c.post)?.seen ?? "";
        const chip = chipWidth(seen);
        return (
          <g key={c.post} data-mini-card transform={`translate(${c.x} ${c.y}) rotate(${c.rotate})`}>
            <g filter={`url(#${id}-shadow)`}>
              <rect width="176" height="78" rx="14" fill="#fff" />
              <g transform="translate(12 12)">
                <PixelIcon name={c.icon} size={28} />
              </g>
              <rect x="50" y="15" width="104" height="8" rx="4" fill="#e4e6eb" />
              <rect x="50" y="30" width="66" height="8" rx="4" fill="#e4e6eb" />
              <g data-chip data-icon={c.icon} data-seen={seen} data-width={chip} transform="translate(12 50)">
                <rect width={chip} height="20" rx="10" fill="#3b5998" />
                <circle cx="11" cy="10" r="5.5" fill="none" stroke="#fff" strokeWidth="1.6" />
                <path d="M11 7.2 V10 L13 11.4" fill="none" stroke="#fff" strokeWidth="1.6" strokeLinecap="round" />
                <text data-time-chip x="22" y="10.5" dominantBaseline="central" fontSize="11" fontWeight="700" fill="#fff">
                  {seen}
                </text>
              </g>
            </g>
          </g>
        );
      })}

      {/* a ring that pings out of each thing as Sam reaches it */}
      <g fill="none" stroke="#1877f2" strokeWidth="3">
        {OBJECTS.map((o) => (
          <circle key={o.icon} data-ping={o.icon} cx={o.x} cy={o.y} r="30" opacity="0" />
        ))}
      </g>

      {/* the things, as pins */}
      {OBJECTS.map((o) => (
        <g key={o.icon} data-node transform={`translate(${o.x} ${o.y})`}>
          <g>
            {pin(
              <g transform="translate(-17 -17)">
                <PixelIcon name={o.icon} size={34} />
              </g>,
            )}
          </g>
        </g>
      ))}

      {/* Sam, in the middle */}
      <g data-node transform={`translate(${SAM.x} ${SAM.y})`}>
        <g>
          <circle r="40" fill={`url(#${id}-ring)`} />
          <circle r="35" fill="#e8f4fb" />
          <g data-home-sam transform="translate(-16 -26) scale(2)">
            <PixelSprite frames={SAM_FRAMES} palette={SAM_PALETTE} visible="wave" />
          </g>
        </g>
      </g>

      {/* Sam out walking, in front of everything (shown by the walk; still pictures have him home in
          the middle). Same size and spot as Sam in his circle, so leaving and coming home is seamless. */}
      <g data-walker opacity="0" transform={`translate(${SAM.x} ${SAM.y})`}>
        <ellipse cx="0" cy="22" rx="13" ry="3.5" fill="#1c1e21" opacity="0.18" />
        <g transform="translate(-16 -26) scale(2)">
          <PixelSprite frames={SAM_FRAMES} palette={SAM_PALETTE} visible="walkA" />
        </g>
      </g>

      {/* emoji badges */}
      {EMOJIS.map((e) => (
        <g key={e.icon} data-emoji transform={`translate(${e.x} ${e.y})`}>
          <g>
            <g>
              <circle r="24" fill="#fff" filter={`url(#${id}-shadow)`} />
              <g transform="translate(-19 -19)">
                <PixelIcon name={e.icon} size={38} />
              </g>
            </g>
          </g>
        </g>
      ))}
    </svg>
  );
}
