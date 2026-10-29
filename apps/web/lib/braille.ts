/**
 * Data for the hero wordmark: the word drawn as a dot-matrix (so sighted visitors can read it)
 * and the same word as real six-dot Braille cells.
 */

/** 5×7 dot-matrix glyphs, one string per row, "#" = dot. */
const MATRIX: Record<string, string[]> = {
  R: ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
  E: ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
  C: [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
  A: [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
  L: ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
};

/**
 * Grade 1 Braille, dot numbers per letter. Cell layout:
 *   1 4
 *   2 5
 *   3 6
 */
const BRAILLE: Record<string, number[]> = {
  R: [1, 2, 3, 5],
  E: [1, 5],
  C: [1, 4],
  A: [1],
  L: [1, 2, 3],
};

/** UEB capital indicator: dot 6. Written twice (⠠⠠) before a word in all capitals. */
const CAPITAL_SIGN = [6];

const toChar = (dots: number[]) => String.fromCodePoint(0x2800 + dots.reduce((bits, d) => bits | (1 << (d - 1)), 0));

/** Unicode Braille pattern for a letter (U+2800 + bit per dot). */
export function brailleChar(letter: string): string {
  return toChar(BRAILLE[letter.toUpperCase()] ?? []);
}

export interface BrailleCell {
  dots: number[];
  char: string;
  /** True for the capital-word indicator cells. */
  indicator: boolean;
}

/** A word as Braille cells; capsWord prefixes the UEB capital-word indicator ⠠⠠. */
export function brailleCells(word: string, { capsWord = false } = {}): BrailleCell[] {
  const letters = [...word.toUpperCase()].map((ch) => ({ dots: BRAILLE[ch] ?? [], char: brailleChar(ch), indicator: false }));
  if (!capsWord) return letters;
  const sign = { dots: CAPITAL_SIGN, char: toChar(CAPITAL_SIGN), indicator: true };
  return [sign, { ...sign }, ...letters];
}

/** Where dot d (1–6) sits inside a cell: column 0|1, row 0|1|2. */
export const dotPosition = (d: number) => ({ col: d <= 3 ? 0 : 1, row: (d - 1) % 3 });

/**
 * Points on a unit sphere (Fibonacci lattice), evenly spread. Used for the hero's particle orb;
 * the caller rotates and projects them.
 */
export function orbPoints(n: number): { x: number; y: number; z: number }[] {
  const golden = Math.PI * (3 - Math.sqrt(5));
  return Array.from({ length: n }, (_, i) => {
    const y = 1 - (2 * (i + 0.5)) / n;
    const radius = Math.sqrt(1 - y * y);
    const theta = golden * i;
    return { x: Math.cos(theta) * radius, y, z: Math.sin(theta) * radius };
  });
}

export interface MatrixDot {
  letter: number;
  col: number;
  row: number;
  x: number;
  y: number;
}

/** Grid size: letters are 5 columns wide with a 2-column gap. */
export const GLYPH = { cols: 5, rows: 7, gap: 2 } as const;

/** Dot-matrix positions for a word, in grid units (multiply by your pitch to draw). */
export function matrixDots(word: string): MatrixDot[] {
  const out: MatrixDot[] = [];
  [...word.toUpperCase()].forEach((ch, letter) => {
    const rows = MATRIX[ch];
    if (!rows) return;
    const left = letter * (GLYPH.cols + GLYPH.gap);
    rows.forEach((line, row) => {
      [...line].forEach((cell, col) => {
        if (cell === "#") out.push({ letter, col, row, x: left + col, y: row });
      });
    });
  });
  return out;
}

/** Width of a word in grid units. */
export const wordWidth = (word: string) => word.length * (GLYPH.cols + GLYPH.gap) - GLYPH.gap;
