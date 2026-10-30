/**
 * Pixel icons for the floating reactions and feed stickers (original art, drawn here).
 * Each icon is a few simple shapes rasterised onto a 32 × 32 grid; a one-pixel outline is then
 * added around everything, so the whole set shares one crisp line-art edge. Cells are merged into
 * horizontal runs to keep the SVG small.
 */

const GRID = 32;
const OUTLINE = "#1c1e21";

type Point = [number, number];
type Shape =
  | { circle: [cx: number, cy: number, r: number]; fill: string | null }
  | { ellipse: [cx: number, cy: number, rx: number, ry: number]; fill: string | null }
  | { rect: [x: number, y: number, w: number, h: number, r?: number]; fill: string | null }
  | { poly: Point[]; fill: string | null }
  | { ring: [cx: number, cy: number, r: number, width: number]; fill: string | null }
  | { line: Point[]; width: number; fill: string | null }
  | { px: Point[]; fill: string | null };

// palette
const C = {
  ink: OUTLINE,
  white: "#ffffff",
  blue: "#3b5998",
  blueLight: "#6d8fd8",
  red: "#e0245e",
  redDark: "#b3164a",
  pink: "#ff9bbb",
  yellow: "#ffcc33",
  yellowDark: "#f0a81c",
  skin: "#f6c7a8",
  skinLight: "#fde0cc",
  skinDark: "#dc9f7c",
  gold: "#f2b632",
  goldDark: "#c98a12",
  lens: "#bfe3ff",
  leather: "#a8572e",
  leatherDark: "#7a3b1d",
  phone: "#2b2f36",
  screen: "#8fb3e8",
  grey: "#9aa4b2",
  cream: "#fff8ef",
  coffee: "#6b3e1f",
  steam: "#8b9dc3",
  green: "#42b72a",
};

/** Points of a star: `spikes` tips at radius `outer`, valleys at `inner`, first tip straight up. */
function star(cx: number, cy: number, outer: number, inner: number, spikes = 5): Point[] {
  return Array.from({ length: spikes * 2 }, (_, i) => {
    const r = i % 2 ? inner : outer;
    const a = (Math.PI * i) / spikes - Math.PI / 2;
    return [cx + Math.cos(a) * r, cy + Math.sin(a) * r];
  });
}

/** A heart: two lobes and a point, centred on cx, with its top at `top`, `w` wide. */
function heart(cx: number, top: number, w: number, fill: string): Shape[] {
  const r = w / 4;
  return [
    { circle: [cx - r, top + r, r], fill },
    { circle: [cx + r, top + r, r], fill },
    { poly: [[cx - w / 2 + 0.2, top + r * 1.25], [cx + w / 2 - 0.2, top + r * 1.25], [cx, top + w * 0.95]], fill },
  ];
}

