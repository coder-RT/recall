"use client";

import { useFrame } from "@react-three/fiber";
import { useMemo, useRef } from "react";
import { BoxGeometry, BufferGeometry, CanvasTexture, Color, EdgesGeometry, Float32BufferAttribute, type Group, PlaneGeometry, SRGBColorSpace } from "three";
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

export interface RoomShape {
  floor: number[][];
  walls: { start: number[]; end: number[]; height_m: number }[];
  /** floor to ceiling, metres (newer exports) */
  height_m?: number;
  /** magnetic north, degrees clockwise from +y, when the scan measured it */
  north_deg?: number | null;
  /** the room's name (newer exports) */
  name?: string;
}

export interface FurnitureBox {
  label: string;
  min: number[];
  max: number[];
}

export interface Thing {
  label: string;
  color: string | null;
  at: number[];
  /** measured size in metres (x, y, z), when the pipeline has one */
  size?: number[] | null;
  confidence: number;
  /** how many of the scan's photos showed it (newer exports) */
  photos?: number | null;
  /** the room it was seen in (newer exports) */
  room?: string | null;
}

/** The room model the pipeline built: floor outline at z = 0 and the walls as thin translucent sheets. */
export function Room({ room, tokens }: { room: RoomShape; tokens: Tokens }) {
  const outline = useMemo(() => {
    const ring = [...room.floor, room.floor[0]].flatMap(([x, y]) => [x, y, 0.01]);
    return new Float32Array(ring);
  }, [room.floor]);
  return (
    <>
      <line>
        <bufferGeometry>
          <bufferAttribute attach="attributes-position" args={[outline, 3]} />
        </bufferGeometry>
        <lineBasicMaterial color={tokens.blueDark} />
      </line>
      {room.walls.map((w, i) => (
        <Wall key={i} wall={w} colour={tokens.blueDark} />
      ))}
    </>
  );
}

function Wall({ wall, colour }: { wall: RoomShape["walls"][number]; colour: string }) {
  const [x1, y1] = wall.start;
  const [x2, y2] = wall.end;
  const length = Math.hypot(x2 - x1, y2 - y1);
  const geometry = useMemo(() => new PlaneGeometry(length, wall.height_m), [length, wall.height_m]);
  const edges = useMemo(() => new EdgesGeometry(geometry), [geometry]);
  // a plane in XY, stood up (rotate about X) and turned along the wall (rotate about Z)
  return (
    <group position={[(x1 + x2) / 2, (y1 + y2) / 2, wall.height_m / 2]} rotation={[0, 0, Math.atan2(y2 - y1, x2 - x1)]}>
      <group rotation={[Math.PI / 2, 0, 0]}>
        <mesh geometry={geometry}>
          <meshBasicMaterial color={colour} transparent opacity={0.06} depthWrite={false} side={2} />
        </mesh>
        <lineSegments geometry={edges}>
          <lineBasicMaterial color={colour} transparent opacity={0.55} />
        </lineSegments>
      </group>
    </group>
  );
}

/** Furniture boxes as outlines. */
export function Furniture({ items, tokens }: { items: FurnitureBox[]; tokens: Tokens }) {
  return (
    <>
      {items.map((f, i) => (
        <BoxOutline key={i} min={f.min} max={f.max} colour={tokens.muted} />
      ))}
    </>
  );
}

function BoxOutline({ min, max, colour }: { min: number[]; max: number[]; colour: string }) {
  const size = [max[0] - min[0], max[1] - min[1], max[2] - min[2]];
  const edges = useMemo(() => new EdgesGeometry(new BoxGeometry(size[0], size[1], size[2])), [size[0], size[1], size[2]]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <lineSegments geometry={edges} position={[min[0] + size[0] / 2, min[1] + size[1] / 2, min[2] + size[2] / 2]}>
      <lineBasicMaterial color={colour} />
    </lineSegments>
  );
}

/**
 * One Facebook-blue arrow per object, pointing down at it from just above its top, with a thin stem to the floor so
 * its height reads; the chosen one is larger, dark blue and haloed. `bob` lets the arrows rise and fall gently (off
 * when motion is reduced).
 */
