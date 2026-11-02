"use client";

import { useMemo } from "react";
import { BoxGeometry, BufferAttribute, BufferGeometry, Color, EdgesGeometry, PlaneGeometry, Shape, ShapeGeometry, SRGBColorSpace, TextureLoader, type Texture } from "three";
import { NorthArrow, type FurnitureBox, type RoomShape, type Thing, type Tokens } from "./Layers";

/** One colour per kind of furniture, like a semantic map (a legend in the controls names them). */
export const KIND_COLOURS: Record<string, string> = {
  desk: "#c9822e",
  table: "#c9822e",
  sofa: "#7a5ea8",
  chair: "#3d8c84",
  bed: "#b5546a",
  shelf: "#5b7f2c",
  cabinet: "#8a6a4f",
  tv: "#33363b",
  door: "#9aa3b2",
};
export const kindColour = (label: string) => KIND_COLOURS[label] ?? "#8792a2";

/** The colours the pipeline names, for things drawn at their measured colour. */
const NAMED: Record<string, string> = {
  black: "#222222",
  white: "#f4f4f4",
  grey: "#9a9a9a",
  red: "#d23c3c",
  orange: "#e8862a",
  yellow: "#e8c62a",
  green: "#3f9a4a",
  blue: "#3b6fd4",
  purple: "#8a4fc0",
  pink: "#e27aa6",
  brown: "#8a5a35",
  beige: "#dccaa5",
};

/**
 * The room as a plan, built only from what was measured: the floor outline filled, the walls as solid panels, the
 * furniture as boxes coloured by kind, and each thing as a small box at its measured size and colour.
 */
export function RoomModel({
  room,
  furniture,
  things,
  selected,
  tokens,
  wallOpacity = 0.45,
  showFurniture = true,
}: {
  room: RoomShape;
  furniture: FurnitureBox[];
  things: Thing[];
  selected: number | null;
  tokens: Tokens;
  /** how solid the walls look: 0.15 (see through) to 1 (opaque) */
  wallOpacity?: number;
  showFurniture?: boolean;
}) {
  const floor = useMemo(() => {
    const shape = new Shape(room.floor.map(([x, y]) => ({ x, y }) as never));
    return new ShapeGeometry(shape);
  }, [room.floor]);
  return (
    <>
      <ambientLight intensity={0.75} />
      <directionalLight position={[3, -4, 6]} intensity={1.6} />
      <mesh geometry={floor} position={[0, 0, -0.005]}>
        <meshLambertMaterial color={tokens.line} side={2} />
      </mesh>
      {room.walls.map((w, i) => (
        <SolidWall key={i} wall={w} colour={tokens.bg} edge={tokens.blueDark} opacity={wallOpacity} />
      ))}
      {showFurniture && furniture.map((f, i) => (
        <SolidBox
          key={i}
          min={f.min}
          max={f.max}
          colour={kindColour(f.label)}
          edge={tokens.blueDark}
        />
      ))}
      {things.map((t, i) => {
        const s = (t.size ?? [0.12, 0.12, 0.12]).map((v) => Math.max(v, 0.05));
        const min = [
          t.at[0] - s[0] / 2,
          t.at[1] - s[1] / 2,
          t.at[2] - s[2] / 2,
        ];
        const max = [
          t.at[0] + s[0] / 2,
          t.at[1] + s[1] / 2,
          t.at[2] + s[2] / 2,
        ];
        return (
          <SolidBox
            key={`t${i}`}
            min={min}
            max={max}
            colour={(t.color && NAMED[t.color]) || tokens.cta}
            edge={i === selected ? tokens.blueDark : tokens.muted}
            thick={i === selected}
          />
        );
      })}
    </>
  );
}

function SolidWall({
  wall,
  colour,
  edge,
  opacity = 0.45,
}: {
  wall: RoomShape["walls"][number];
  colour: string;
  edge: string;
  opacity?: number;
}) {
  const [x1, y1] = wall.start;
  const [x2, y2] = wall.end;
  const length = Math.hypot(x2 - x1, y2 - y1);
  const geometry = useMemo(
    () => new PlaneGeometry(length, wall.height_m),
    [length, wall.height_m],
  );
  const edges = useMemo(() => new EdgesGeometry(geometry), [geometry]);
  return (
    <group
      position={[(x1 + x2) / 2, (y1 + y2) / 2, wall.height_m / 2]}
      rotation={[0, 0, Math.atan2(y2 - y1, x2 - x1)]}
    >
      <group rotation={[Math.PI / 2, 0, 0]}>
        {/* see-through enough to look into the room from any side */}
        <mesh geometry={geometry}>
          <meshLambertMaterial
            color={colour}
            transparent
            opacity={opacity}
            depthWrite={opacity >= 1}
            side={2}
          />
        </mesh>
        <lineSegments geometry={edges}>
          <lineBasicMaterial color={edge} />
        </lineSegments>
      </group>
    </group>
  );
}

