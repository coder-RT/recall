"use client";

import { Canvas, useThree } from "@react-three/fiber";
import { useEffect, useMemo, useRef, useState } from "react";
import { CatmullRomCurve3, Color, type Group, Vector3 } from "three";
import { Furniture, Room, Route, Things, type FurnitureBox, type RoomShape, type Thing, type Tokens, type Walk } from "./Layers";
import { makeUniforms, RoomCloud, type CloudData } from "./RoomCloud";
import path from "./film-path.json";

/**
 * The film's fly-through of the real scan (/film, not linked from the site). Time is set from outside, never from the
 * clock: `window.__film.seek(t)` places the camera on its path and sets every reveal for that moment, then renders one
 * frame, so a capture script can step through it frame by frame. `?t=` shows one moment.
 */

export interface FilmWalk {
  label: string;
  color?: string | null;
  place?: string;
  target: number[];
  steps: { clock: number; metres: number; say: string }[];
  path: [number, number][];
}

interface Meta {
  room: RoomShape;
  furniture: FurnitureBox[];
  objects: Thing[];
}

const TOKENS: Tokens = { line: "#bdc7d8", blue: "#3b5998", blueDark: "#29487d", bg: "#f0f2f5", muted: "#4b4f56", cta: "#42b72a" };
const BG = "#f0f2f5";

/** The reveal timeline, in seconds of the film's 13. */
export const FILM = {
  gather: [0, 3.2],
  room: 2.4,
  furniture: 4.0,
  pin: 6.4,
  route: [8.0, 11.4],
  proof: 11.8,
} as const;

const ease = (x: number) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
const clamp01 = (x: number) => Math.min(1, Math.max(0, x));

async function loadCloud(src: string): Promise<CloudData> {
  const get = (f: string) => fetch(`${src}/${f}`).then((r) => (r.ok ? r.arrayBuffer() : Promise.reject(new Error(f))));
  const [positions, conf] = await Promise.all([get("points.bin"), get("conf.bin")]);
  return { positions: new Float32Array(positions), colors: null, conf: new Uint8Array(conf) };
}

interface Labels {
  furniture: { text: string; at: Vector3 }[];
  pin: { text: string; at: Vector3 };
  steps: { text: string; clock: number; at: Vector3; from: number }[];
}

