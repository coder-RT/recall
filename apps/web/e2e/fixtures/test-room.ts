/**
 * A made-up room for the viewer tests: a 4 × 3 m box with a desk, a shelf and three things. Built here in code and
 * served by the test (page.route), so no scan of a real home is ever needed or stored.
 */

const W = 4;
const D = 3;
const H = 2.4;
const STEP = 0.04;

function* grid(a: number, b: number) {
  for (let i = 0; i <= a / STEP; i++) for (let j = 0; j <= b / STEP; j++) yield [i * STEP, j * STEP] as const;
}

function build() {
  const pts: number[] = [];
  const add = (x: number, y: number, z: number) => pts.push(x - W / 2, y - D / 2, z);
  for (const [x, y] of grid(W, D)) add(x, y, 0); // floor
  for (const [x, z] of grid(W, H)) {
    add(x, 0, z); // two long walls
    add(x, D, z);
  }
  for (const [y, z] of grid(D, H)) add(0, y, z); // one short wall (the room is open on one side)
  for (const [x, y] of grid(1.2, 0.6)) add(0.4 + x, 2.2 + y, 0.75); // desk top
  for (const [x, y] of grid(0.8, 0.3)) add(2.8 + x, 0.1 + y, 1.2); // shelf
  const positions = new Float32Array(pts);
  const n = positions.length / 3;
  const colors = new Uint8Array(n * 3);
  const conf = new Uint8Array(n);
  for (let i = 0; i < n; i++) {
    const z = positions[i * 3 + 2];
    colors.set(z < 0.01 ? [150, 120, 90] : [200, 195, 185], i * 3); // a wooden floor and off-white walls
    conf[i] = (i * 37) % 256;
  }
  return { positions, colors, conf, n };
}

const room = build();

export const testMeta = {
  count: room.n,
  bounds: { min: [-W / 2, -D / 2, 0], max: [W / 2, D / 2, H] },
  surfaces: [{ z: 0.75, min: [-1.6, 0.7], max: [-0.4, 1.3], area_m2: 0.72, points: 450 }],
  room: {
    floor: [[-W / 2, -D / 2], [W / 2, -D / 2], [W / 2, D / 2], [-W / 2, D / 2]],
    walls: [
      { start: [-W / 2, -D / 2], end: [W / 2, -D / 2], height_m: H },
      { start: [-W / 2, D / 2], end: [W / 2, D / 2], height_m: H },
      { start: [-W / 2, -D / 2], end: [-W / 2, D / 2], height_m: H },
    ],
    height_m: H,
  },
  furniture: [
    { label: "desk", min: [-1.6, 0.7, 0], max: [-0.4, 1.3, 0.76], confidence: 0.9 },
    { label: "shelf", min: [0.8, -1.4, 1.1], max: [1.6, -1.1, 1.25], confidence: 0.7 },
  ],
  objects: [
    { label: "keys", color: "grey", at: [-1.0, 1.0, 0.77], confidence: 0.92 },
    { label: "bag", color: "red", at: [1.5, 0.5, 0.2], confidence: 0.7 },
    { label: "book", color: "blue", at: [1.2, -1.25, 1.27], confidence: 0.55 },
  ],
  stats: { frames: 48, total_s: 120.4, sam_calls: 384, captured: "2026-10-30" },
  mesh: { vertices: 4, triangles: 2 },
  photo: { frames_used: 1, textured_share: 1 },
  architect: { walls: 4, scanned_walls: 2 },
  drawings: [{ id: "A1.1", title: "Floor plan", file: "sheet-a1-1.svg", summary: "Floor plan of the test room: 4.00 by 3.00 metres." }],
};

/** A tiny 2 x 2 photo (warm wood and white) as a PNG, served as the photo atlas. */
const atlasPng = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGO4fu/D////GRj+////HwBUawsLYYhJNwAAAABJRU5ErkJggg==",
  "base64",
);

/** The made-up room regenerated: a 4 x 3 m plan, two walls seen, a desk as a top on four legs, one thing. */
const architect = {
  theta: 0,
  height: H,
  plan: [[-W / 2, -D / 2], [W / 2, -D / 2], [W / 2, D / 2], [-W / 2, D / 2]],
  walls: [
    { a: [-W / 2, -D / 2], b: [W / 2, -D / 2], scanned: true, openings: [] },
    { a: [W / 2, -D / 2], b: [W / 2, D / 2], scanned: false, openings: [] },
    { a: [W / 2, D / 2], b: [-W / 2, D / 2], scanned: true, openings: [{ kind: "door", offset: 1, width: 0.9, height: 2.05 }] },
    { a: [-W / 2, D / 2], b: [-W / 2, -D / 2], scanned: false, openings: [] },
  ],
  wall_t: 0.12,
  floor_colour: "#c9b79c",
  wall_colour: "#eeeae4",
  furniture: [
    {
      label: "desk",
      colour: "#8a5a35",
      lo: [-1.6, 0.7, 0],
      hi: [-0.4, 1.3, 0.76],
      parts: [
        { kind: "top", c: [-1.0, 1.0, 0.745], s: [1.2, 0.6, 0.03] },
        { kind: "leg", c: [-1.55, 0.75, 0.365], s: [0.05, 0.05, 0.73] },
        { kind: "leg", c: [-0.45, 0.75, 0.365], s: [0.05, 0.05, 0.73] },
        { kind: "leg", c: [-1.55, 1.25, 0.365], s: [0.05, 0.05, 0.73] },
        { kind: "leg", c: [-0.45, 1.25, 0.365], s: [0.05, 0.05, 0.73] },
      ],
    },
  ],
  things: [{ n: 1, label: "keys", color: "grey", at: [-1.0, 1.0, 0.77], size: [0.08, 0.05, 0.03] }],
};

const sheet = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 420 297"><title>A1.1 Floor plan</title><rect width="420" height="297" fill="#fff"/><text x="20" y="40">4.00</text></svg>`;

/** The made-up room's surface: the floor as one quad (two triangles), warm grey. */
const meshPos = new Float32Array([-W / 2, -D / 2, 0, W / 2, -D / 2, 0, W / 2, D / 2, 0, -W / 2, D / 2, 0]);
const meshCol = new Uint8Array([190, 170, 150, 190, 170, 150, 190, 170, 150, 190, 170, 150]);
const meshIdx = new Uint32Array([0, 1, 2, 0, 2, 3]);

export const testFiles: Record<string, Buffer> = {
  "points.bin": Buffer.from(room.positions.buffer),
  "colors.bin": Buffer.from(room.colors.buffer),
  "conf.bin": Buffer.from(room.conf.buffer),
  "meta.json": Buffer.from(JSON.stringify(testMeta)),
  "mesh_pos.bin": Buffer.from(meshPos.buffer),
  "mesh_col.bin": Buffer.from(meshCol.buffer),
  "mesh_idx.bin": Buffer.from(meshIdx.buffer),
  // the photo room: the floor quad again, every corner mapped into the atlas
  "photo_pos.bin": Buffer.from(meshPos.buffer),
  "photo_uv.bin": Buffer.from(new Float32Array([0, 0, 1, 0, 1, 1, 0, 1]).buffer),
  "photo_idx.bin": Buffer.from(meshIdx.buffer),
  "photo_rest_idx.bin": Buffer.from(new Uint32Array([]).buffer),
  "photo_col.bin": Buffer.from(meshCol.buffer),
  "photo_atlas.jpg": atlasPng,
  "architect.json": Buffer.from(JSON.stringify(architect)),
  "sheet-a1-1.svg": Buffer.from(sheet),
};
