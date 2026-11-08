// `mbmap/3d`: glTF models read in a worker of their own (meshopt decoding in its wasm), placed on the
// map at GeoJSON points or streamed as 3D Tiles by custom layers, on Web Mercator and on the globe.
import type { CustomLayerInterface, CustomRenderMethodInput } from "./custom";
import type { Material, Primitive } from "./model/gltf";
import { ModelProgram, releaseModel, uploadModel, type GpuModel } from "./model/draw";
import { Y_UP, triple, mercatorFrame, mul, placement, points, sphereFrame, value, type Value } from "./model/place";
import { eastNorthUp, multiply, toCartographic } from "./tiles/geo";
import { frameState } from "./tiles/frame";
import { expandTileset } from "./tiles/implicit";
import { buildTree, Traversal, type Tile } from "./tiles/tileset";
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
 * A 3D Tiles layer: the tileset at `url` (3D Tiles 1.0 or 1.1: b3dm and glTF contents, external
 * tilesets, implicit tiling), refined while a tile's screen-space error exceeds
 * `maximumScreenSpaceError` (default 8, as loaders.gl), `height` meters added to every tile (to set
 * ellipsoidal heights on the map's ground), at most `maximumLoadedTiles` contents kept (default 256).
 */
export interface TilesLayerOptions extends ModelOptions {
  id: string;
  url: string | URL;
  maximumScreenSpaceError?: number;
  height?: number;
  maximumLoadedTiles?: number;
}

/** Contents loading at once. */
const MAX_LOADS = 6;

const IDENTITY = new Float64Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

/** A loaded tile's model on the GPU and where its meters (east, north, up) stand. */
interface TileModel {
  gpu: GpuModel;
  lng: number;
  lat: number;
  height: number;
}

const fetchBytes = async (url: string): Promise<Uint8Array> => {
  const u = new URL(url);
  if (!/^(https?|blob|data):$/.test(u.protocol)) throw new Error(`cannot load ${u.protocol} URLs`);
  const res = await fetch(u, { credentials: "omit" });
  if (!res.ok) throw new Error(`${u.href}: HTTP ${res.status}`);
  return new Uint8Array(await res.arrayBuffer());
};

/** The rigid transform's inverse (rotation transposed), column-major. */
function rigidInverse(m: ArrayLike<number>): Float64Array {
  const r = [m[0], m[4], m[8], 0, m[1], m[5], m[9], 0, m[2], m[6], m[10], 0];
  const t = [m[12], m[13], m[14]];
  return new Float64Array([...r, -(r[0] * t[0] + r[4] * t[1] + r[8] * t[2]), -(r[1] * t[0] + r[5] * t[1] + r[9] * t[2]), -(r[2] * t[0] + r[6] * t[1] + r[10] * t[2]), 1]);
}

/** A custom layer streaming a 3D Tiles tileset (`tilesLayer`). */
export class TilesLayer implements CustomLayerInterface {
  readonly id: string;
  readonly type = "custom" as const;
  readonly renderingMode = "3d" as const;
  /** Settles once the tileset's JSON is read (or rejects with why it was not). */
  readonly ready: Promise<void>;
  #options: TilesLayerOptions;
  #root: Tile | null = null;
  #traversal: Traversal;
  #loading = 0;
  #loaded = new Set<Tile>();
  #map: { triggerRepaint?: () => void } | null = null;
  #gl: WebGL2RenderingContext | null = null;
  #program: ModelProgram | null = null;
  #generation = 0;

  constructor(options: TilesLayerOptions) {
    this.id = options.id;
    this.#options = options;
    this.#traversal = new Traversal(options.maximumScreenSpaceError ?? 8);
    const url = new URL(options.url, document.baseURI).href;
    this.ready = fetchBytes(url)
      .then(async (bytes) => expandTileset(JSON.parse(new TextDecoder().decode(bytes)), url, fetchBytes))
      .then((json) => {
        this.#root = buildTree(json, url);
        this.#map?.triggerRepaint?.();
      });
  }

  /** The tiles drawn in the last frame. */
  get selected(): Tile[] {
    return [...this.#traversal.selected.values()];
  }

  onAdd(map: unknown, gl: WebGL2RenderingContext): void {
    this.#map = map as { triggerRepaint?: () => void };
    this.#gl = gl;
    this.#program = new ModelProgram(gl);
  }

  onRemove(_map: unknown, gl: WebGL2RenderingContext): void {
    for (const tile of this.#loaded) this.#unload(tile, gl);
    this.#program?.delete(gl);
    this.#program = null;
    this.#map = null;
    this.#gl = null;
    this.#generation++;
  }

  render(gl: WebGL2RenderingContext, options: CustomRenderMethodInput): void {
    const program = this.#program;
    const root = this.#root;
    if (!program || !root) return;
    const d = options.defaultProjectionData;
    const t = d.projectionTransition;
    const flat = t > 0 ? d.fallbackMatrix : d.mainMatrix;
    const canvas = gl.canvas as HTMLCanvasElement;
    const height = canvas.clientHeight || gl.drawingBufferHeight;
    const frame = t > 0.5 ? frameState(options.modelViewProjectionMatrix, height, true) : frameState(flat, height);
    if (!frame) return;
    this.#traversal.traverse(root, frame);
    const wanted = [...this.#traversal.requested.values()].sort((a, b) => a.distance - b.distance);
    for (const tile of wanted) {
      if (this.#loading >= MAX_LOADS) break;
      this.#load(tile);
    }
    const plane = d.clippingPlane;
    const offset = this.#options.height ?? 0;
    program.begin(gl, t);
    for (const pass of [0, 1]) {
      gl.depthMask(pass === 0);
      for (const tile of this.#traversal.selected.values()) {
        const m = tile.content as TileModel | null;
        if (!m) continue;
        const sphere = sphereFrame(m.lng, m.lat, m.height + offset);
        if (t > 0 && sphere[12] * plane[0] + sphere[13] * plane[1] + sphere[14] * plane[2] + plane[3] < 0) continue;
        const flatMatrix = mul(flat, mercatorFrame(m.lng, m.lat, m.height + offset));
        const globe = t > 0 ? mul(options.modelViewProjectionMatrix, sphere) : null;
        program.draw(gl, m.gpu, IDENTITY, flatMatrix, globe, 1, false, pass);
      }
    }
    gl.depthMask(true);
    this.#evict(gl);
  }

  #load(tile: Tile): void {
    const url = tile.contentUrl!;
    const generation = this.#generation;
    tile.state = "loading";
    this.#loading++;
    const done = () => {
      this.#loading--;
      this.#map?.triggerRepaint?.();
    };
    if (/\.json([?#]|$)/i.test(url)) {
      fetchBytes(url)
        .then((bytes) => expandTileset(JSON.parse(new TextDecoder().decode(bytes)), url, fetchBytes))
        .then((json) => {
          buildTree(json, url, tile);
          tile.isTileset = true;
          tile.state = "ready";
        })
        .catch(() => (tile.state = "failed"))
        .finally(done);
      return;
    }
    start(this.#options);
    client
      .call<LoadedModel & { rtc: [number, number, number] | null }>("tile", { url })
      .then((content) => {
        const gl = this.#gl;
        if (!gl || generation !== this.#generation) {
          tile.state = "unloaded";
          return;
        }
        // Meters of the content: the tile's transform, RTC_CENTER and glTF's +Y up turned to +Z, then
        // east, north, up at the tile's center.
        let toEcef = tile.transform;
        if (content.rtc) toEcef = multiply(toEcef, [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, ...content.rtc, 1]);
        toEcef = multiply(toEcef, Y_UP);
        const center = tile.volume.center;
        const carto = toCartographic(center) ?? [0, 0, 0];
        const axis = multiply(rigidInverse(eastNorthUp(center)), toEcef);
        tile.content = { gpu: uploadModel(gl, content, axis), lng: carto[0], lat: carto[1], height: carto[2] } satisfies TileModel;
        tile.state = "ready";
        this.#loaded.add(tile);
      })
      .catch(() => (tile.state = "failed"))
      .finally(done);
  }

  #unload(tile: Tile, gl: WebGL2RenderingContext): void {
    const m = tile.content as TileModel | null;
    if (m) releaseModel(gl, m.gpu);
    tile.content = null;
    tile.state = "unloaded";
    this.#loaded.delete(tile);
  }

  /** Frees the contents used longest ago beyond `maximumLoadedTiles`, never one drawn now. */
  #evict(gl: WebGL2RenderingContext): void {
    const max = this.#options.maximumLoadedTiles ?? 256;
    if (this.#loaded.size <= max) return;
    const idle = [...this.#loaded].filter((t) => !this.#traversal.selected.has(t.path)).sort((a, b) => a.lastUsed - b.lastUsed);
    for (const tile of idle.slice(0, this.#loaded.size - max)) this.#unload(tile, gl);
  }
}

/** A custom layer for `map.addLayer` streaming the 3D Tiles tileset at `options.url`. */
export function tilesLayer(options: TilesLayerOptions): TilesLayer {
  return new TilesLayer(options);
}

