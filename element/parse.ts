// Strict parsing of <mb-map> attribute values (AGENTS.md §8.3: reject, never
// coerce). Free of imports so tests can run it as is.

/** Highest zoom; mirrors the default `max_zoom` of `Transform` in core/transform.mbt. */
export const MAX_ZOOM = 22;

/** Highest pitch in degrees; mirrors `MAX_PITCH` in core/transform.mbt. */
export const MAX_PITCH = 60;

/** Most tile workers; mirrors `MAX_WORKERS` in map/map.mbt (0 picks automatically). */
export const MAX_WORKERS = 4;

const DECIMAL = /^\s*-?\d+(?:\.\d+)?\s*$/;

/** A center within longitude ±180 and latitude ±90, or null. */
export function checkCenter(c: { lng: number; lat: number }): { lng: number; lat: number } | null {
  return Number.isFinite(c.lng) && Number.isFinite(c.lat) && Math.abs(c.lng) <= 180 && Math.abs(c.lat) <= 90
    ? { lng: c.lng, lat: c.lat }
    : null;
}

/** `lng,lat` as two decimal numbers within range, or null. */
export function parseCenter(value: string): { lng: number; lat: number } | null {
  const parts = value.split(",");
  if (parts.length !== 2 || !parts.every((p) => DECIMAL.test(p))) return null;
  return checkCenter({ lng: Number(parts[0]), lat: Number(parts[1]) });
}

/** A zoom from 0 to `MAX_ZOOM`, or null. */
export function checkZoom(z: number): number | null {
  return Number.isFinite(z) && z >= 0 && z <= MAX_ZOOM ? z : null;
}

/** A decimal zoom from 0 to `MAX_ZOOM`, or null. */
export function parseZoom(value: string): number | null {
  return DECIMAL.test(value) ? checkZoom(Number(value)) : null;
}

/** A finite bearing in degrees (any value; the map wraps it), or null. */
export function checkBearing(b: number): number | null {
  return Number.isFinite(b) ? b : null;
}

/** A decimal bearing, or null. */
export function parseBearing(value: string): number | null {
  return DECIMAL.test(value) ? checkBearing(Number(value)) : null;
}

/** A pitch from 0 to `MAX_PITCH`, or null. */
export function checkPitch(p: number): number | null {
  return Number.isFinite(p) && p >= 0 && p <= MAX_PITCH ? p : null;
}

/** A decimal pitch from 0 to `MAX_PITCH`, or null. */
export function parsePitch(value: string): number | null {
  return DECIMAL.test(value) ? checkPitch(Number(value)) : null;
}

/** A worker count from 0 to `MAX_WORKERS`, or null. */
export function parseWorkerCount(value: string): number | null {
  if (!/^\d$/.test(value)) return null;
  const n = Number(value);
  return n <= MAX_WORKERS ? n : null;
}
