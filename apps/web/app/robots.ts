import type { MetadataRoute } from "next";

/** Crawlers may read the site and the published real scan, never someone's local scan pages or the API routes. */
export default function robots(): MetadataRoute.Robots {
  return {
    rules: [{ userAgent: "*", allow: ["/", "/homes/flat/"], disallow: ["/homes/", "/api/"] }],
  };
}