/** Places the camera, sets the reveals, renders a frame and moves the HTML labels, for time t. */
function Rig({ data, meta, walk, labels, overlay }: { data: CloudData; meta: Meta; walk: FilmWalk; labels: Labels; overlay: React.RefObject<HTMLDivElement | null> }) {
  const { camera, gl, scene, size } = useThree();
  const uniforms = useMemo(() => {
    const u = makeUniforms(0, 2.2);
    u.uLow.value = new Color(TOKENS.line);
    u.uHigh.value = new Color(TOKENS.blue);
    u.uBg.value = new Color(BG);
    return u;
  }, []);
  const room = useRef<Group>(null);
  const furniture = useRef<Group>(null);
  const pin = useRef<Group>(null);
  const walkLayer = useRef<Group>(null);
  const curve = useMemo(() => new CatmullRomCurve3(path.points.map((p) => new Vector3(...p))), []);
  const aim = useMemo(() => new CatmullRomCurve3(path.targets.map((p) => new Vector3(...p))), []);
  const route: Walk = useMemo(() => ({ path: walk.path, progress: { value: 0 } }), [walk]);
  const keys = useMemo(() => [{ label: walk.label, color: walk.color ?? null, at: walk.target, confidence: 1 } as Thing], [walk]);

  useEffect(() => {
    camera.up.set(0, 0, 1);
    const seek = (t: number) => {
      const p = ease(clamp01(t / path.duration));
      camera.position.copy(curve.getPointAt(p));
      camera.lookAt(aim.getPointAt(p));
      camera.updateMatrixWorld();
      uniforms.uProgress.value = ease(clamp01((t - FILM.gather[0]) / (FILM.gather[1] - FILM.gather[0])));
      if (room.current) room.current.visible = t >= FILM.room;
      if (furniture.current) furniture.current.visible = t >= FILM.furniture;
      if (pin.current) pin.current.visible = t >= FILM.pin;
      if (walkLayer.current) walkLayer.current.visible = t >= FILM.route[0];
      route.progress.value = clamp01((t - FILM.route[0]) / (FILM.route[1] - FILM.route[0]));
      gl.render(scene, camera); // one frame now (the Route layer reads its progress in its own frame hook too)
      // the HTML labels follow their 3D points
      const el = overlay.current;
      if (!el) return;
      const place = (node: HTMLElement | null, at: Vector3, show: boolean) => {
        if (!node) return;
        const v = at.clone().project(camera);
        const behind = v.z > 1;
        node.style.opacity = show && !behind ? "1" : "0";
        // kept inside the frame (a label near the edge slides in rather than leaving)
        const w = node.offsetWidth, h = node.offsetHeight, m = 48;
        const x = Math.min(size.width - m - w / 2, Math.max(m + w / 2, ((v.x + 1) / 2) * size.width));
        const y = Math.min(size.height - m, Math.max(m + h, ((1 - v.y) / 2) * size.height));
        node.style.transform = `translate(${x}px, ${y}px) translate(-50%, -100%)`;
      };
      labels.furniture.forEach((f, i) => place(el.querySelector(`[data-furniture="${i}"]`), f.at, t >= FILM.furniture + 0.25 * i && t < FILM.pin));
      place(el.querySelector("[data-pin]"), labels.pin.at, t >= FILM.pin + 0.3);
      // only the step being walked, from the moment the walk reaches it until the next one starts
      const walking = t >= FILM.route[0] && t < FILM.proof;
      labels.steps.forEach((s, i) => {
        const next = labels.steps[i + 1]?.from ?? 1.01;
        place(el.querySelector(`[data-step="${i}"]`), s.at, walking && route.progress.value >= s.from && route.progress.value < next);
      });
      const proof = el.querySelector<HTMLElement>("[data-proof]");
      if (proof) proof.style.opacity = t >= FILM.proof ? "1" : "0";
    };
    const film = {
      duration: path.duration,
      seek: (t: number) =>
        new Promise<void>((resolve) => {
          seek(t);
          // two frames: the walk's own frame hook draws its progress, then the page is painted
          requestAnimationFrame(() => {
            seek(t);
            requestAnimationFrame(() => resolve());
          });
        }),
    };
    (window as unknown as { __film?: typeof film }).__film = film;
    const start = Number(new URLSearchParams(location.search).get("t") ?? "0");
    film.seek(Number.isFinite(start) ? start : 0).then(() => document.documentElement.setAttribute("data-film-ready", "true"));
  }, [camera, gl, scene, size, curve, aim, uniforms, route, labels, overlay]);

  return (
    <>
      <RoomCloud data={data} uniforms={uniforms} />
      <group ref={room} visible={false}>
        <Room room={meta.room} tokens={TOKENS} />
      </group>
      <group ref={furniture} visible={false}>
        <Furniture items={meta.furniture} tokens={TOKENS} />
      </group>
      <group ref={pin} visible={false}>
        <Things items={keys} selected={0} tokens={TOKENS} />
      </group>
      <group ref={walkLayer} visible={false}>
        <Route walk={route} tokens={TOKENS} />
      </group>
    </>
  );
}

const shape = "absolute left-0 top-0 whitespace-nowrap rounded-full px-5 py-2 font-bold shadow-[0_0_0_2px_#bdc7d8,0_10px_24px_-8px_rgba(59,89,152,0.45)]";
const pill = `${shape} bg-white text-[30px] text-ink`;

