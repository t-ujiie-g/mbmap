// Strict parsing of <mb-map> attributes: invalid values give null (AGENTS.md
// §8.3). Import-free so tests run it as is.

/** Highest zoom; mirrors `MAX_ZOOM` in core/transform.mbt. */
export const MAX_ZOOM = 22;

/** Highest pitch in degrees; mirrors `MAX_PITCH` in core/transform.mbt. */
export const MAX_PITCH = 85;

/** Most tile workers; mirrors `MAX_WORKERS` in map/map.mbt (0 picks automatically). */
export const MAX_WORKERS = 4;

const DECIMAL = /^\s*-?\d+(?:\.\d+)?\s*$/;

export function checkCenter(c: { lng: number; lat: number }): { lng: number; lat: number } | null {
  return Number.isFinite(c.lng) && Number.isFinite(c.lat) && Math.abs(c.lng) <= 180 && Math.abs(c.lat) <= 90
    ? { lng: c.lng, lat: c.lat }
    : null;
}

export function parseCenter(value: string): { lng: number; lat: number } | null {
  const parts = value.split(",");
  if (parts.length !== 2 || !parts.every((p) => DECIMAL.test(p))) return null;
  return checkCenter({ lng: Number(parts[0]), lat: Number(parts[1]) });
}

export function checkZoom(z: number): number | null {
  return Number.isFinite(z) && z >= 0 && z <= MAX_ZOOM ? z : null;
}

export function parseZoom(value: string): number | null {
  return DECIMAL.test(value) ? checkZoom(Number(value)) : null;
}

export function checkBearing(b: number): number | null {
  return Number.isFinite(b) ? b : null;
}

export function parseBearing(value: string): number | null {
  return DECIMAL.test(value) ? checkBearing(Number(value)) : null;
}

export function checkPitch(p: number): number | null {
  return Number.isFinite(p) && p >= 0 && p <= MAX_PITCH ? p : null;
}

export function parsePitch(value: string): number | null {
  return DECIMAL.test(value) ? checkPitch(Number(value)) : null;
}

/** `"true"` or `"false"`, nothing else. */
export function parseBoolean(value: string): boolean | null {
  return value === "true" ? true : value === "false" ? false : null;
}

export function parseWorkerCount(value: string): number | null {
  if (!/^\d$/.test(value)) return null;
  const n = Number(value);
  return n <= MAX_WORKERS ? n : null;
}
