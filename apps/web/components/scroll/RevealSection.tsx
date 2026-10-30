"use client";

import type { ComponentProps } from "react";
import { useSectionReveal } from "@/lib/reveal";

/** A <section> whose [data-eyebrow] / [data-heading] / [data-reveal] / [data-card] children animate in once. */
export function RevealSection(props: ComponentProps<"section">) {
  const ref = useSectionReveal<HTMLElement>();
  return <section ref={ref} {...props} />;
}
