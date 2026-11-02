/** Numbers derived from a scan's meta.json (pure, so each one is tested against the published scan). */

type Polygon = number[][];

/** Floor area from the room's outline (shoelace), in square metres. */
export function floorArea(floor: Polygon): number {
  let a = 0;
  for (let i = 0; i < floor.length; i++) {
    const [x1, y1] = floor[i];
    const [x2, y2] = floor[(i + 1) % floor.length];
    a += x1 * y2 - x2 * y1;
  }
  return Math.abs(a) / 2;
}

/** The outline's length all the way round, in metres. */
export function perimeter(floor: Polygon): number {
  let p = 0;
  for (let i = 0; i < floor.length; i++) {
    const [x1, y1] = floor[i];
    const [x2, y2] = floor[(i + 1) % floor.length];
    p += Math.hypot(x2 - x1, y2 - y1);
  }
  return p;
}

/** The outline's extent along x and y, in metres (the room's width by its length, as the floor plan measures it). */
export function extent(floor: Polygon): [number, number] {
  const xs = floor.map((p) => p[0]);
  const ys = floor.map((p) => p[1]);
  return [Math.max(...xs) - Math.min(...xs), Math.max(...ys) - Math.min(...ys)];
}

/** Things Recall waits to mention until the owner confirms them: seen in only one photo. */
export function waiting(things: { photos?: number | null }[]): number {
  return things.filter((t) => t.photos != null && t.photos < 2).length;
}

/** The mean SAM 3.1 score of the things, 0 to 1. */
export function meanConfidence(things: { confidence: number }[]): number {
  return things.length ? things.reduce((s, t) => s + t.confidence, 0) / things.length : 0;
}

/** Points per square metre of floor. */
export function density(points: number, floor: Polygon): number {
  const a = floorArea(floor);
  return a > 0 ? points / a : 0;
}
