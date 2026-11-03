// Distances on the map as MapLibre GL JS 6.16.0 measures them (`LngLat.distanceTo`,
// ScaleControl's `getRoundNum`; BSD-3-Clause, Copyright (c) 2020 MapLibre
// contributors; see NOTICE). Import-free, so that `npm test` can load it.

/** MapLibre's mean Earth radius, which `LngLat.distanceTo` measures with. */
const EARTH_RADIUS = 6371008.8;

/** Great-circle distance in meters, as MapLibre's `LngLat.distanceTo`. */
export function distanceTo(a: { lng: number; lat: number }, b: { lng: number; lat: number }): number {
  const rad = Math.PI / 180;
  const lat1 = a.lat * rad;
  const lat2 = b.lat * rad;
  const c = Math.sin(lat1) * Math.sin(lat2) + Math.cos(lat1) * Math.cos(lat2) * Math.cos((b.lng - a.lng) * rad);
  return EARTH_RADIUS * Math.acos(Math.min(c, 1));
}

function decimalRound(d: number): number {
  const multiplier = Math.pow(10, Math.ceil(-Math.log(d) / Math.LN10));
  return Math.round(d * multiplier) / multiplier;
}

/** MapLibre's `getRoundNum`: 1, 2, 3 or 5 times a power of ten, at most `num`. */
export function roundNumber(num: number): number {
  const pow10 = Math.pow(10, `${Math.floor(num)}`.length - 1);
  let d = num / pow10;
  d = d >= 10 ? 10 : d >= 5 ? 5 : d >= 3 ? 3 : d >= 2 ? 2 : d >= 1 ? 1 : decimalRound(d);
  return pow10 * d;
}

/** The box `radius` meters around `center` (MapLibre's `LngLatBounds.fromLngLat`), as west, south, east, north. */
export function boundsAround(center: { lng: number; lat: number }, radius: number): [number, number, number, number] {
  const lat = (360 * radius) / 40075017;
  const lng = lat / Math.cos((Math.PI / 180) * center.lat);
  return [center.lng - lng, center.lat - lat, center.lng + lng, center.lat + lat];
}
