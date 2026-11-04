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
  p: "#1c1e21", // phone (the poses below)
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

// More poses for the film (docs/private/video): same head, body and legs, drawn here in the same 16 × 24 style.
const HEAD_EYES_CLOSED = [
  "....hhhhhhh.....",
  "...hhhhhhhhh....",
  "...hhsssssshh...",
  "...hssssssssh...",
  "...sseesseesh...",
  "...ssssssssss...",
  "....ssssssss....",
  ".....ssssss.....",
  "......ssss......",
];

const HEAD_CHEER = [
  "....hhhhhhh.....",
  "...hhhhhhhhh....",
  "...hhsssssshh...",
  "...hssssssssh...",
  "...sssesssesh...",
  ".s.ssssssssss.s.",
  ".s..ssssssss..s.",
  ".ss..ssssss..ss.",
  "..s...ssss...s..",
];

const BODY_REACH = [
  "s..tttttttttt..s",
  ".ssttttttttttss.",
  "...ttTTTTTTtt...",
  "...tttttttttt...",
  "...tttttttttt...",
  "....tttttttt....",
  "....tttttttt....",
];

const BODY_PHONE = [
  "....tttttttt.pp.",
  "...tttttttttspp.",
  "..sttTTTTTTtts..",
  "..sttttttttt....",
  "..stttttttttt...",
  "..s.tttttttt....",
  "....tttttttt....",
];

const BODY_CHEER = [
  "..stttttttttts..",
  "...tttttttttt...",
  "...ttTTTTTTtt...",
  "...tttttttttt...",
  "...tttttttttt...",
  "....tttttttt....",
  "....tttttttt....",
];

/** Sam searching by touch (arms out), holding a phone up, walking with eyes closed, and cheering. */
export const SAM_MORE_FRAMES = {
  reachA: [...HEAD, ...BODY_REACH, ...LEGS_WALK_A],
  reachB: [...HEAD, ...BODY_REACH, ...LEGS_WALK_B],
  reach: [...HEAD, ...BODY_REACH, ...LEGS_STAND],
  phone: [...HEAD, ...BODY_PHONE, ...LEGS_STAND],
  phoneA: [...HEAD, ...BODY_PHONE, ...LEGS_WALK_A],
  phoneB: [...HEAD, ...BODY_PHONE, ...LEGS_WALK_B],
  closedA: [...HEAD_EYES_CLOSED, ...BODY_ARMS_DOWN, ...LEGS_WALK_A],
  closedB: [...HEAD_EYES_CLOSED, ...BODY_ARMS_DOWN, ...LEGS_WALK_B],
  closed: [...HEAD_EYES_CLOSED, ...BODY_ARMS_DOWN, ...LEGS_STAND],
  cheer: [...HEAD_CHEER, ...BODY_CHEER, ...LEGS_STAND],
} as const;
