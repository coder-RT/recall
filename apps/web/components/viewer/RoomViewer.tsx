"use client";

import dynamic from "next/dynamic";
import type { ViewerProps } from "./ViewerCanvas";

// three.js only runs in the browser; the server sends the caption, stats and noscript poster.
const ViewerCanvas = dynamic(() => import("./ViewerCanvas"), { ssr: false });

export function RoomViewer(props: ViewerProps) {
  return <ViewerCanvas {...props} />;
}