const ICONS = {
  // Facebook-style like: white thumb on a blue disc
  like: [
    { circle: [16, 16, 14.5], fill: C.blue },
    { rect: [8, 15, 4, 9], fill: C.white },
    { rect: [12.5, 13.5, 11, 10.5, 2], fill: C.white },
    { poly: [[12.5, 15], [15, 7.5], [17.5, 7], [18.5, 9.5], [17.5, 14]], fill: C.white },
    { line: [[18, 17], [23, 17]], width: 1, fill: C.blue },
    { line: [[18, 20], [23, 20]], width: 1, fill: C.blue },
  ],
  // Facebook-style love: white heart on a red disc
  love: [{ circle: [16, 16, 14.5], fill: C.red }, ...heart(16, 9, 15, C.white)],
  heart: [...heart(16, 5, 25, C.red), { line: [[16, 27], [24.5, 13.5]], width: 2, fill: C.redDark }, { circle: [10, 10.5, 2], fill: C.pink }],
  // a finger heart: thumb and index finger crossed in an X above a curled fist, a small heart
  // over the crossing
  heartHands: [
    ...heart(16, 1, 9, C.red),
    { rect: [9.5, 20, 16, 11, 4.5], fill: C.skin },
    // index finger, from the fist up to the left
    { line: [[21.5, 22], [12.5, 13.5]], width: 4.6, fill: C.skin },
    // thumb, from the fist up to the right, lying over the index finger
    { line: [[11.5, 23], [20.5, 13.5]], width: 4.6, fill: C.skinLight },
    { line: [[12.5, 24.5], [21, 15]], width: 1, fill: C.skinDark },
    // curled fingers
    { line: [[15.5, 25.5], [23.5, 25.5]], width: 1, fill: C.skinDark },
    { line: [[14.5, 28.5], [23, 28.5]], width: 1, fill: C.skinDark },
  ],
  // smiley in sunglasses
  cool: [
    { circle: [16, 16, 14], fill: C.yellow },
    { ring: [16, 16, 14, 1.6], fill: C.yellowDark },
    { rect: [5.5, 10.5, 9.5, 6.5, 2.5], fill: C.ink },
    { rect: [17, 10.5, 9.5, 6.5, 2.5], fill: C.ink },
    { line: [[14, 12.5], [18, 12.5]], width: 2, fill: C.ink },
    { line: [[2.5, 12.5], [5.5, 12.5]], width: 1.4, fill: C.ink },
    { line: [[26.5, 12.5], [29.5, 12.5]], width: 1.4, fill: C.ink },
    { px: [[7, 11], [8, 11], [7, 12], [19, 11], [20, 11], [19, 12]], fill: C.white },
    { line: [[10, 21], [13, 23.6], [19, 23.6], [22, 21]], width: 1.6, fill: C.ink },
  ],
  star: [{ poly: star(16, 17, 15, 6.5), fill: C.yellow }, { poly: star(16, 17.5, 9, 4), fill: "#ffe080" }, { px: [[13, 13], [14, 13]], fill: C.white }],
  key: [
    { circle: [9.5, 12, 7.2], fill: C.gold },
    { circle: [9.5, 12, 3.3], fill: null },
    { rect: [15.5, 10, 14, 4.5, 1], fill: C.gold },
    { rect: [21.5, 13.5, 3, 5.5], fill: C.gold },
    { rect: [26.5, 13.5, 3, 4], fill: C.gold },
    { line: [[16.5, 13.8], [29, 13.8]], width: 1, fill: C.goldDark },
    { px: [[6, 8], [7, 7]], fill: C.white },
  ],
  glasses: [
    { circle: [9, 17, 6.5], fill: C.lens },
    { circle: [23, 17, 6.5], fill: C.lens },
    { ring: [9, 17, 6.5, 2], fill: C.ink },
    { ring: [23, 17, 6.5, 2], fill: C.ink },
    { line: [[14.5, 15], [17.5, 15]], width: 2, fill: C.ink },
    { line: [[3, 15], [1.5, 10.5]], width: 1.6, fill: C.ink },
    { line: [[29, 15], [30.5, 10.5]], width: 1.6, fill: C.ink },
    { px: [[6, 14], [7, 13], [20, 14], [21, 13]], fill: C.white },
  ],
  wallet: [
    { rect: [3.5, 8.5, 25, 18, 3], fill: C.leather },
    { line: [[5.5, 11.5], [26.5, 11.5]], width: 1, fill: C.leatherDark },
    { rect: [16, 13, 13.5, 9.5, 2.5], fill: C.leatherDark },
    { circle: [20.5, 17.5, 1.6], fill: C.gold },
  ],
  phone: [
    { rect: [8.5, 2.5, 15, 27, 3.5], fill: C.phone },
    { rect: [10.5, 6.5, 11, 17.5, 1], fill: C.screen },
    { line: [[14, 4.5], [18, 4.5]], width: 1, fill: C.grey },
    { circle: [16, 26.5, 1.4], fill: C.grey },
    { line: [[12, 12], [16, 8]], width: 1, fill: C.white },
  ],
  remote: [
    { rect: [10.5, 1.5, 11, 29, 4], fill: C.phone },
    { circle: [16, 6.5, 1.9], fill: C.red },
    ...[11, 15, 19, 23].flatMap((y): Shape[] => [
      { circle: [13.5, y, 1.2], fill: C.grey },
      { circle: [18.5, y, 1.2], fill: C.grey },
    ]),
  ],
  mug: [
    { ring: [22, 19.5, 5.5, 2.4], fill: C.cream },
    { rect: [4.5, 11, 17, 18, 3.5], fill: C.cream },
    { rect: [4.5, 19, 17, 4], fill: C.blue },
    { ellipse: [13, 12.5, 7, 1.6], fill: C.coffee },
    { line: [[9.5, 8.5], [8.5, 6.5], [10, 4.5], [9, 2.5]], width: 1.4, fill: C.steam },
    { line: [[15.5, 8.5], [14.5, 6.5], [16, 4.5], [15, 2.5]], width: 1.4, fill: C.steam },
    { line: [[7.5, 14.5], [7.5, 17.5]], width: 1, fill: C.white },
  ],
  // "found it": a magnifying glass with a green tick badge
  found: [
    { circle: [13, 13, 8.5], fill: C.lens },
    { ring: [13, 13, 8.5, 2.2], fill: C.ink },
    { line: [[19.5, 19.5], [28, 28]], width: 3, fill: C.ink },
    { px: [[9, 9], [10, 8], [8, 11]], fill: C.white },
    { circle: [24, 23.5, 5.5], fill: C.green },
    { line: [[21, 23.5], [23.5, 26], [27.5, 21]], width: 1.6, fill: C.white },
  ],
  // "last seen ten past ten"
  clock: [
    { circle: [16, 16, 14], fill: C.white },
    { ring: [16, 16, 14, 2.2], fill: C.ink },
    { px: [[16, 5], [27, 16], [16, 27], [5, 16]], fill: C.ink },
    { line: [[16, 16], [10.5, 12]], width: 2, fill: C.ink },
    { line: [[16, 16], [21.5, 8.5]], width: 1.6, fill: C.ink },
    { circle: [16, 16, 1.4], fill: C.red },
  ],
} satisfies Record<string, Shape[]>;

