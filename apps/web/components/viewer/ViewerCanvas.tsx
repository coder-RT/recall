"use client";
/* eslint-disable react-hooks/immutability -- three.js uniforms and controls are mutable objects, updated in effects and frames, never during render */

import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { useEffect, useId, useMemo, useRef, useState } from "react";
import { Color, Vector3 } from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { gsap, MOTION_OK } from "@/lib/gsap";
import { useMotionPrefs } from "@/lib/motion-prefs";
import { FloorGrid, Furniture, HeightBands, Room, Surfaces, Things, type Bounds, type FurnitureBox, type RoomShape, type Surface, type Thing, type Tokens } from "./Layers";
import { makeUniforms, MODES, RoomCloud, type CloudData, type CloudUniforms, type ColourMode } from "./RoomCloud";
import { ArchitectRoom, kindColour, loadArchitect, loadMesh, loadPhoto, PhotoRoom, RoomModel, SurfaceMesh, type ArchitectData, type MeshData, type PhotoData } from "./RoomViews";

/** The ways to see the room: every measured point, the room as a plan, or the measured surface. */
export type View = "dots" | "model" | "surface" | "photo" | "architect";

const TARGET = new Vector3(0, 0, 0.9);

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
function Controls({ spin }: { spin: boolean }) {
  const { camera, gl, invalidate } = useThree();
  const controls = useMemo(() => {
    camera.up.set(0, 0, 1);
    const c = new OrbitControls(camera, gl.domElement);
    c.target.copy(TARGET);
    c.enableDamping = true;
    c.enableZoom = false;
    c.enablePan = false;
    c.minPolarAngle = 0.35;
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

function Scene({ view, mesh, photo, architect, data, uniforms, spin, layers, bounds, surfaces, model, tokens }: { view: View; mesh: MeshData | null; photo: PhotoData | null; architect: ArchitectData | null; data: CloudData; uniforms: CloudUniforms; spin: boolean; layers: Layers; bounds: Bounds; surfaces: Surface[]; model: Model; tokens: Tokens }) {
  const { invalidate } = useThree();
  useEffect(() => invalidate(), [model.selected, layers, view, mesh, photo, architect, invalidate]);
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
        <RoomModel room={model.room} furniture={model.furniture} things={model.things} selected={model.selected} tokens={tokens} />
        <Things items={model.things} selected={model.selected} tokens={tokens} bob={spin} />
        <Controls spin={spin} />
      </>
    );
  }
  if (view === "photo" && photo) {
    return (
      <>
        <PhotoRoom photo={photo} />
        <Things items={model.things} selected={model.selected} tokens={tokens} bob={spin} />
        <Controls spin={spin} />
      </>
    );
  }
  if (view === "architect" && architect) {
    return (
      <>
        <ArchitectRoom model={architect} selected={model.selected} tokens={tokens} />
        <Things items={model.things} selected={model.selected} tokens={tokens} bob={spin} />
        <Controls spin={spin} />
      </>
    );
  }
  if (view === "surface" && mesh) {
    return (
      <>
        <SurfaceMesh mesh={mesh} />
        <Things items={model.things} selected={model.selected} tokens={tokens} bob={spin} />
        <Controls spin={spin} />
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
      <Controls spin={spin} />
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
    <div className="flex size-full flex-col">
      <div ref={root} role="img" aria-label={`${t.label} ${t.viewNotes[view]}`} data-viewer data-mode={layers.mode} data-view={view} className="relative min-h-0 flex-1">
        {data ? (
          <Canvas
            frameloop={still ? "demand" : "always"}
            dpr={[1, 2]}
            camera={{ position: [4.6, -5.8, 5.6], fov: 34, near: 0.1, far: 60 }}
            gl={{ antialias: true, alpha: true, preserveDrawingBuffer: true }}
          >
            <Scene view={view} mesh={mesh} photo={photo} architect={architect} data={data} uniforms={uniforms} spin={!still} layers={layers} bounds={bounds} surfaces={surfaces} model={{ room, furniture, things, selected }} tokens={tokens} />
          </Canvas>
        ) : (
          <p className="grid size-full place-items-center text-sm text-muted">{t.loading}</p>
        )}
      </div>
      <div data-viewer-controls className="flex flex-wrap gap-x-6 gap-y-3 border-t border-fb-line px-4 py-3">
        <fieldset className="flex w-full flex-wrap items-center gap-2">
          <legend className="float-left mr-1 text-sm font-semibold text-muted">{t.view}</legend>
          {views.map((v) => (
            <label key={v} className={chip}>
              <input type="radio" name={`${id}-view`} value={v} checked={view === v} onChange={() => setView(v)} className={check} />
              {t.views[v]}
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
      </div>
    </div>
  );
}
