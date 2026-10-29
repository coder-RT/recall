"use client";

import { useMemo } from "react";
import { BufferAttribute, BufferGeometry, Color, ShaderMaterial } from "three";

/** What colours the points: height in the site's blues, the photo's colour, or the pipeline's confidence. */
export type ColourMode = "height" | "photo" | "confidence";
export const MODES: ColourMode[] = ["height", "photo", "confidence"];

export interface CloudUniforms {
  uProgress: { value: number };
  uSize: { value: number };
  uMode: { value: number };
  uLow: { value: Color };
  uHigh: { value: Color };
  uBg: { value: Color };
  uWeak: { value: Color };
  uStrong: { value: Color };
  [name: string]: { value: unknown };
}

/** `size` is the base point size in device pixels (scale it by the canvas's pixel ratio). */
export function makeUniforms(progress: number, size: number): CloudUniforms {
  return {
    uProgress: { value: progress },
    uSize: { value: size },
    uMode: { value: 0 },
    uLow: { value: new Color("#bdc7d8") },
    uHigh: { value: new Color("#3b5998") },
    uBg: { value: new Color("#ffffff") },
    uWeak: { value: new Color("#4b4f56") },
    uStrong: { value: new Color("#42b72a") },
  };
}

export interface CloudData {
  positions: Float32Array;
  /** rgb per point, 0..255; null when colors.bin is not published (it is gitignored) */
  colors: Uint8Array | null;
  /** 0..255, least to most confident */
  conf: Uint8Array;
}

// Each point flies from a scattered shell to where the scan put it; low points land first, so the
// floor settles and the walls rise. A swirl about the vertical axis fades out as it lands.
const vertex = /* glsl */ `
  uniform float uProgress;
  uniform float uSize;
  attribute vec3 aStart;
  attribute float aDelay;
  attribute vec3 aColor;
  attribute float aConf;
  varying float vHeight;
  varying float vAlpha;
  varying float vFar;
  varying vec3 vColor;
  varying float vConf;
  void main() {
    float t = clamp(uProgress * 1.4 - aDelay, 0.0, 1.0);
    float e = 1.0 - pow(1.0 - t, 3.0);
    vec3 p = mix(aStart, position, e);
    float a = (1.0 - e) * 2.4;
    p.xy = mat2(cos(a), sin(a), -sin(a), cos(a)) * p.xy;
    vHeight = position.z;
    vAlpha = 0.35 + 0.55 * e;
    vColor = aColor;
    vConf = aConf;
    vec4 mv = modelViewMatrix * vec4(p, 1.0);
    gl_Position = projectionMatrix * mv;
    vFar = smoothstep(5.0, 11.0, -mv.z);
    gl_PointSize = uSize * (12.0 / -mv.z);
  }
`;

const fragment = /* glsl */ `
  uniform int uMode;
  uniform vec3 uLow;
  uniform vec3 uHigh;
  uniform vec3 uBg;
  uniform vec3 uWeak;
  uniform vec3 uStrong;
  varying float vHeight;
  varying float vAlpha;
  varying float vFar;
  varying vec3 vColor;
  varying float vConf;
  void main() {
    vec2 c = gl_PointCoord - 0.5;
    if (dot(c, c) > 0.25) discard;
    if (uMode == 1) {
      // the photo's own colour: sRGB bytes already, so no conversion; opaque, so the room reads as solid
      gl_FragColor = vec4(mix(vColor, uBg, vFar * 0.12), 1.0);
      return;
    }
    vec3 colour = uMode == 2
      ? mix(uWeak, uStrong, vConf)
      : mix(uLow, uHigh, smoothstep(0.1, 1.6, vHeight)); // floor in one token, walls in the other
    // far points fade towards the background for depth
    gl_FragColor = vec4(mix(colour, uBg, vFar * 0.45), vAlpha);
    #include <colorspace_fragment>
  }
`;

/** Small seeded PRNG, so the scatter looks the same on every visit (and in the poster). */
function mulberry32(seed: number) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function RoomCloud({ data, uniforms }: { data: CloudData; uniforms: CloudUniforms }) {
  const geometry = useMemo(() => {
    const { positions, colors, conf } = data;
    const count = positions.length / 3;
    const start = new Float32Array(positions.length);
    const delay = new Float32Array(count);
    const rand = mulberry32(7);
    let top = 0;
    for (let i = 0; i < count; i++) top = Math.max(top, positions[i * 3 + 2]);
    for (let i = 0; i < count; i++) {
      // a flattened shell around the room, like a cloud waiting to settle
      const angle = rand() * Math.PI * 2;
      const radius = 3.5 + rand() * 3;
      start[i * 3] = Math.cos(angle) * radius;
      start[i * 3 + 1] = Math.sin(angle) * radius;
      start[i * 3 + 2] = 1 + (rand() - 0.5) * 2.5;
      delay[i] = (positions[i * 3 + 2] / (top || 1)) * 0.3 + rand() * 0.1;
    }
    const g = new BufferGeometry();
    g.setAttribute("position", new BufferAttribute(positions, 3));
    g.setAttribute("aStart", new BufferAttribute(start, 3));
    g.setAttribute("aDelay", new BufferAttribute(delay, 1));
    g.setAttribute("aColor", new BufferAttribute(colors ?? new Uint8Array(positions.length), 3, true));
    g.setAttribute("aConf", new BufferAttribute(conf, 1, true));
    return g;
  }, [data]);

  const material = useMemo(
    () => new ShaderMaterial({ vertexShader: vertex, fragmentShader: fragment, uniforms, transparent: true, depthWrite: false }),
    [uniforms],
  );

  return <points geometry={geometry} material={material} frustumCulled={false} />;
}
