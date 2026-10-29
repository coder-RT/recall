"use client";

import { useMemo } from "react";
import { BoxGeometry, Color, EdgesGeometry, PlaneGeometry } from "three";
import { BAND_EDGES } from "./bands";

export interface Surface {
  z: number;
  min: number[];
  max: number[];
  area_m2: number;
}

export interface Bounds {
  min: number[];
  max: number[];
}

/** Token colours as CSS strings, read from globals.css. */
export interface Tokens {
  line: string;
  blue: string;
  blueDark: string;
  bg: string;
  muted: string;
  cta: string;
}

/** A metre grid on the floor plane (z = 0 in the home frame). */
export function FloorGrid({ bounds, tokens }: { bounds: Bounds; tokens: Tokens }) {
  const size = Math.ceil(Math.max(bounds.max[0] - bounds.min[0], bounds.max[1] - bounds.min[1])) + 1;
  const colour = useMemo(() => new Color(tokens.line), [tokens.line]);
  // gridHelper lies in XZ; our up is Z, so turn it onto XY
  return <gridHelper args={[size, size * 2, colour, colour]} rotation={[Math.PI / 2, 0, 0]} position={[0, 0, 0.005]} />;
}

/** Translucent sheets at the band edges, so a point's band can be read at a glance. */
export function HeightBands({ bounds, tokens }: { bounds: Bounds; tokens: Tokens }) {
  const w = bounds.max[0] - bounds.min[0];
  const h = bounds.max[1] - bounds.min[1];
  const cx = (bounds.max[0] + bounds.min[0]) / 2;
  const cy = (bounds.max[1] + bounds.min[1]) / 2;
  const geometry = useMemo(() => new PlaneGeometry(w, h), [w, h]);
  const edges = useMemo(() => new EdgesGeometry(geometry), [geometry]);
  return (
    <>
      {BAND_EDGES.map((z) => (
        <group key={z} position={[cx, cy, z]}>
          <mesh geometry={geometry}>
            <meshBasicMaterial color={tokens.blueDark} transparent opacity={0.07} depthWrite={false} side={2} />
          </mesh>
          <lineSegments geometry={edges}>
            <lineBasicMaterial color={tokens.blueDark} transparent opacity={0.5} />
          </lineSegments>
        </group>
      ))}
    </>
  );
}

/** Horizontal surfaces the export found (desk tops, shelf levels, seats): thin slabs with an outline. */
export function Surfaces({ surfaces, tokens }: { surfaces: Surface[]; tokens: Tokens }) {
  return (
    <>
      {surfaces.map((s, i) => {
        const w = s.max[0] - s.min[0];
        const h = s.max[1] - s.min[1];
        return <SurfaceSlab key={i} w={w} h={h} position={[s.min[0] + w / 2, s.min[1] + h / 2, s.z]} colour={tokens.cta} />;
      })}
    </>
  );
}

function SurfaceSlab({ w, h, position, colour }: { w: number; h: number; position: [number, number, number]; colour: string }) {
  const geometry = useMemo(() => new BoxGeometry(w, h, 0.02), [w, h]);
  const edges = useMemo(() => new EdgesGeometry(geometry), [geometry]);
  return (
    <group position={position}>
      <mesh geometry={geometry}>
        <meshBasicMaterial color={colour} transparent opacity={0.35} depthWrite={false} />
      </mesh>
      <lineSegments geometry={edges}>
        <lineBasicMaterial color={colour} />
      </lineSegments>
    </group>
  );
}
