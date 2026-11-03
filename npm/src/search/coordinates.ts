// The coordinates provider: places written as text, the projected ones taken
// to degrees through a `transform` the page passes (mbmap/analysis's).
import { parseLngLat, parsePlaneRectangular, parseUtm } from "./parse";
import type { LngLat, SearchProvider, SearchResult, Transform } from "./types";

const degrees = (p: LngLat) => `${p.lat.toFixed(6)}, ${p.lng.toFixed(6)}`;

/**
 * Coordinates typed into the box: latitude and longitude (decimal, or degrees-minutes-seconds), and
 * with `transform`, Japan's plane rectangular systems and UTM. `reverse` writes a place's degrees.
 */
export function coordinates(options: { transform?: Transform; name?: string } = {}): SearchProvider {
  const name = options.name ?? "coordinates";
  return {
    name,
    async search(query) {
      const out: SearchResult[] = parseLngLat(query).map((p) => ({ provider: name, label: degrees(p), lngLat: p }));
      const projected = parsePlaneRectangular(query) ?? parseUtm(query);
      if (projected && options.transform) {
        const ll = await options.transform([projected.x, projected.y], projected.epsg, 4326);
        const p = { lng: ll[0], lat: ll[1] };
        if (Number.isFinite(p.lng) && Number.isFinite(p.lat)) out.push({ provider: name, label: degrees(p), detail: projected.title, lngLat: p });
      }
      return out;
    },
    reverse(p) {
      return [{ provider: name, label: degrees(p), lngLat: p }];
    },
  };
}