export function Things({ items, selected, tokens, bob = false }: { items: Thing[]; selected: number | null; tokens: Tokens; bob?: boolean }) {
  return (
    <>
      {items.map((t, i) => (
        <Arrow key={i} thing={t} chosen={i === selected} colour={i === selected ? tokens.blueDark : tokens.blue} edge={tokens.bg} bob={bob} />
      ))}
    </>
  );
}

// home frame: z up. three's cylinders stand along +y, and with radiusBottom 0 the point is at -y; turning +90°
// about x takes +y to +z, so the point faces down (-z).
const DOWN: [number, number, number] = [Math.PI / 2, 0, 0];

// arrows are drawn over the points (no depth test, late in the transparent pass the cloud also uses), so a thing
// inside a shelf or behind a chair still shows; no tone mapping, so they keep the exact token colours
function Arrow({ thing, chosen, colour, edge, bob }: { thing: Thing; chosen: boolean; colour: string; edge: string; bob: boolean }) {
  const ref = useRef<Group>(null);
  const [x, y, z] = thing.at;
  const top = z + Math.max(thing.size?.[2] ?? 0.1, 0.05) / 2 + 0.04; // the tip, just above the thing
  const k = chosen ? 1.5 : 1;
  const head = 0.12 * k;
  const shaft = 0.16 * k;
  const stem = useMemo(() => new Float32Array([x, y, 0, x, y, top]), [x, y, top]);
  useFrame(({ clock }) => {
    if (ref.current) ref.current.position.z = bob ? top + 0.03 * (1 + Math.sin(clock.elapsedTime * 2.4)) : top;
  });
  const part = (key: string, args: [number, number, number, number], at: number, scale: number, fill: string, order: number) => (
    <mesh key={key} position={[0, 0, at]} rotation={DOWN} scale={scale} renderOrder={order}>
      <cylinderGeometry args={args} />
      <meshBasicMaterial color={fill} transparent depthTest={false} toneMapped={false} />
    </mesh>
  );
  return (
    <>
      <group ref={ref} position={[x, y, top]}>
        {chosen && (
          <mesh position={[0, 0, head / 2]} renderOrder={9}>
            <sphereGeometry args={[head * 1.4, 24, 16]} />
            <meshBasicMaterial color={colour} transparent opacity={0.22} depthTest={false} toneMapped={false} />
          </mesh>
        )}
        {/* a white edge (the same shapes a little larger, drawn first), then the blue */}
        {part("he", [0.07 * k, 0, head, 24], head / 2, 1.18, edge, 10)}
        {part("se", [0.025 * k, 0.025 * k, shaft, 12], head + shaft / 2, 1.3, edge, 10)}
        {part("h", [0.07 * k, 0, head, 24], head / 2, 1, colour, 11)}
        {part("s", [0.025 * k, 0.025 * k, shaft, 12], head + shaft / 2, 1, colour, 11)}
      </group>
      <line>
        <bufferGeometry>
          <bufferAttribute attach="attributes-position" args={[stem, 3]} />
        </bufferGeometry>
        <lineBasicMaterial color={colour} depthTest={false} transparent opacity={chosen ? 0.9 : 0.5} toneMapped={false} />
      </line>
    </>
  );
}


/** A text label that always faces the camera: a sprite carrying a small canvas. */
function Label({ text, at, colour, size = 0.34 }: { text: string; at: [number, number, number]; colour: string; size?: number }) {
  const { texture, aspect } = useMemo(() => {
    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d")!;
    const font = "600 64px system-ui, -apple-system, sans-serif";
    ctx.font = font;
    const w = Math.ceil(ctx.measureText(text).width) + 24;
    canvas.width = w;
    canvas.height = 88;
    ctx.font = font;
    ctx.fillStyle = colour;
    ctx.textBaseline = "middle";
    ctx.fillText(text, 12, 46);
    const tex = new CanvasTexture(canvas);
    tex.colorSpace = SRGBColorSpace;
    return { texture: tex, aspect: w / 88 };
  }, [text, colour]);
  return (
    <sprite position={at} scale={[size * aspect, size, 1]}>
      <spriteMaterial map={texture} transparent depthWrite={false} />
    </sprite>
  );
}

