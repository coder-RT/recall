/** The height bands from CLAUDE.md §4 (spatial relations): floor < 0.3, knee, waist, chest, head > 1.5 m. */
export const BAND_EDGES = [0.3, 0.7, 1.1, 1.5];

export const BANDS = ["floor", "knee", "waist", "chest", "head"] as const;
export type Band = (typeof BANDS)[number];

/** The band a height (metres above the floor) falls in. */
export function bandOf(z: number): Band {
  const i = BAND_EDGES.findIndex((edge) => z < edge);
  return BANDS[i === -1 ? BANDS.length - 1 : i];
}
