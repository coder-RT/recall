/**
 * Where a home's scan comes from. The author's real living room is published, geometry only (no photo data:
 * make public-scan), in public/real-scan/<home>/; any other home is your own, exported on this computer by
 * make viewer into public/local-scan/<home>/, which git ignores.
 */
export const PUBLIC_SCANS = new Set(["flat"]);

/** Old names that now show the published real scan. */
export const SCAN_ALIASES: Record<string, string> = { "demo-flat": "flat" };

export function scanFolder(homeId: string) {
  const id = encodeURIComponent(homeId);
  return PUBLIC_SCANS.has(homeId) ? `/real-scan/${id}` : `/local-scan/${id}`;
}