export function FilmFlythrough({ walk, src }: { walk: FilmWalk; src: string }) {
  const overlay = useRef<HTMLDivElement>(null);
  const [data, setData] = useState<CloudData | null>(null);
  const [meta, setMeta] = useState<Meta | null>(null);
  useEffect(() => {
    let cancelled = false;
    Promise.all([loadCloud(src), fetch(`${src}/meta.json`).then((r) => r.json())]).then(([d, m]) => {
      if (!cancelled) {
        setData(d);
        setMeta(m);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [src]);

  const labels: Labels | null = useMemo(() => {
    if (!meta) return null;
    // one label per kind of furniture, the largest of each, at its top
    const seen = new Map<string, FurnitureBox>();
    for (const f of meta.furniture) {
      const vol = (b: FurnitureBox) => (b.max[0] - b.min[0]) * (b.max[1] - b.min[1]);
      const prev = seen.get(f.label);
      if (!prev || vol(f) > vol(prev)) seen.set(f.label, f);
    }
    const furniture = [...seen.values()]
      .filter((f) => f.label !== "door")
      .slice(0, 6)
      .map((f) => ({ text: f.label, at: new Vector3((f.min[0] + f.max[0]) / 2, (f.min[1] + f.max[1]) / 2, f.max[2] + 0.1) }));
    const [tx, ty, tz] = walk.target;
    const steps = walk.steps.map((s, i) => {
      const [x, y] = walk.path[i];
      const total = walk.steps.reduce((a, b) => a + b.metres, 0);
      const before = walk.steps.slice(0, i).reduce((a, b) => a + b.metres, 0);
      return { text: s.say.replace(/\.$/, ""), clock: s.clock, at: new Vector3(x, y, 0.15), from: before / total };
    });
    return { furniture, pin: { text: `${walk.label} · ${walk.place ?? ""}`.replace(/ · $/, ""), at: new Vector3(tx, ty, tz + 0.55) }, steps };
  }, [meta, walk]);

  return (
    <div className="fixed inset-0 z-[200] overflow-hidden" style={{ background: `radial-gradient(1200px 800px at 15% 0%, #dfe3ee, transparent 70%), ${BG}` }} data-film>
      {data && meta && labels && (
        <Canvas frameloop="demand" dpr={1} camera={{ fov: 34, near: 0.1, far: 80, position: path.points[0] as [number, number, number] }} gl={{ antialias: true, alpha: true, preserveDrawingBuffer: true }}>
          <Rig data={data} meta={meta} walk={walk} labels={labels} overlay={overlay} />
        </Canvas>
      )}
      <div ref={overlay} aria-hidden className="pointer-events-none absolute inset-0 font-sans">
        {labels?.furniture.map((f, i) => (
          <span key={i} data-furniture={i} className={pill} style={{ opacity: 0 }}>
            {f.text}
          </span>
        ))}
        {labels && (
          <span data-pin className={`${shape} bg-fb-blue-dark text-[36px] text-white`} style={{ opacity: 0 }}>
            {labels.pin.text}
          </span>
        )}
        {labels?.steps.map((s, i) => (
          <span key={i} data-step={i} className={`${pill} flex items-center gap-3 text-[28px]`} style={{ opacity: 0 }}>
            <svg viewBox="0 0 40 40" className="size-9" aria-hidden>
              <circle cx="20" cy="20" r="17" fill="white" stroke="#29487d" strokeWidth="3" />
              <line x1="20" y1="20" x2="20" y2="8" stroke="#29487d" strokeWidth="3.5" strokeLinecap="round" transform={`rotate(${(s.clock % 12) * 30} 20 20)`} />
            </svg>
            {s.text}
          </span>
        ))}
        <div data-proof className="absolute bottom-16 left-16 rounded-3xl bg-white px-10 py-6 shadow-[0_0_0_2px_#bdc7d8,0_20px_40px_-12px_rgba(59,89,152,0.45)]" style={{ opacity: 0 }}>
          <p className="text-[96px] font-bold leading-none text-fb-blue-dark">3 cm</p>
          <p className="mt-2 text-[30px] font-bold text-ink">arrival check on the real keys</p>
          <p className="text-[26px] text-muted">SAM 3.1 + LiDAR depth vs where Recall remembered them</p>
        </div>
      </div>
    </div>
  );
}
