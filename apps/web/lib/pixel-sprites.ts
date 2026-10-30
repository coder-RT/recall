/**
 * Sam, the pixel character in the landing story. Original art (16 × 24 cells), drawn here.
 * Frames share the head and body; only the arms and legs change.
 */

export const SAM_PALETTE: Record<string, string> = {
  h: "#7a4e2d", // hair
  s: "#f2c1a8", // skin
  e: "#1c1e21", // eyes
  t: "#4fb3e8", // tee
  T: "#3a95c7", // tee shade
  j: "#2f4a7a", // jeans
  g: "#6b7a8f", // shoes
};

const HEAD = [
  "....hhhhhhh.....",
  "...hhhhhhhhh....",
  "...hhsssssshh...",
  "...hssssssssh...",
  "...sssesssesh...",
  "...ssssssssss...",
  "....ssssssss....",
  ".....ssssss.....",
  "......ssss......",
];

const BODY_ARMS_DOWN = [
  "....tttttttt....",
  "...tttttttttt...",
  "..sttTTTTTTtts..",
  "..sttttttttts...",
  "..stttttttttts..",
  "..s.tttttttt.s..",
  "....tttttttt....",
];

const BODY_WAVE = [
  "....tttttttt.ss.",
  "...ttttttttttss.",
  "..sttTTTTTTttt..",
  "..sttttttttt....",
  "..stttttttttt...",
  "..s.tttttttt....",
  "....tttttttt....",
];

const LEGS_STAND = [
  "....jjjjjjjj....",
  "....jjj..jjj....",
  "....jjj..jjj....",
  "....jjj..jjj....",
  "....jjj..jjj....",
  "...gggg..gggg...",
  "................",
  "................",
];

const LEGS_WALK_A = [
  "....jjjjjjjj....",
  "...jjj....jjj...",
  "...jjj....jjj...",
  "..jjj......jjj..",
  "..jjj......jjj..",
  ".gggg......gggg.",
  "................",
  "................",
];

const LEGS_WALK_B = [
  "....jjjjjjjj....",
  ".....jjjjjj.....",
  ".....jjj.jjj....",
  "....jjj..jjj....",
  "....jjj...jjj...",
  "...gggg...gggg..",
  "................",
  "................",
];

export const SAM_FRAMES = {
  stand: [...HEAD, ...BODY_ARMS_DOWN, ...LEGS_STAND],
  walkA: [...HEAD, ...BODY_ARMS_DOWN, ...LEGS_WALK_A],
  walkB: [...HEAD, ...BODY_ARMS_DOWN, ...LEGS_WALK_B],
  wave: [...HEAD, ...BODY_WAVE, ...LEGS_STAND],
} as const;

export type SamFrame = keyof typeof SAM_FRAMES;