function SolidBox({
  min,
  max,
  colour,
  edge,
  thick = false,
}: {
  min: number[];
  max: number[];
  colour: string;
  edge: string;
  thick?: boolean;
}) {
  const [sx, sy, sz] = [max[0] - min[0], max[1] - min[1], max[2] - min[2]];
  const box = useMemo(() => new BoxGeometry(sx, sy, sz), [sx, sy, sz]);
  const edges = useMemo(() => new EdgesGeometry(box), [box]);
  return (
    <group
      position={[
        min[0] + sx / 2,
        min[1] + sy / 2,
        min[2] + sz / 2,
      ]}
      scale={thick ? 1.25 : 1}
    >
      <mesh geometry={box}>
        <meshLambertMaterial color={colour} />
      </mesh>
      <lineSegments geometry={edges}>
        <lineBasicMaterial color={edge} />
      </lineSegments>
    </group>
  );
}

export interface MeshData {
  positions: Float32Array;
  colors: Uint8Array;
  index: Uint32Array;
}

/** The measured surface (Poisson over the points, in the export), drawn with its photo colours. */
export function SurfaceMesh({ mesh, wireframe = false, flat = false }: { mesh: MeshData; wireframe?: boolean; flat?: boolean }) {
  const geometry = useMemo(() => {
    const g = new BufferGeometry();
    g.setAttribute("position", new BufferAttribute(mesh.positions, 3));
    g.setAttribute("color", new BufferAttribute(mesh.colors, 3, true));
    g.setIndex(new BufferAttribute(mesh.index, 1));
    g.computeVertexNormals();
    return g;
  }, [mesh]);
  return (
    <>
      <ambientLight intensity={1.1} />
      <directionalLight position={[3, -4, 6]} intensity={0.9} />
      <mesh geometry={geometry}>
        <meshLambertMaterial key={`${wireframe}-${flat}`} vertexColors side={2} wireframe={wireframe} flatShading={flat} />
      </mesh>
    </>
  );
}

export async function loadMesh(src: string): Promise<MeshData | null> {
  const get = (file: string) =>
    fetch(`${src}/${file}`).then((r) => (r.ok ? r.arrayBuffer() : null));
  const [p, c, i] = await Promise.all([
    get("mesh_pos.bin"),
    get("mesh_col.bin"),
    get("mesh_idx.bin"),
  ]);
  if (!p || !c || !i) return null;
  return {
    positions: new Float32Array(p),
    colors: new Uint8Array(c),
    index: new Uint32Array(i),
  };
}

export interface PhotoData {
  positions: Float32Array;
  uvs: Float32Array;
  index: Uint32Array;
  rest: Uint32Array;
  colors: Uint8Array;
  atlas: Texture;
}

/** The room's surface painted with the scan's own photos (each triangle from the photo that saw it best). */
export function PhotoRoom({ photo }: { photo: PhotoData }) {
  const [textured, rest] = useMemo(() => {
    const position = new BufferAttribute(photo.positions, 3);
    const a = new BufferGeometry();
    a.setAttribute("position", position);
    a.setAttribute("uv", new BufferAttribute(photo.uvs, 2));
    a.setIndex(new BufferAttribute(photo.index, 1));
    const b = new BufferGeometry();
    b.setAttribute("position", position);
    b.setAttribute("color", new BufferAttribute(photo.colors, 3, true));
    b.setIndex(new BufferAttribute(photo.rest, 1));
    b.computeVertexNormals();
    return [a, b];
  }, [photo]);
  return (
    <>
      <ambientLight intensity={1.1} />
      <directionalLight position={[3, -4, 6]} intensity={0.8} />
      {/* unlit: the photos already carry the room's own light */}
      <mesh geometry={textured}>
        <meshBasicMaterial map={photo.atlas} side={2} />
      </mesh>
      <mesh geometry={rest}>
        <meshLambertMaterial vertexColors side={2} />
      </mesh>
    </>
  );
}

export async function loadPhoto(src: string): Promise<PhotoData | null> {
  const get = (file: string) => fetch(`${src}/${file}`).then((r) => (r.ok ? r.arrayBuffer() : null));
  const [p, uv, i, rest, c] = await Promise.all(["photo_pos.bin", "photo_uv.bin", "photo_idx.bin", "photo_rest_idx.bin", "photo_col.bin"].map(get));
  if (!p || !uv || !i || !rest || !c) return null;
  const atlas = await new TextureLoader().loadAsync(`${src}/photo_atlas.jpg`).catch(() => null);
  if (!atlas) return null;
  atlas.colorSpace = SRGBColorSpace;
  atlas.anisotropy = 4;
  return { positions: new Float32Array(p), uvs: new Float32Array(uv), index: new Uint32Array(i), rest: new Uint32Array(rest), colors: new Uint8Array(c), atlas };
}