function Line({ points, colour }: { points: number[]; colour: string }) {
  const geometry = useMemo(() => {
    const g = new BufferGeometry();
    g.setAttribute("position", new Float32BufferAttribute(points, 3));
    return g;
  }, [points]);
  return (
    <lineSegments geometry={geometry}>
      <lineBasicMaterial color={colour} />
    </lineSegments>
  );
}

/**
 * The room's axes from its corner on the floor: x and y along the floor and z up, every metre marked, and magnetic
 * north when the scan measured it (`north_deg` is clockwise from +y, as the API's routes use it).
 */
export function Axes({ floor, height, northDeg, tokens, labels }: { floor: number[][]; height?: number; northDeg?: number | null; tokens: Tokens; labels: { x: string; y: string; z: string; north: string } }) {
  // from the floor outline's corner, so the axes hug the room rather than the padded scan bounds
  const x0 = Math.min(...floor.map((p) => p[0]));
  const y0 = Math.min(...floor.map((p) => p[1]));
  const x1 = x0 + Math.ceil(Math.max(...floor.map((p) => p[0])) - x0);
  const y1 = y0 + Math.ceil(Math.max(...floor.map((p) => p[1])) - y0);
  const z1 = Math.max(2, Math.ceil(height ?? 2.5));
  const segments = useMemo(() => {
    const p: number[] = [x0, y0, 0, x1, y0, 0, x0, y0, 0, x0, y1, 0, x0, y0, 0, x0, y0, z1];
    const tick = 0.08;
    for (let x = x0 + 1; x <= x1; x++) p.push(x, y0 - tick, 0, x, y0 + tick, 0);
    for (let y = y0 + 1; y <= y1; y++) p.push(x0 - tick, y, 0, x0 + tick, y, 0);
    for (let z = 1; z <= z1; z++) p.push(x0 - tick, y0, z, x0 + tick, y0, z);
    return p;
  }, [x0, y0, x1, y1, z1]);
  const north = northDeg == null ? null : ((northDeg * Math.PI) / 180);
  const cx = (x0 + x1) / 2;
  const cy = (y0 + y1) / 2;
  return (
    <group data-axes>
      <Line points={segments} colour={tokens.blueDark} />
      <Label text={labels.x} at={[x1 + 0.55, y0, 0.05]} colour={tokens.blueDark} />
      <Label text={labels.y} at={[x0, y1 + 0.55, 0.05]} colour={tokens.blueDark} />
      <Label text={labels.z} at={[x0, y0, z1 + 0.4]} colour={tokens.blueDark} />
      {Array.from({ length: x1 - x0 }, (_, i) => (
        <Label key={`x${i}`} text={`${i + 1}`} at={[x0 + i + 1, y0 - 0.3, 0.02]} colour={tokens.muted} size={0.24} />
      ))}
      {Array.from({ length: y1 - y0 }, (_, i) => (
        <Label key={`y${i}`} text={`${i + 1}`} at={[x0 - 0.3, y0 + i + 1, 0.02]} colour={tokens.muted} size={0.24} />
      ))}
      {Array.from({ length: z1 }, (_, i) => (
        <Label key={`z${i}`} text={`${i + 1}`} at={[x0 - 0.3, y0, i + 1]} colour={tokens.muted} size={0.24} />
      ))}
      {north !== null && (
        <>
          <Line points={[cx, cy, 0.02, cx + Math.sin(north) * 1.2, cy + Math.cos(north) * 1.2, 0.02]} colour={tokens.cta} />
          <Label text={labels.north} at={[cx + Math.sin(north) * 1.45, cy + Math.cos(north) * 1.45, 0.08]} colour={tokens.cta} size={0.4} />
        </>
      )}
    </group>
  );
}
