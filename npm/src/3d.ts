// `mbmap/3d`: glTF models read in a worker of their own (meshopt decoding in its wasm), placed on the
// map at GeoJSON points or streamed as 3D Tiles by custom layers, on Web Mercator and on the globe.
import type { CustomLayerInterface, CustomRenderMethodInput } from "./custom";
import type { Material, Primitive } from "./model/gltf";
import { ModelProgram, releaseModel, uploadModel, type GpuModel } from "./model/draw";
import { Y_UP, triple, mercatorFrame, mul, placement, points, sphereFrame, value, type Value } from "./model/place";
import type { Tile } from "./tiles/tileset";
import type { TilesEngine, TilesParts } from "./3d-tiles";
import { wasmUrl } from "./urls";
import { WorkerClient } from "./worker-client";

/** Where the 3D worker (`workerUrl`) and its wasm (`wasmUrl`) are served; by default next to this module. */
export interface ModelOptions {
  workerUrl?: string | URL;
  wasmUrl?: string | URL;
}

/** A glTF model as read: its primitives, materials and decoded images. */
export interface LoadedModel {
  primitives: Primitive[];
  materials: Material[];
  images: ImageBitmap[];
}

export type { Value } from "./model/place";

/** Three numbers, the whole or each one a constant or `["get", key]`. */
export type Triple = Value<[Value<number>, Value<number>, Value<number>]>;

/**
 * A model layer: `model` (a URL of a .glb or .gltf, or a model `loadModel` gave) at each point of
 * `data` (a GeoJSON Point, Feature or FeatureCollection; a third coordinate is the height in meters).
 * `scale` [x, y, z], `rotation` [x, y, z] in degrees about the east, north and up axes (z turns the
 * model clockwise seen from above) and `translation` [east, north, up] in meters, as Mapbox's
 * `model-scale`, `model-rotation` and `model-translation`; `opacity` 0 to 1. Each may read the feature's
 * properties with `["get", key]`, as a whole or per number.
 */
export interface ModelLayerOptions extends ModelOptions {
  id: string;
  model: string | LoadedModel;
  data: unknown;
  scale?: Triple;
  rotation?: Triple;
  translation?: Triple;
  opacity?: Value<number>;
}

const client = new WorkerClient("3d");

function start(options: ModelOptions): void {
  client.start(options.workerUrl ?? new URL("./3d-worker.js", import.meta.url), (page) => ({
    wasm: wasmUrl(options.wasmUrl ?? new URL("./3d.wasm", import.meta.url), page),
  }));
}

/** Reads the glTF model at `url` (.glb, or .gltf with its buffers and images beside it). */
export async function loadModel(url: string | URL, options: ModelOptions = {}): Promise<LoadedModel> {
  start(options);
  return client.call<LoadedModel>("load", { url: new URL(url, document.baseURI).href });
}

/** Stops the 3D worker; pending loads reject. */
export function terminate(): void {
  client.terminate();
}

/** A point the model stands at, with its own transform. */
interface Instance {
  lng: number;
  lat: number;
  height: number;
  transform: Float64Array;
  opacity: number;
}

/** A custom layer drawing a glTF model at each point of its data (`modelLayer`). */
export class ModelLayer implements CustomLayerInterface {
  readonly id: string;
  readonly type = "custom" as const;
  readonly renderingMode = "3d" as const;
  /** Settles once the model is loaded (or rejects with why it was not). */
  readonly ready: Promise<void>;
  #options: ModelLayerOptions;
  #model: LoadedModel | null = null;
  #instances: Instance[] = [];
  #map: { triggerRepaint?: () => void } | null = null;
  #gl: WebGL2RenderingContext | null = null;
  #program: ModelProgram | null = null;
  #gpu: GpuModel | null = null;