/** The regenerated room (architect.json, in its squared plan frame; `theta` turns it back into the scan's frame). */
export interface ArchitectData {
  theta: number;
  height: number;
  plan: number[][];
  walls: { a: number[]; b: number[]; scanned: boolean; openings: { kind: string; offset: number; width: number; height: number }[] }[];
  wall_t: number;
  floor_colour: string;
  wall_colour: string;
  furniture: { label: string; colour: string; lo: number[]; hi: number[]; parts: { kind: string; c: number[]; s: number[] }[] }[];
  things: { n: number; label: string; color: string | null; at: number[]; size: number[] | null }[];
}

/** Walls are cut at this height by default, like an architect's model, so the room can be seen into from any side. */
export const CUT = 1.1;

export function ArchitectRoom({ model, selected, tokens, cut = CUT, north }: { model: ArchitectData; selected: number | null; tokens: Tokens; cut?: number; north?: { deg?: number | null; label: string } }) {
  const floor = useMemo(() => new ShapeGeometry(new Shape(model.plan.map(([x, y]) => ({ x, y }) as never))), [model.plan]);
  const wallHeight = Math.min(cut, model.height);
  return (
    <group rotation={[0, 0, model.theta]}>
      {/* an architect's model shows north, not x/y/z axes; drawn in the plan's own frame */}
      {north && <NorthArrow floor={model.plan} northDeg={north.deg} tokens={tokens} label={north.label} theta={model.theta} />}
      <hemisphereLight args={["#ffffff", "#c9c2b6", 1.1]} />
      <directionalLight position={[2, -3, 6]} intensity={1.4} />
      <mesh geometry={floor} position={[0, 0, -0.004]}>
        <meshStandardMaterial color={model.floor_colour} roughness={0.85} side={2} />
      </mesh>
      {model.walls.flatMap((w, i) => wallPieces(w, model.wall_t).map(([s, e], j) => {
        const [ax, ay] = w.a;
        const [bx, by] = w.b;
        const len = Math.hypot(bx - ax, by - ay);
        const ux = (bx - ax) / len;
        const uy = (by - ay) / len;
        const mid = (s + e) / 2;
        // the room is on each wall's left, so the wall stands outside the measured floor
        const cx = ax + ux * mid + uy * (model.wall_t / 2);
        const cy = ay + uy * mid - ux * (model.wall_t / 2);
        return (
          <mesh key={`${i}-${j}`} position={[cx, cy, wallHeight / 2]} rotation={[0, 0, Math.atan2(uy, ux)]}>
            <boxGeometry args={[e - s, model.wall_t, wallHeight]} />
            <meshStandardMaterial color={w.scanned ? model.wall_colour : tokens.line} roughness={0.9} transparent={!w.scanned} opacity={w.scanned ? 1 : 0.35} />
          </mesh>
        );
      }))}
      {model.furniture.flatMap((f, i) =>
        f.parts.map((p, j) => (
          <mesh key={`${i}-${j}`} position={p.c as [number, number, number]}>
            <boxGeometry args={p.s as [number, number, number]} />
            <meshStandardMaterial color={p.kind === "leg" ? shade(f.colour, 0.7) : f.colour} roughness={0.7} />
          </mesh>
        )),
      )}
      {model.things.map((t) => {
        const s = (t.size ?? [0.12, 0.12, 0.12]).map((v) => Math.max(v, 0.05));
        const chosen = selected === t.n - 1;
        return (
          <mesh key={t.n} position={t.at as [number, number, number]} scale={chosen ? 1.4 : 1}>
            <boxGeometry args={s as [number, number, number]} />
            <meshStandardMaterial color={(t.color && NAMED[t.color]) || tokens.cta} emissive={chosen ? tokens.blueDark : "#000000"} emissiveIntensity={chosen ? 0.5 : 0} />
          </mesh>
        );
      })}
    </group>
  );
}

/** A wall's solid pieces along its length, leaving door openings out and closing the corners. */
function wallPieces(w: ArchitectData["walls"][number], t: number): [number, number][] {
  const len = Math.hypot(w.b[0] - w.a[0], w.b[1] - w.a[1]);
  let pieces: [number, number][] = [[-t, len + t]];
  for (const o of w.openings) {
    pieces = pieces.flatMap(([s, e]) => [[s, Math.min(e, o.offset)], [Math.max(s, o.offset + o.width), e]] as [number, number][]).filter(([s, e]) => e - s > 0.01);
  }
  return pieces;
}

function shade(hex: string, k: number): string {
  const c = new Color(hex);
  c.multiplyScalar(k);
  return `#${c.getHexString()}`;
}

export async function loadArchitect(src: string): Promise<ArchitectData | null> {
  return fetch(`${src}/architect.json`).then((r) => (r.ok ? (r.json() as Promise<ArchitectData>) : null)).catch(() => null);
}
