"use client";
/* eslint-disable react-hooks/immutability -- three.js uniforms and controls are mutable objects, updated in effects and frames, never during render */

import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { AnimatePresence, motion } from "motion/react";
import { useEffect, useId, useMemo, useRef, useState } from "react";
import { Color, Vector3 } from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { gsap, MOTION_OK } from "@/lib/gsap";
import { useMotionPrefs } from "@/lib/motion-prefs";
import { Axes, FloorGrid, Furniture, HeightBands, Room, Surfaces, Things, type Bounds, type FurnitureBox, type RoomShape, type Surface, type Thing, type Tokens } from "./Layers";
import { makeUniforms, MODES, RoomCloud, type CloudData, type CloudUniforms, type ColourMode } from "./RoomCloud";
import { ArchitectRoom, CUT, kindColour, loadArchitect, loadMesh, loadPhoto, PhotoRoom, RoomModel, SurfaceMesh, type ArchitectData, type MeshData, type PhotoData } from "./RoomViews";

/** The ways to see the room: every measured point, the room as a plan, or the measured surface. */
export type View = "dots" | "model" | "surface" | "photo" | "architect";

const TARGET = new Vector3(0, 0, 0.9);

/** Where the camera stands for each preset (the room's centre is at the origin; z is up). */
export type Preset = "iso" | "top" | "front" | "side";
const PRESETS: Record<Preset, [number, number, number]> = {
  iso: [4.6, -5.8, 5.6],
  top: [0.01, -0.6, 10.5],
  front: [0, -9.5, 2.4],
  side: [9.5, 0, 2.4],
};
/** The views that read best: every measured point, and the regenerated room. */
export const BEST_VIEWS: View[] = ["dots", "architect"];

interface Options {
  preset: Preset;
  axes: boolean;
  wallOpacity: number;
  showFurniture: boolean;
  wireframe: boolean;
  flat: boolean;
  cut: number;
}

export interface ViewerStrings {
  label: string;
  loading: string;
  view: string;
  views: Record<View, string>;
  viewNotes: Record<View, string>;
  colour: string;
  modes: Record<ColourMode, string>;
  layers: string;
  grid: string;
  bands: string;
  surfaces: string;
  room: string;
  things: string;
  axes: string;
  axisLabels: { x: string; y: string; z: string; north: string };
  best: string;
  more: string;
  camera: string;
  presets: Record<Preset, string>;
  wallOpacity: string;
  showFurniture: string;
  wireframe: string;
  flat: string;
  cut: string;
}

export interface ViewerProps {
  /** folder with points.bin, colors.bin and conf.bin */
  src: string;
  bounds: Bounds;
  surfaces: Surface[];
  room: RoomShape;
  furniture: FurnitureBox[];
  things: Thing[];
  /** index into `things` of the one chosen in the list, or null */
  selected: number | null;
  /** the export has a surface mesh (mesh_pos.bin, mesh_col.bin, mesh_idx.bin) */
  hasMesh?: boolean;
  /** the export has the photo-textured surface (photo_*.bin, photo_atlas.jpg) */
  hasPhoto?: boolean;
  /** the export has the regenerated room (architect.json) */
  hasArchitect?: boolean;
  t: ViewerStrings;
}

interface Layers {
  mode: ColourMode;
  grid: boolean;
  bands: boolean;
  surfaces: boolean;
  room: boolean;
  things: boolean;
}

type Model = Pick<ViewerProps, "room" | "furniture" | "things" | "selected">;

/** Drag to orbit (sideways on phones, so vertical swipes still scroll the page); a slow turn until the first drag. */
function Controls({ spin, preset }: { spin: boolean; preset: Preset }) {
  const { camera, gl, invalidate } = useThree();
  const controls = useMemo(() => {
    camera.up.set(0, 0, 1);
    const c = new OrbitControls(camera, gl.domElement);
    c.target.copy(TARGET);
    c.enableDamping = true;
    c.enableZoom = false;
    c.enablePan = false;
    c.minPolarAngle = 0.02; // the Top preset looks straight down
    c.maxPolarAngle = 1.35;
    c.autoRotateSpeed = 0.6;
    c.update(); // aim at the room now, not on the second frame
    return c;
  }, [camera, gl]);

  useEffect(() => {
    gl.domElement.style.touchAction = "pan-y";
    controls.autoRotate = spin;
    const stop = () => {
      controls.autoRotate = false;
    };
    // with frameloop="demand" (reduced motion) a drag still has to redraw
    const redraw = () => invalidate();
    controls.addEventListener("start", stop);
    controls.addEventListener("change", redraw);
    return () => {
      controls.removeEventListener("start", stop);
      controls.removeEventListener("change", redraw);
    };
  }, [controls, gl, spin, invalidate]);

  // a preset moves the camera once; dragging still turns the room from there
  const first = useRef(true);
  useEffect(() => {
    if (first.current) {
      first.current = false;
      return;
    }
    camera.position.set(...PRESETS[preset]);
    controls.autoRotate = false;
    controls.update();
    invalidate();
  }, [preset, camera, controls, invalidate]);

  useEffect(() => () => controls.dispose(), [controls]);
  useFrame(() => controls.update());
  return null;
}

