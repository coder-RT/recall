"use client";

import { useEffect, useState, useSyncExternalStore } from "react";
import { format, getDictionary } from "@/i18n";
import { canSpeak, sayLine, stopSpeaking } from "@/lib/speech";

const t = getDictionary().app.hearRoom;
const noSubscribe = () => () => {};

/** The room read aloud by the browser's own voice (Web Speech, no model): what a blind visitor would want first. */
export function HearRoom({ area, things }: { area: string; things: string[] }) {
  const speech = useSyncExternalStore(noSubscribe, canSpeak, () => false);
  const [speaking, setSpeaking] = useState(false);
  useEffect(() => () => stopSpeaking(), []);
  if (!speech) return null;
  const toggle = async () => {
    if (speaking) {
      stopSpeaking();
      return setSpeaking(false);
    }
    setSpeaking(true);
    const list = things.length > 1 ? `${things.slice(0, -1).join(", ")} and ${things.at(-1)}` : things.join("");
    await sayLine(format(t.line, { area, things: list }), "assistant", { long: true });
    setSpeaking(false);
  };
  return (
    <button type="button" onClick={toggle} aria-pressed={speaking} className="btn btn-ghost mt-4 min-h-11" data-hear-room>
      {speaking ? t.stop : t.hear}
    </button>
  );
}
