/**
 * Types for the sample "memories" in the landing feed. The posts themselves are text, so they live
 * in i18n/dictionaries (feed.posts). Illustrative only, not real Recall output (rule 3): the feed is
 * labelled as such in the UI. Tiles are drawn scenes, not photos of a real home.
 */

export type Scene = "hallway" | "shelf" | "kitchen" | "desk" | "sofa" | "bedside" | "door";

export interface MemoryPost {
  id: string;
  object: string;
  emoji: string;
  seen: string;
  room: string;
  text: string;
  tags: string[];
  tiles: Scene[];
  /** Extra sightings hidden behind the "+n" tile. */
  more: number;
  reactions: number;
  asks: number;
}