  constructor(options: ModelLayerOptions) {
    this.id = options.id;
    this.#options = options;
    this.setData(options.data);
    const model = typeof options.model === "string" ? loadModel(options.model, options) : Promise.resolve(options.model);
    this.ready = model.then((m) => {
      this.#model = m;
      if (this.#gl) this.#upload(this.#gl);
      this.#map?.triggerRepaint?.();
    });
  }

  /** Places the model at the points of `data` from now on. */
  setData(data: unknown): void {
    const o = this.#options;
    this.#instances = points(data).map(({ coords, props }) => {
      const scale = triple(o.scale, props, [1, 1, 1]);
      const rotation = triple(o.rotation, props, [0, 0, 0]);
      const translation = triple(o.translation, props, [0, 0, 0]);
      const opacity = Number(value(o.opacity, props, 1));
      return {
        lng: coords[0],
        lat: Math.max(-85.051129, Math.min(85.051129, coords[1])),
        height: Number.isFinite(coords[2]) ? coords[2] : 0,
        transform: placement(scale, rotation, translation),
        opacity: Number.isFinite(opacity) ? Math.max(0, Math.min(1, opacity)) : 1,
      };
    });
    this.#map?.triggerRepaint?.();
  }

  onAdd(map: unknown, gl: WebGL2RenderingContext): void {
    this.#map = map as { triggerRepaint?: () => void };
    this.#gl = gl;
    this.#program = new ModelProgram(gl);
    if (this.#model) this.#upload(gl);
  }

  onRemove(_map: unknown, gl: WebGL2RenderingContext): void {
    if (this.#gpu) releaseModel(gl, this.#gpu);
    this.#program?.delete(gl);
    this.#gpu = null;
    this.#program = null;
    this.#map = null;
    this.#gl = null;
  }

  #upload(gl: WebGL2RenderingContext): void {
    if (this.#gpu) releaseModel(gl, this.#gpu);
    this.#gpu = uploadModel(gl, this.#model!, Y_UP);
  }

  render(gl: WebGL2RenderingContext, options: CustomRenderMethodInput): void {
    const program = this.#program;
    const gpu = this.#gpu;
    if (!program || !gpu || !this.#instances.length) return;
    const d = options.defaultProjectionData;
    const t = d.projectionTransition;
    // On the globe `mainMatrix` is Float32 and the full-precision globe matrix is the model-view-projection.
    const flat = t > 0 ? d.fallbackMatrix : d.mainMatrix;
    const plane = d.clippingPlane;
    program.begin(gl, t);
    for (const pass of [0, 1]) {
      gl.depthMask(pass === 0);
      for (const inst of this.#instances) {
        const frame = sphereFrame(inst.lng, inst.lat, inst.height);
        if (t > 0 && frame[12] * plane[0] + frame[13] * plane[1] + frame[14] * plane[2] + plane[3] < 0) continue;
        const flatMatrix = mul(flat, mercatorFrame(inst.lng, inst.lat, inst.height));
        const globe = t > 0 ? mul(options.modelViewProjectionMatrix, frame) : null;
        program.draw(gl, gpu, inst.transform, flatMatrix, globe, inst.opacity, inst.opacity < 1, pass);
      }
    }
    gl.depthMask(true);
  }
}

/** A custom layer for `map.addLayer` drawing a glTF model at each point of `options.data`. */
export function modelLayer(options: ModelLayerOptions): ModelLayer {
  return new ModelLayer(options);
}

/**
 * A point cloud layer: the uncompressed LAS (1.0 to 1.4) at `url`, its coordinates in the file's CRS
 * or `crs` (an EPSG code or PROJ string, which wins), thinned to at most `maxPoints` (default 2 000 000),
 * drawn `pointSize` CSS pixels across (default 2) colored by `color`: `"rgb"` (the file's colors, the
 * default when it has them), `"height"`, `"intensity"` or `"classification"` (ASPRS classes).
 */
export interface PointCloudLayerOptions extends ModelOptions {
  id: string;
  url: string | URL;
  crs?: number | string;
  maxPoints?: number;
  pointSize?: number;
  color?: "rgb" | "height" | "intensity" | "classification";
}

/** A LAS point cloud as the 3D worker gives it: meters east, north, up of `center` ([lng, lat, h]). */
interface LoadedCloud {
  center: [number, number, number];
  positions: Float32Array;
  colors: Uint8Array | null;
  intensity: Uint16Array;
  classification: Uint8Array;
  count: number;
  kept: number;
  bounds: [number, number, number, number, number, number];
}

/** ASPRS classes 0 to 18 (LAS 1.4 R15 table 17) as RGB: unclassified gray, ground brown, vegetation greens, buildings orange, water blue. */
const CLASS_COLORS = [
  [150, 150, 150], [170, 170, 170], [150, 110, 70], [140, 200, 110], [70, 160, 70], [30, 110, 40], [230, 130, 60], [230, 60, 200], [160, 160, 160],
  [70, 130, 220], [200, 180, 60], [90, 90, 90], [200, 200, 200], [240, 220, 40], [240, 220, 40], [180, 60, 60], [240, 220, 40], [120, 100, 160], [230, 60, 200],
];
/** Low to high, as viridis' ends and middle. */
const RAMP = [[68, 1, 84], [59, 82, 139], [33, 145, 140], [94, 201, 98], [253, 231, 37]];

/** The RGB of each point for `mode`. */
function cloudColors(c: LoadedCloud, mode: PointCloudLayerOptions["color"]): Uint8Array {
  if ((mode ?? "rgb") === "rgb" && c.colors) return c.colors;
  const n = c.kept;
  const out = new Uint8Array(3 * n);
  if (mode === "classification") {
    for (let i = 0; i < n; i++) out.set(CLASS_COLORS[c.classification[i]] ?? CLASS_COLORS[1], 3 * i);
    return out;
  }
  const value = mode === "intensity" ? (i: number) => c.intensity[i] : (i: number) => c.positions[3 * i + 2];
  let lo = Infinity;
  let hi = -Infinity;
  for (let i = 0; i < n; i++) {
    lo = Math.min(lo, value(i));
    hi = Math.max(hi, value(i));
  }
  for (let i = 0; i < n; i++) {
    const t = hi > lo ? ((value(i) - lo) / (hi - lo)) * (RAMP.length - 1) : 0;
    const k = Math.min(Math.floor(t), RAMP.length - 2);
    const f = t - k;
    for (let j = 0; j < 3; j++) out[3 * i + j] = Math.round(RAMP[k][j] + (RAMP[k + 1][j] - RAMP[k][j]) * f);
  }
  return out;
}

const IDENTITY = new Float64Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

/** A custom layer drawing a LAS point cloud (`pointCloudLayer`). */
export class PointCloudLayer implements CustomLayerInterface {
  readonly id: string;
  readonly type = "custom" as const;
  readonly renderingMode = "3d" as const;
  /** Settles once the cloud is read (or rejects with why it was not). */
  readonly ready: Promise<void>;
  #options: PointCloudLayerOptions;
  #cloud: LoadedCloud | null = null;
  #map: { triggerRepaint?: () => void } | null = null;
  #gl: WebGL2RenderingContext | null = null;
  #program: ModelProgram | null = null;
  #gpu: GpuModel | null = null;

  constructor(options: PointCloudLayerOptions) {
    this.id = options.id;
    this.#options = options;
    start(options);
    const url = new URL(options.url, document.baseURI).href;
    this.ready = client.call<LoadedCloud>("las", { url, maxPoints: options.maxPoints ?? 2_000_000, crs: options.crs }).then((c) => {
      this.#cloud = c;
      if (this.#gl) this.#upload(this.#gl);
      this.#map?.triggerRepaint?.();
    });
  }

  /** [west, south, east, north] of the points read, once `ready`. */
  get bounds(): [number, number, number, number] | null {
    const b = this.#cloud?.bounds;
    return b ? [b[0], b[1], b[3], b[4]] : null;
  }

  /** The points in the file and those drawn (after thinning to `maxPoints`), once `ready`. */
  get counts(): { file: number; drawn: number } | null {
    return this.#cloud ? { file: this.#cloud.count, drawn: this.#cloud.kept } : null;
  }

  /** Colors the points by `mode` from now on. */
  setColor(mode: NonNullable<PointCloudLayerOptions["color"]>): void {
    this.#options = { ...this.#options, color: mode };
    if (this.#gl && this.#cloud) this.#upload(this.#gl);
    this.#map?.triggerRepaint?.();
  }

  onAdd(map: unknown, gl: WebGL2RenderingContext): void {
    this.#map = map as { triggerRepaint?: () => void };
    this.#gl = gl;
    this.#program = new ModelProgram(gl);
    if (this.#cloud) this.#upload(gl);
  }

  onRemove(_map: unknown, gl: WebGL2RenderingContext): void {
    if (this.#gpu) releaseModel(gl, this.#gpu);
    this.#program?.delete(gl);
    this.#gpu = null;
    this.#program = null;
    this.#map = null;
    this.#gl = null;
  }

  #upload(gl: WebGL2RenderingContext): void {
    const c = this.#cloud!;
    if (this.#gpu) releaseModel(gl, this.#gpu);
    const color = { data: cloudColors(c, this.#options.color), size: 3, type: gl.UNSIGNED_BYTE, normalized: true };
    const position = { data: c.positions, size: 3, type: gl.FLOAT, normalized: false };
    const material = { color: [1, 1, 1, 1] as [number, number, number, number], alphaMode: "OPAQUE" as const, alphaCutoff: 0.5, doubleSided: true, unlit: true };
    const primitive = { attributes: { POSITION: position, COLOR_0: color }, mode: gl.POINTS, material: 0, matrix: IDENTITY };
    this.#gpu = uploadModel(gl, { primitives: [primitive], materials: [material], images: [] }, IDENTITY);
  }

  render(gl: WebGL2RenderingContext, options: CustomRenderMethodInput): void {
    const program = this.#program;
    const gpu = this.#gpu;
    const c = this.#cloud;
    if (!program || !gpu || !c) return;
    const d = options.defaultProjectionData;
    const t = d.projectionTransition;
    const [lng, lat, h] = c.center;
    const css = (gl.canvas as HTMLCanvasElement).clientWidth || gl.drawingBufferWidth;
    program.begin(gl, t);
    program.setPointSize((this.#options.pointSize ?? 2) * (gl.drawingBufferWidth / css));
    const flat = mul(t > 0 ? d.fallbackMatrix : d.mainMatrix, mercatorFrame(lng, lat, h));
    const globe = t > 0 ? mul(options.modelViewProjectionMatrix, sphereFrame(lng, lat, h)) : null;
    program.draw(gl, gpu, IDENTITY, flat, globe, 1, false, 0);
  }
}

/** A custom layer for `map.addLayer` drawing the LAS point cloud at `options.url`. */
export function pointCloudLayer(options: PointCloudLayerOptions): PointCloudLayer {
  return new PointCloudLayer(options);
}

/**
 * A 3D Tiles layer: the tileset at `url` (3D Tiles 1.0 or 1.1: b3dm, i3dm, pnts, cmpt and glTF contents,
 * external tilesets, implicit tiling), refined while a tile's screen-space error exceeds
 * `maximumScreenSpaceError` (default 8, as loaders.gl), `height` meters added to every tile (to set
 * ellipsoidal heights on the map's ground), at most `maximumLoadedTiles` contents kept (default 256),
 * points drawn `pointSize` CSS pixels across (default 2).
 */
export interface TilesLayerOptions extends ModelOptions {
  id: string;
  url: string | URL;
  maximumScreenSpaceError?: number;
  height?: number;
  maximumLoadedTiles?: number;
  pointSize?: number;
}

/** A feature of a 3D tile: its tile's `path`, its `id` in the tile and its `properties`. */
export interface TileFeature {
  tile: string;
  id: number;
  properties: Record<string, unknown>;
}

/** A custom layer streaming a 3D Tiles tileset (`tilesLayer`); its work is in `3d-tiles.js`, loaded with the first. */
export class TilesLayer implements CustomLayerInterface {
  readonly id: string;
  readonly type = "custom" as const;
  readonly renderingMode = "3d" as const;
  /** Settles once the tileset's JSON is read (or rejects with why it was not). */
  readonly ready: Promise<void>;
  #engine: TilesEngine | null = null;
  #map: { triggerRepaint?: () => void } | null = null;
  #gl: WebGL2RenderingContext | null = null;
  #program: ModelProgram | null = null;

  constructor(options: TilesLayerOptions) {
    this.id = options.id;
    const url = new URL(options.url, document.baseURI).href;
    const parts: TilesParts = {
      loadTile: (tileUrl) => {
        start(options);
        return client.call("tile", { url: tileUrl });
      },
      upload: uploadModel,
      release: releaseModel,
      repaint: () => this.#map?.triggerRepaint?.(),
    };
    this.ready = import("./3d-tiles.js")
      .then((m) => m.openTileset(url, options, parts))
      .then((engine) => {
        this.#engine = engine;
        this.#map?.triggerRepaint?.();
      });
  }

  /** The tiles drawn in the last frame. */
  get selected(): Tile[] {
    return this.#engine?.selected ?? [];
  }

  /** Whether the last frame asked for no content and none is loading. */
  get idle(): boolean {
    return this.#engine?.idle ?? false;
  }

  /**
   * The feature drawn at CSS pixel `point` of the map's canvas, after the next frame: its tile's `path`,
   * its `id` (b3dm batch id or EXT_mesh_features feature id) and `properties`, or null.
   */
  async queryFeature(point: { x: number; y: number }): Promise<TileFeature | null> {
    const hit = (await this.#engine?.pick(point.x, point.y)) ?? null;
    if (!hit) return null;
    const properties = hit.part.properties(hit.feature);
    return { tile: hit.tile.path, id: hit.feature, properties };
  }

  onAdd(map: unknown, gl: WebGL2RenderingContext): void {
    this.#map = map as { triggerRepaint?: () => void };
    this.#gl = gl;
    this.#program = new ModelProgram(gl);
  }

  onRemove(_map: unknown, gl: WebGL2RenderingContext): void {
    this.#engine?.release(gl);
    this.#program?.delete(gl);
    this.#program = null;
    this.#map = null;
    this.#gl = null;
  }

  render(gl: WebGL2RenderingContext, options: CustomRenderMethodInput): void {
    if (this.#program && this.#engine) this.#engine.render(gl, options, this.#program);
  }
}

/** A custom layer for `map.addLayer` streaming the 3D Tiles tileset at `options.url`. */
export function tilesLayer(options: TilesLayerOptions): TilesLayer {
  return new TilesLayer(options);
}

