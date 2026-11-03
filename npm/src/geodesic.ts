// `mbmap/geodesic`: distances, azimuths and areas on the WGS 84 ellipsoid, in a
// worker of its own started on the first call. A port of GeographicLib's
// geodesic routines whose results equal geographiclib-geodesic 2.2.0's.
import { wasmUrl } from "./urls";
import { WorkerClient } from "./worker-client";

/** `[longitude, latitude]` in degrees. */
export type Position = [number, number];

/** Where the geodesic worker (`workerUrl`) and its wasm (`wasmUrl`) are served; by default next to this module. */
export interface GeodesicOptions {
  workerUrl?: string | URL;
  wasmUrl?: string | URL;
}

/**
 * Between two points: `distance` in meters, `azimuth1` and `azimuth2` (degrees clockwise from north)
 * at each end in the direction of travel, `arc` on the auxiliary sphere in degrees, `area` in square
 * meters between the geodesic and the equator (GeographicLib's S12).
 */
export interface Inverse {
  distance: number;
  azimuth1: number;
  azimuth2: number;
  arc: number;
  area: number;
}

/** `position` reached, the `azimuth` there (degrees) and the `arc` in degrees. */
export interface Direct {
  position: Position;
  azimuth: number;
  arc: number;
}

/**
 * `closed`: measure the ring the positions close (default false, a line); `step`: also return the
 * path with points at most `step` meters apart along its geodesics (closed back to the start for a
 * ring), for drawing it on a Web Mercator map.
 */
export interface MeasureOptions extends GeodesicOptions {
  closed?: boolean;
  step?: number;
}

/**
 * `length` in meters (a ring's perimeter); `area` in square meters (counter-clockwise rings positive,
 * NaN for a line, 0 below three positions); `distances` along the path to each position; `path` with
 * longitudes running on across ±180, when a `step` was given.
 */
export interface Measurement {
  length: number;
  area: number;
  distances: Float64Array;
  path?: Position[];
}

const client = new WorkerClient("geodesic");

function start(options: GeodesicOptions): void {
  client.start(options.workerUrl ?? new URL("./geodesic-worker.js", import.meta.url), (page) => ({
    wasm: wasmUrl(options.wasmUrl ?? new URL("./geodesic.wasm", import.meta.url), page),
  }));
}

/** The geodesic from `from` to `to` (the inverse problem). */
export async function inverse(from: Position, to: Position, options: GeodesicOptions = {}): Promise<Inverse> {
  start(options);
  const [distance, azimuth1, azimuth2, arc, area] = await client.call<Float64Array>("inverse", { from: [...from], to: [...to] });
  return { distance, azimuth1, azimuth2, arc, area };
}

/** Where `distance` meters from `from` at `azimuth` (degrees clockwise from north) leads (the direct problem). */
export async function direct(from: Position, azimuth: number, distance: number, options: GeodesicOptions = {}): Promise<Direct> {
  start(options);
  const [lat, lng, az, arc] = await client.call<Float64Array>("direct", { from: [...from], azimuth, distance });
  return { position: [lng, lat], azimuth: az, arc };
}

/** Measures the line through `positions`, or the ring they close (`closed`), along geodesics. */
export async function measure(positions: ArrayLike<Position>, options: MeasureOptions = {}): Promise<Measurement> {
  start(options);
  const coords = new Float64Array(positions.length * 2);
  for (let i = 0; i < positions.length; i++) coords.set(positions[i], i * 2);
  const { closed = false, step } = options;
  const r = await client.call<{ measured: Float64Array; path?: Float64Array }>("measure", { coords: coords.buffer, closed, step }, [coords.buffer]);
  const m: Measurement = { length: r.measured[0], area: r.measured[1], distances: r.measured.subarray(2) };
  if (r.path) {
    const path: Position[] = [];
    for (let i = 0; i < r.path.length; i += 2) path.push([r.path[i], r.path[i + 1]]);
    m.path = path;
  }
  return m;
}

/** Stops the geodesic worker; pending calls reject. */
export function terminate(): void {
  client.terminate();
}
