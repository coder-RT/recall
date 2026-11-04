import type { Metadata } from "next";
import { FilmFlythrough, type FilmWalk } from "@/components/viewer/FilmFlythrough";
// the keys walk, made by Recall's own code from the recorded run (make demo-walks)
import walks from "@/public/real-scan/flat/walks.json";

export const metadata: Metadata = {
  title: "Fly-through · Recall",
  robots: { index: false, follow: false },
};

/** For the demo film only: a fly-through of the real scan with the keys walk. Not linked from the site. */
export default function FilmPage() {
  const keys = walks.walks.find((w) => w.question === "Where are my keys?") as unknown as FilmWalk & { arrive: string };
  // where they are, in the planner's own words ("…in front of you, near the desk, at knee height.")
  const place = keys.arrive.replace(/^.*in front of you, /, "").replace(/\.$/, "").replace(", at ", " · ");
  return <FilmFlythrough walk={{ ...keys, place }} src="/real-scan/flat" />;
}