/** Token colours from globals.css, re-read when the high-contrast theme toggles. */
function useTokens(): Tokens {
  const read = (): Tokens => {
    const css = getComputedStyle(document.documentElement);
    const token = (name: string, fallback: string) => css.getPropertyValue(name).trim() || fallback;
    return {
      line: token("--color-fb-line", "#bdc7d8"),
      blue: token("--color-fb-blue", "#3b5998"),
      blueDark: token("--color-fb-blue-dark", "#29487d"),
      bg: token("--color-white", "#ffffff"),
      muted: token("--color-muted", "#4b4f56"),
      cta: token("--color-cta", "#42b72a"),
    };
  };
  const [tokens, setTokens] = useState(read);
  useEffect(() => {
    const watch = new MutationObserver(() => setTokens(read()));
    watch.observe(document.documentElement, { attributes: true, attributeFilter: ["data-contrast"] });
    return () => watch.disconnect();
  }, []);
  return tokens;
}

function Scene({ view, mesh, photo, architect, data, uniforms, spin, layers, bounds, surfaces, model, tokens, options, axisLabels }: { view: View; mesh: MeshData | null; photo: PhotoData | null; architect: ArchitectData | null; data: CloudData; uniforms: CloudUniforms; spin: boolean; layers: Layers; bounds: Bounds; surfaces: Surface[]; model: Model; tokens: Tokens; options: Options; axisLabels: ViewerStrings["axisLabels"] }) {
  const { invalidate } = useThree();
  useEffect(() => invalidate(), [model.selected, layers, view, mesh, photo, architect, options, invalidate]);
  const axes = options.axes && <Axes floor={model.room.floor} height={model.room.height_m} northDeg={model.room.north_deg} tokens={tokens} labels={axisLabels} />;
  const controls = <Controls spin={spin} preset={options.preset} />;
  useEffect(() => {
    uniforms.uLow.value = new Color(tokens.line);
    uniforms.uHigh.value = new Color(tokens.blue);
    uniforms.uBg.value = new Color(tokens.bg);
    uniforms.uWeak.value = new Color(tokens.muted);
    uniforms.uStrong.value = new Color(tokens.cta);
    uniforms.uMode.value = MODES.indexOf(layers.mode);
    invalidate();
  }, [uniforms, tokens, layers.mode, invalidate]);
  if (view === "model") {
    return (
      <>
        <RoomModel room={model.room} furniture={model.furniture} things={model.things} selected={model.selected} tokens={tokens} wallOpacity={options.wallOpacity} showFurniture={options.showFurniture} />
        <Things items={model.things} selected={model.selected} tokens={tokens} bob={spin} />
        {axes}
        {controls}
      </>
    );
  }
  if (view === "photo" && photo) {
    return (
      <>
        <PhotoRoom photo={photo} />
        <Things items={model.things} selected={model.selected} tokens={tokens} bob={spin} />
        {axes}
        {controls}
      </>
    );
  }
  if (view === "architect" && architect) {
    return (
      <>
        {/* an architect's model shows north and scale, not x/y/z axes */}
        <ArchitectRoom model={architect} selected={model.selected} tokens={tokens} cut={options.cut} north={{ deg: model.room.north_deg, label: axisLabels.north }} />
        <Things items={model.things} selected={model.selected} tokens={tokens} bob={spin} />
        {controls}
      </>
    );
  }
  if (view === "surface" && mesh) {
    return (
      <>
        <SurfaceMesh mesh={mesh} wireframe={options.wireframe} flat={options.flat} />
        <Things items={model.things} selected={model.selected} tokens={tokens} bob={spin} />
        {axes}
        {controls}
      </>
    );
  }
  return (
    <>
      <RoomCloud data={data} uniforms={uniforms} />
      {layers.grid && <FloorGrid bounds={bounds} tokens={tokens} />}
      {layers.bands && <HeightBands bounds={bounds} tokens={tokens} />}
      {layers.surfaces && <Surfaces surfaces={surfaces} tokens={tokens} />}
      {layers.room && <Room room={model.room} tokens={tokens} />}
      {layers.room && <Furniture items={model.furniture} tokens={tokens} />}
      {layers.things && <Things items={model.things} selected={model.selected} tokens={tokens} bob={spin} />}
      {axes}
      {controls}
    </>
  );
}

