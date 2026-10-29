"use client";
/* eslint-disable react-hooks/immutability -- three.js uniforms and controls are mutable objects, updated in effects and frames, never during render */

import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { useEffect, useId, useMemo, useRef, useState } from "react";
import { Color, Vector3 } from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { gsap, MOTION_OK } from "@/lib/gsap";
import { useMotionPrefs } from "@/lib/motion-prefs";
import { FloorGrid, HeightBands, Surfaces, type Bounds, type Surface, type Tokens } from "./Layers";
import { makeUniforms, MODES, RoomCloud, type CloudData, type CloudUniforms, type ColourMode } from "./RoomCloud";

const TARGET = new Vector3(0, 0, 0.9);

export interface ViewerStrings {
  label: string;
  loading: string;
  colour: string;
  modes: Record<ColourMode, string>;
  layers: string;
  grid: string;
  bands: string;
  surfaces: string;
}

export interface ViewerProps {
  /** folder with points.bin, colors.bin and conf.bin */
  src: string;
  bounds: Bounds;
  surfaces: Surface[];
  t: ViewerStrings;
}

interface Layers {
  mode: ColourMode;
  grid: boolean;
  bands: boolean;
  surfaces: boolean;
}

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

function Scene({ data, uniforms, spin, layers, bounds, surfaces, tokens }: { data: CloudData; uniforms: CloudUniforms; spin: boolean; layers: Layers; bounds: Bounds; surfaces: Surface[]; tokens: Tokens }) {
  const { invalidate } = useThree();
  useEffect(() => {
    uniforms.uLow.value = new Color(tokens.line);
    uniforms.uHigh.value = new Color(tokens.blue);
    uniforms.uBg.value = new Color(tokens.bg);
    uniforms.uWeak.value = new Color(tokens.muted);
    uniforms.uStrong.value = new Color(tokens.cta);
    uniforms.uMode.value = MODES.indexOf(layers.mode);
    invalidate();
  }, [uniforms, tokens, layers.mode, invalidate]);
  return (
    <>
      <RoomCloud data={data} uniforms={uniforms} />
      {layers.grid && <FloorGrid bounds={bounds} tokens={tokens} />}
      {layers.bands && <HeightBands bounds={bounds} tokens={tokens} />}
      {layers.surfaces && <Surfaces surfaces={surfaces} tokens={tokens} />}
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

export default function ViewerCanvas({ src, bounds, surfaces, t }: ViewerProps) {
  const root = useRef<HTMLDivElement>(null);
  const id = useId();
  const { reduced } = useMotionPrefs();
  const [data, setData] = useState<CloudData | null>(null);
  const [layers, setLayers] = useState<Layers>({ mode: "height", grid: true, bands: false, surfaces: false });
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

  const toggle = (key: "grid" | "bands" | "surfaces") => setLayers((l) => ({ ...l, [key]: !l[key] }));
  const modes = data?.colors ? MODES : MODES.filter((mode) => mode !== "photo");
  const check = "size-4 accent-fb-blue";
  const chip = "flex cursor-pointer items-center gap-2 rounded-full border border-fb-line bg-white px-3 py-1.5 text-sm text-ink has-checked:border-fb-blue has-checked:bg-fb-blue-pale";

  return (
    <div className="flex size-full flex-col">
      <div ref={root} role="img" aria-label={t.label} data-viewer data-mode={layers.mode} className="relative min-h-0 flex-1">
        {data ? (
          <Canvas
            frameloop={still ? "demand" : "always"}
            dpr={[1, 2]}
            camera={{ position: [4.6, -5.8, 5.6], fov: 34, near: 0.1, far: 60 }}
            gl={{ antialias: true, alpha: true, preserveDrawingBuffer: true }}
          >
            <Scene data={data} uniforms={uniforms} spin={!still} layers={layers} bounds={bounds} surfaces={surfaces} tokens={tokens} />
          </Canvas>
        ) : (
          <p className="grid size-full place-items-center text-sm text-muted">{t.loading}</p>
        )}
      </div>
      <div data-viewer-controls className="flex flex-wrap gap-x-6 gap-y-3 border-t border-fb-line px-4 py-3">
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
          {(["grid", "bands", "surfaces"] as const).map((key) => (
            <label key={key} className={chip}>
              <input type="checkbox" checked={layers[key]} onChange={() => toggle(key)} className={check} />
              {t[key]}
            </label>
          ))}
        </fieldset>
      </div>
    </div>
  );
}
