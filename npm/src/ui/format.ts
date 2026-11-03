// Coordinates as text: decimal degrees, degrees-minutes-seconds, and the UTM
// zone of a place. Import-free, so that `npm test` can load it.

/** `value` in degrees, minutes and seconds (`digits` decimals of seconds), with its hemisphere letter. */
export function dms(value: number, positive: string, negative: string, digits = 1): string {
  const scale = 10 ** digits;
  // Round the seconds first so that 59.96″ carries into the minutes.
  let total = Math.round(Math.abs(value) * 3600 * scale);
  const d = Math.floor(total / (3600 * scale));
  total -= d * 3600 * scale;
  const m = Math.floor(total / (60 * scale));
  const s = (total - m * 60 * scale) / scale;
  return `${d}°${String(m).padStart(2, "0")}′${s.toFixed(digits).padStart(digits > 0 ? 3 + digits : 2, "0")}″${value < 0 ? negative : positive}`;
}

/** Latitude and longitude in degrees, minutes and seconds. */
export function formatDms(p: { lng: number; lat: number }, digits = 1): string {
  return `${dms(p.lat, "N", "S", digits)} ${dms(p.lng, "E", "W", digits)}`;
}

/** Latitude and longitude in decimal degrees. */
export function formatDegrees(p: { lng: number; lat: number }, digits = 5): string {
  return `${p.lat.toFixed(digits)}, ${p.lng.toFixed(digits)}`;
}

/** The WGS 84 UTM zone of a place (1-60; no Norway or Svalbard exceptions) and its EPSG code. */
export function utmZone(p: { lng: number; lat: number }): { zone: number; north: boolean; epsg: number } {
  const lng = ((((p.lng + 180) % 360) + 360) % 360) - 180;
  const zone = Math.min(60, Math.floor((lng + 180) / 6) + 1);
  const north = p.lat >= 0;
  return { zone, north, epsg: (north ? 32600 : 32700) + zone };
}

/** A length: meters (one decimal below 100 m) below 1 km, then kilometers. */
export function formatLength(meters: number): string {
  if (meters < 1000) return `${meters < 100 ? meters.toFixed(1) : Math.round(meters)} m`;
  return `${(meters / 1000).toFixed(meters < 10_000 ? 3 : meters < 100_000 ? 2 : 1)} km`;
}

/** An area: square meters below 1 ha, hectares below 1 km², then square kilometers. */
export function formatArea(squareMeters: number): string {
  if (squareMeters < 10_000) return `${squareMeters.toFixed(squareMeters < 100 ? 1 : 0)} m²`;
  if (squareMeters < 1_000_000) return `${(squareMeters / 10_000).toFixed(2)} ha`;
  return `${(squareMeters / 1_000_000).toFixed(squareMeters < 100_000_000 ? 3 : 2)} km²`;
}
