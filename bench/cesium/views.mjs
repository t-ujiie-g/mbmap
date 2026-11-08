// The cameras both pages take (MapLibre's: center, zoom of 512-px tiles, pitch, bearing), the
// viewport and the scripted orbit, shared by bench/cesium/run.mjs and its two pages.
export const WIDTH = 800;
export const HEIGHT = 600;
export const VIEWS = [
  { name: "station-z17-p50", center: [139.7671, 35.6812], zoom: 17, pitch: 50, bearing: -20 },
  { name: "station-z16-p0", center: [139.7671, 35.6812], zoom: 16, pitch: 0, bearing: 0 },
  { name: "station-z18-p60", center: [139.7671, 35.6812], zoom: 18, pitch: 60, bearing: 30 },
];
/** Frames of the orbit after settling, one degree of bearing each. */
export const ORBIT_FRAMES = 120;
/** PLATEAU's heights are above the ellipsoid; the geoid lies 36.7 m above it at Tokyo Station. */
export const HEIGHT_OFFSET = -36.7;
/** MapLibre's vertical field of view (atan(3/4), 36.87°). */
export const FOV = Math.atan(0.75);

/**
 * The distance in meters from MapLibre's camera to its center: 0.5 / tan(fov / 2) viewport heights,
 * at the meters per pixel of the center's latitude.
 */
export function cameraDistance(view, height = HEIGHT) {
  const metersPerPixel = (2 * Math.PI * 6378137 * Math.cos((view.center[1] * Math.PI) / 180)) / (512 * 2 ** view.zoom);
  return (0.5 / Math.tan(FOV / 2)) * height * metersPerPixel;
}

/** Sums the CPU time of every requestAnimationFrame callback per frame (callbacks of one frame share `t`). */
export function trackFrames() {
  const frames = new Map();
  const raf = requestAnimationFrame.bind(window);
  window.requestAnimationFrame = (f) => raf((t) => {
    const t0 = performance.now();
    f(t);
    frames.set(t, (frames.get(t) ?? 0) + performance.now() - t0);
  });
  return frames;
}

/** p50, p95 and max of `xs`. */
export function quantiles(xs) {
  const s = [...xs].sort((a, b) => a - b);
  const q = (p) => s[Math.min(s.length - 1, Math.floor(p * s.length))];
  return { frames: s.length, p50: q(0.5), p95: q(0.95), max: s[s.length - 1] };
}

/**
 * Resolves with the time the selection last changed once `state()` (a key of what is drawn, or
 * null while loading) has stayed the same for `frames` frames.
 */
export function settle(state, frames = 10) {
  return new Promise((done) => {
    let last = null;
    let since = performance.now();
    let same = 0;
    const check = () => {
      const now = state();
      if (now === null || now !== last) {
        same = 0;
        since = performance.now();
      } else same++;
      last = now;
      if (same >= frames) done(since);
      else requestAnimationFrame(check);
    };
    requestAnimationFrame(check);
  });
}