export type PixelIconName = keyof typeof ICONS;
export const PIXEL_ICON_NAMES = Object.keys(ICONS) as PixelIconName[];

export interface PixelRect {
  x: number;
  y: number;
  /** Width in cells (runs of one colour are merged); height is always one cell. */
  w: number;
  fill: string;
}

function inside(shape: Shape, x: number, y: number): boolean {
  if ("circle" in shape) {
    const [cx, cy, r] = shape.circle;
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r;
  }
  if ("ellipse" in shape) {
    const [cx, cy, rx, ry] = shape.ellipse;
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1;
  }
  if ("rect" in shape) {
    const [rx, ry, w, h, r = 0] = shape.rect;
    // distance from the point to the rectangle shrunk by the corner radius
    const dx = Math.max(rx + r - x, 0, x - (rx + w - r));
    const dy = Math.max(ry + r - y, 0, y - (ry + h - r));
    return x >= rx && x <= rx + w && y >= ry && y <= ry + h && dx * dx + dy * dy <= r * r;
  }
  if ("ring" in shape) {
    const [cx, cy, r, width] = shape.ring;
    const d = Math.hypot(x - cx, y - cy);
    return d <= r && d >= r - width;
  }
  if ("poly" in shape) {
    let hit = false;
    const p = shape.poly;
    for (let i = 0, j = p.length - 1; i < p.length; j = i++) {
      const [xi, yi] = p[i];
      const [xj, yj] = p[j];
      if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) hit = !hit;
    }
    return hit;
  }
  if ("line" in shape) {
    const half = shape.width / 2;
    return shape.line.slice(1).some(([x2, y2], i) => {
      const [x1, y1] = shape.line[i];
      const len2 = (x2 - x1) ** 2 + (y2 - y1) ** 2 || 1;
      const t = Math.max(0, Math.min(1, ((x - x1) * (x2 - x1) + (y - y1) * (y2 - y1)) / len2));
      return Math.hypot(x - (x1 + t * (x2 - x1)), y - (y1 + t * (y2 - y1))) <= half;
    });
  }
  return shape.px.some(([px, py]) => Math.floor(x) === px && Math.floor(y) === py);
}

const cache = new Map<PixelIconName, PixelRect[]>();

/** The icon as runs of cells on its 32 × 32 grid, outline included. */
export function pixelRects(name: PixelIconName): PixelRect[] {
  const hit = cache.get(name);
  if (hit) return hit;

  const grid: (string | null)[][] = Array.from({ length: GRID }, () => Array(GRID).fill(null));
  for (const shape of ICONS[name] as Shape[]) {
    for (let y = 0; y < GRID; y++) {
      for (let x = 0; x < GRID; x++) if (inside(shape, x + 0.5, y + 0.5)) grid[y][x] = shape.fill;
    }
  }
  // outline: every empty cell touching a filled one (also inside holes, like the key's bow)
  const filled = (x: number, y: number) => grid[y]?.[x] != null;
  const out = grid.map((row, y) =>
    row.map((cell, x) => cell ?? (filled(x - 1, y) || filled(x + 1, y) || filled(x, y - 1) || filled(x, y + 1) ? OUTLINE : null)),
  );

  const rects: PixelRect[] = [];
  out.forEach((row, y) => {
    for (let x = 0; x < GRID; ) {
      const fill = row[x];
      let w = 1;
      while (fill && row[x + w] === fill) w++;
      if (fill) rects.push({ x, y, w, fill });
      x += w;
    }
  });
  cache.set(name, rects);
  return rects;
}

/** SVG markup for an icon, for places that build DOM directly (the reaction layer). */
export function pixelSvg(name: PixelIconName, size: number): string {
  const rects = pixelRects(name)
    .map((r) => `<rect x="${r.x}" y="${r.y - 0.02}" width="${r.w}" height="1.04" fill="${r.fill}"/>`)
    .join("");
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${GRID} ${GRID}" width="${size}" height="${size}" shape-rendering="crispEdges">${rects}</svg>`;
}

export const PIXEL_GRID = GRID;

/** Which icon stands for each sample post's object (feed.posts ids in the dictionary). */
export const objectIcon: Record<string, PixelIconName> = {
  keys: "key",
  glasses: "glasses",
  wallet: "wallet",
  phone: "phone",
  remote: "remote",
  mug: "mug",
};

/** The filled cells of a hand-drawn pixel grid (one string per row, one palette key per cell). */
export function gridRects(rows: readonly string[], palette: Record<string, string>) {
  return rows.flatMap((row, y) => [...row].flatMap((ch, x) => (palette[ch] ? [{ x, y, fill: palette[ch] }] : [])));
}