async function load(src: string): Promise<CloudData> {
  const get = (file: string, required: boolean) =>
    fetch(`${src}/${file}`).then((r) => {
      if (r.ok) return r.arrayBuffer();
      if (required) throw new Error(`${file}: ${r.status}`);
      return null;
    });
  // colors.bin is optional: it is kept out of the public repo, so a deployed site may not have it
  const [positions, colors, conf] = await Promise.all([get("points.bin", true), get("colors.bin", false), get("conf.bin", true)]);
  return { positions: new Float32Array(positions!), colors: colors ? new Uint8Array(colors) : null, conf: new Uint8Array(conf!) };
}

export default function ViewerCanvas({ src, bounds, surfaces, room, furniture, things, selected, hasMesh = false, hasPhoto = false, hasArchitect = false, t }: ViewerProps) {
  const root = useRef<HTMLDivElement>(null);
  const id = useId();
  const { reduced } = useMotionPrefs();
  const [data, setData] = useState<CloudData | null>(null);
  const [layers, setLayers] = useState<Layers>({ mode: "height", grid: true, bands: false, surfaces: false, room: true, things: true });
  const [view, setView] = useState<View>("dots");
  const [options, setOptions] = useState<Options>({ preset: "iso", axes: true, wallOpacity: 0.45, showFurniture: true, wireframe: false, flat: false, cut: CUT });
  const [moreOpen, setMoreOpen] = useState(false);
  const set = <K extends keyof Options>(key: K, value: Options[K]) => setOptions((o) => ({ ...o, [key]: value }));
  // each view opens with the settings it reads best in (each can be changed after):
  // the surface as a 3D wireframe with the axes
  const chooseView = (v: View) => {
    setView(v);
    if (v === "surface") setOptions((o) => ({ ...o, preset: "iso", axes: true, wireframe: true }));
    // the architect's model reads best from above, with the walls cut at 1.5 m
    if (v === "architect") setOptions((o) => ({ ...o, preset: "top", cut: 1.5 }));
  };
  const [mesh, setMesh] = useState<MeshData | null>(null);
  const [photo, setPhoto] = useState<PhotoData | null>(null);
  const [architect, setArchitect] = useState<ArchitectData | null>(null);
  const [animate] = useState(() => !reduced && window.matchMedia(MOTION_OK).matches);
  // the same clamp as the Canvas dpr below, so the first frame already has the final point size
  const uniforms = useMemo(() => makeUniforms(animate ? 0 : 1, Math.min(Math.max(window.devicePixelRatio, 1), 2) * 1.15), [animate]);
  const still = reduced || !animate;
  const tokens = useTokens();

  // fetch the scan only once the viewer is close to the screen
  useEffect(() => {
    const el = root.current;
    if (!el) return;
    let cancelled = false;
    const seen = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting) return;
        seen.disconnect();
        load(src).then((d) => !cancelled && setData(d));
      },
      { rootMargin: "200px" },
    );
    seen.observe(el);
    return () => {
      cancelled = true;
      seen.disconnect();
    };
  }, [src]);

  // the surface is fetched only when someone asks to see it
  useEffect(() => {
    if (view !== "surface" || mesh || !hasMesh) return;
    let cancelled = false;
    loadMesh(src).then((m) => !cancelled && setMesh(m));
    return () => {
      cancelled = true;
    };
  }, [view, mesh, hasMesh, src]);
  useEffect(() => {
    if (view !== "photo" || photo || !hasPhoto) return;
    let cancelled = false;
    loadPhoto(src).then((p) => !cancelled && setPhoto(p));
    return () => {
      cancelled = true;
    };
  }, [view, photo, hasPhoto, src]);
  useEffect(() => {
    if (view !== "architect" || architect || !hasArchitect) return;
    let cancelled = false;
    loadArchitect(src).then((a) => !cancelled && setArchitect(a));
    return () => {
      cancelled = true;
    };
  }, [view, architect, hasArchitect, src]);

  // the gather: GSAP owns this one uniform; nothing else animates the canvas
  useEffect(() => {
    const el = root.current;
    if (!data || !el) return;
    if (still) {
      uniforms.uProgress.value = 1;
      // mark it formed once the canvas has actually drawn it
      let frame = requestAnimationFrame(() => {
        frame = requestAnimationFrame(() => {
          el.dataset.progress = "1";
        });
      });
      return () => cancelAnimationFrame(frame);
    }
    el.dataset.progress = "0";
    const tween = gsap.to(uniforms.uProgress, {
      value: 1,
      duration: 2.8,
      // in-out, so the gather is actually seen; an editorial ease-out would land almost at once
      ease: "power2.inOut",
      delay: 0.2,
      onComplete: () => {
        el.dataset.progress = "1";
      },
    });
    return () => {
      tween.kill();
    };
  }, [data, still, uniforms]);

  const toggle = (key: "grid" | "bands" | "surfaces" | "room" | "things") => setLayers((l) => ({ ...l, [key]: !l[key] }));
  const modes = data?.colors ? MODES : MODES.filter((mode) => mode !== "photo");
  const views: View[] = ["dots", "model", ...(hasMesh ? (["surface"] as const) : []), ...(hasPhoto ? (["photo"] as const) : []), ...(hasArchitect ? (["architect"] as const) : [])];
  const pending = (view === "surface" && !mesh) || (view === "photo" && !photo) || (view === "architect" && !architect);
  const kinds = [...new Set(furniture.map((f) => f.label))];
  const check = "size-4 accent-fb-blue";
  const chip = "flex cursor-pointer items-center gap-2 rounded-full border border-fb-line bg-white px-3 py-1.5 text-sm text-ink has-checked:border-fb-blue has-checked:bg-fb-blue-pale";

  return (
    <div className="flex flex-col">
      <div ref={root} role="img" aria-label={`${t.label} ${t.viewNotes[view]}`} data-viewer data-mode={layers.mode} data-view={view} className="relative aspect-[4/5] sm:aspect-[4/3]">
        {data ? (
          <Canvas
            frameloop={still ? "demand" : "always"}
            dpr={[1, 2]}
            camera={{ position: [4.6, -5.8, 5.6], fov: 34, near: 0.1, far: 60 }}
            gl={{ antialias: true, alpha: true, preserveDrawingBuffer: true }}
          >
            <Scene view={view} mesh={mesh} photo={photo} architect={architect} data={data} uniforms={uniforms} spin={!still} layers={layers} bounds={bounds} surfaces={surfaces} model={{ room, furniture, things, selected }} tokens={tokens} options={options} axisLabels={t.axisLabels} />
          </Canvas>
        ) : (
          <p className="grid size-full place-items-center text-sm text-muted">{t.loading}</p>
        )}
      </div>
      <div data-viewer-controls className="flex flex-wrap gap-x-6 gap-y-3 border-t border-fb-line px-4 py-3">
        <fieldset className="flex w-full flex-wrap items-center gap-2">
          <legend className="float-left mr-1 text-sm font-semibold text-muted">{t.view}</legend>
          {views.map((v) => (
            <label key={v} className={chip} data-best={BEST_VIEWS.includes(v) || undefined}>
              <input type="radio" name={`${id}-view`} value={v} checked={view === v} onChange={() => chooseView(v)} className={check} />
              {t.views[v]}
              {BEST_VIEWS.includes(v) && (
                <span className="rounded-full bg-cta-dark px-2 py-0.5 text-xs font-bold text-white">
                  <span aria-hidden>★ </span>
                  {t.best}
                </span>
              )}
            </label>
          ))}
          <p className="w-full text-sm text-muted" aria-live="polite">
            {pending ? t.loading : t.viewNotes[view]}
          </p>
        </fieldset>
        {view === "model" && kinds.length > 0 && (
          <ul aria-label={t.room} className="flex flex-wrap gap-x-4 gap-y-1 text-sm text-ink">
            {kinds.map((k) => (
              <li key={k} className="flex items-center gap-1.5">
                <span aria-hidden className="inline-block size-3 rounded-sm border border-fb-line" style={{ background: kindColour(k) }} />
                {k}
              </li>
            ))}
          </ul>
        )}
        {view === "dots" && (
          <>
        <fieldset className="flex flex-wrap items-center gap-2">
          <legend className="float-left mr-1 text-sm font-semibold text-muted">{t.colour}</legend>
          {modes.map((mode) => (
            <label key={mode} className={chip}>
              <input type="radio" name={`${id}-mode`} value={mode} checked={layers.mode === mode} onChange={() => setLayers((l) => ({ ...l, mode }))} className={check} />
              {t.modes[mode]}
            </label>
          ))}
        </fieldset>
        <fieldset className="flex flex-wrap items-center gap-2">
          <legend className="float-left mr-1 text-sm font-semibold text-muted">{t.layers}</legend>
          {(["room", "things", "grid", "bands", "surfaces"] as const).map((key) => (
            <label key={key} className={chip}>
              <input type="checkbox" checked={layers[key]} onChange={() => toggle(key)} className={check} />
              {t[key]}
            </label>
          ))}
        </fieldset>
          </>
        )}
        <div className="w-full">
          <button
            type="button"
            aria-expanded={moreOpen}
            aria-controls={`${id}-more`}
            onClick={() => setMoreOpen((o) => !o)}
            className="flex min-h-11 items-center gap-2 text-sm font-semibold text-fb-blue-dark underline"
          >
            <span aria-hidden className={`inline-block transition-transform motion-reduce:transition-none ${moreOpen ? "rotate-90" : ""}`}>
              ▸
            </span>
            {t.more}
          </button>
          <AnimatePresence initial={false}>
            {moreOpen && (
              <motion.div
                id={`${id}-more`}
                data-more-options
                key="more"
                initial={{ height: 0, opacity: 0 }}
                animate={{ height: "auto", opacity: 1 }}
                exit={{ height: 0, opacity: 0 }}
                transition={{ duration: 0.25 }}
                className="overflow-hidden"
              >
                <div className="flex flex-wrap gap-x-6 gap-y-3 pt-2">
                  <fieldset className="flex flex-wrap items-center gap-2">
                    <legend className="float-left mr-1 text-sm font-semibold text-muted">{t.camera}</legend>
                    {(Object.keys(PRESETS) as Preset[]).map((p) => (
                      <label key={p} className={chip}>
                        <input type="radio" name={`${id}-preset`} value={p} checked={options.preset === p} onChange={() => set("preset", p)} className={check} />
                        {t.presets[p]}
                      </label>
                    ))}
                  </fieldset>
                  {view !== "architect" && (
                    <label className={chip}>
                      <input type="checkbox" checked={options.axes} onChange={() => set("axes", !options.axes)} className={check} />
                      {t.axes}
                    </label>
                  )}
                  {view === "model" && (
                    <>
                      <label className="flex items-center gap-2 text-sm text-ink">
                        {t.wallOpacity}
                        <input type="range" min={0.15} max={1} step={0.05} value={options.wallOpacity} onChange={(e) => set("wallOpacity", Number(e.target.value))} className="accent-fb-blue" />
                        <span className="tabular-nums text-muted">{Math.round(options.wallOpacity * 100)}%</span>
                      </label>
                      <label className={chip}>
                        <input type="checkbox" checked={options.showFurniture} onChange={() => set("showFurniture", !options.showFurniture)} className={check} />
                        {t.showFurniture}
                      </label>
                    </>
                  )}
                  {view === "surface" && (
                    <>
                      <label className={chip}>
                        <input type="checkbox" checked={options.wireframe} onChange={() => set("wireframe", !options.wireframe)} className={check} />
                        {t.wireframe}
                      </label>
                      <label className={chip}>
                        <input type="checkbox" checked={options.flat} onChange={() => set("flat", !options.flat)} className={check} />
                        {t.flat}
                      </label>
                    </>
                  )}
                  {view === "architect" && (
                    <label className="flex items-center gap-2 text-sm text-ink">
                      {t.cut}
                      <input type="range" min={0.6} max={2.4} step={0.1} value={options.cut} onChange={(e) => set("cut", Number(e.target.value))} className="accent-fb-blue" />
                      <span className="tabular-nums text-muted">{options.cut.toFixed(1)} m</span>
                    </label>
                  )}
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}
