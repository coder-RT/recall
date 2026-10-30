/**
 * Timing and voices of the landing story "One morning, one mug" (the words are in
 * i18n/dictionaries, story.captions). Illustrative, not a recording of the app (rule 3): labelled
 * as a sample story. `at` is seconds into the 12-second timeline.
 *
 * Voices: Sam (the man in the blue tee) is male, the mug is female, Recall has its own assistant
 * voice. With narration on, each line is spoken by the browser's own speech synthesis in that role
 * (lib/speech.ts); no recording is shipped and no speech model runs.
 */

import type { VoiceRole } from "@/lib/speech";

export const STORY_SECONDS = 12;

export const captionTimes = [
  { at: 0, key: "wants", voice: "narrator" },
  { at: 2.2, key: "notHere", voice: "narrator" },
  { at: 5.25, key: "asks", voice: "male" },
  { at: 6.2, key: "answer", voice: "assistant" },
  // each line starts after its visuals have settled: the mug is out and awake before it speaks
  { at: 8.9, key: "here", voice: "female" },
  { at: 10.1, key: "there", voice: "male" },
  { at: 10.9, key: "found", voice: "female" },
] as const satisfies readonly { at: number; key: string; voice: VoiceRole }[];
