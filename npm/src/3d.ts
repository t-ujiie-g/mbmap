// `mbmap/3d`: glTF models read in a worker of their own (meshopt decoding in its wasm), placed on the
// map at GeoJSON points or streamed as 3D Tiles by custom layers, on Web Mercator and on the globe.
import { mercatorMeters, type Clipping } from "./clipping";
import type { CustomLayerInterface, CustomRenderMethodInput } from "./custom";
import type { Material, Primitive } from "./model/gltf";
import { ModelProgram, releaseModel, uploadModel, type GpuModel } from "./model/draw";
import { Y_UP, triple, mercatorFrame, placement, points, sphereFrame, value, type Value } from "./model/place";
import type { Tile } from "./tiles/tileset";
import { IDENTITY } from "./tiles/geo";
import type { TilesEngine } from "./3d-tiles";
import type { I3sParts } from "./3d-i3s";
import { crsArg, type Crs } from "./crs";
import { cloudColors, type CloudColor } from "./model/cloud";
import { wasmUrl } from "./urls";
import { WorkerClient } from "./worker-client";

/** What the layers ask of the map they are on. */
interface MapLike {
  triggerRepaint?(): void;
  getClipping?(): Clipping | null;
  getZoom?(): number;
  getCenter?(): { lat: number };
}

/** `map`'s clipping, with the meters a CSS pixel spans per unit of clip w (1 over the center's depth in meters). */
function clipOf(map: MapLike | null, gl: WebGL2RenderingContext, input: CustomRenderMethodInput): { cut: Clipping; mpp: number } | undefined {
  const cut = map?.getClipping?.();
  if (!cut || !map?.getZoom || !map.getCenter) return undefined;
  const height = (gl.canvas as HTMLCanvasElement).clientHeight || gl.drawingBufferHeight;
  const ppm = (512 * 2 ** map.getZoom()) / mercatorMeters(map.getCenter().lat);
  return { cut, mpp: (2 * Math.tan(input.fov / 2)) / height / ppm };
}

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
    proj: wasmUrl(new URL("./proj.wasm", import.meta.url), page),
    prj: new URL("./prjwkt.js", import.meta.url).href,
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
  #map: MapLike | null = null;
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
    this.#map = map as MapLike;
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
    this.#draw(gl, options, false);
  }

  renderShadow(gl: WebGL2RenderingContext, options: CustomRenderMethodInput): void {
    this.#draw(gl, options, true);
  }

  /** Draws the instances, or only the opaque ones' depth when `casting` shadows. */
  #draw(gl: WebGL2RenderingContext, options: CustomRenderMethodInput, casting: boolean): void {
    const program = this.#program;
    const gpu = this.#gpu;
    if (!program || !gpu || !this.#instances.length) return;
    const d = options.defaultProjectionData;
    const t = d.projectionTransition;
    const plane = d.clippingPlane;
    program.begin(gl, options, false, casting, clipOf(this.#map, gl, options));
    for (const pass of casting ? [0] : [0, 1]) {
      gl.depthMask(pass === 0);
      for (const inst of this.#instances) {
        const frame = sphereFrame(inst.lng, inst.lat, inst.height);
        if (t > 0 && frame[12] * plane[0] + frame[13] * plane[1] + frame[14] * plane[2] + plane[3] < 0) continue;
        program.draw(gl, gpu, inst.transform, mercatorFrame(inst.lng, inst.lat, inst.height), frame, inst.opacity, inst.opacity < 1, pass);
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
 * (GeoTIFF keys or WKT) or `crs` (an EPSG code or PROJ string, which wins), heights as they are, thinned to at most `maxPoints` (default 2 000 000),
 * drawn `pointSize` CSS pixels across (default 2) colored by `color`: `"rgb"` (the file's colors, the
 * default when it has them), `"height"`, `"intensity"` or `"classification"` (ASPRS classes).
 */
export interface PointCloudLayerOptions extends ModelOptions {
  id: string;
  url: string | URL;
  crs?: Crs;
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


/** A custom layer drawing a LAS point cloud (`pointCloudLayer`). */
export class PointCloudLayer implements CustomLayerInterface {
  readonly id: string;
  readonly type = "custom" as const;
  readonly renderingMode = "3d" as const;
  /** Settles once the cloud is read (or rejects with why it was not). */
  readonly ready: Promise<void>;
  #options: PointCloudLayerOptions;
  #cloud: LoadedCloud | null = null;
  #map: MapLike | null = null;
  #gl: WebGL2RenderingContext | null = null;
  #program: ModelProgram | null = null;
  #gpu: GpuModel | null = null;

  constructor(options: PointCloudLayerOptions) {
    this.id = options.id;
    this.#options = options;
    start(options);
    const url = new URL(options.url, document.baseURI).href;
    const crs = options.crs === undefined ? Promise.resolve(undefined) : crsArg(options.crs, "3d");
    this.ready = crs.then((c) => client.call<LoadedCloud>("las", { url, maxPoints: options.maxPoints ?? 2_000_000, crs: c })).then((c) => {
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
    this.#map = map as MapLike;
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
    const color = { data: cloudColors({ ...c, count: c.kept }, this.#options.color), size: 3, type: gl.UNSIGNED_BYTE, normalized: true };
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
    const [lng, lat, h] = c.center;
    const css = (gl.canvas as HTMLCanvasElement).clientWidth || gl.drawingBufferWidth;
    program.begin(gl, options, false, false, clipOf(this.#map, gl, options));
    program.setPointSize((this.#options.pointSize ?? 2) * (gl.drawingBufferWidth / css));
    program.draw(gl, gpu, IDENTITY, mercatorFrame(lng, lat, h), sphereFrame(lng, lat, h), 1, false, 0);
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
  #map: MapLike | null = null;
  #program: ModelProgram | null = null;

  /** `i3s` reads `url` as an I3S scene layer (`i3sLayer`) instead of a 3D Tiles tileset. */
  constructor(options: TilesLayerOptions, i3s = false) {
    this.id = options.id;
    const url = new URL(options.url, document.baseURI).href;
    const call = <T>(op: string, args: object) => {
      start(options);
      return client.call<T>(op, args);
    };
    const parts: I3sParts = {
      loadTile: (tileUrl) => call("tile", { url: tileUrl }),
      loadNode: (args) => call("i3s", args),
      loadPoints: (args) => call("pcsl", args),
      upload: uploadModel,
      release: releaseModel,
      repaint: () => this.#map?.triggerRepaint?.(),
    };
    this.ready = (i3s ? import("./3d-i3s.js").then((m) => m.openI3s(url, options, parts)) : import("./3d-tiles.js").then((m) => m.openTileset(url, options, parts)))
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
    const properties = await hit.part.properties(hit.feature);
    return { tile: hit.tile.path, id: hit.feature, properties };
  }

  onAdd(map: unknown, gl: WebGL2RenderingContext): void {
    this.#map = map as MapLike;
    this.#program = new ModelProgram(gl);
  }

  onRemove(_map: unknown, gl: WebGL2RenderingContext): void {
    this.#engine?.release(gl);
    this.#program?.delete(gl);
    this.#program = null;
    this.#map = null;
  }

  render(gl: WebGL2RenderingContext, options: CustomRenderMethodInput): void {
    if (this.#program && this.#engine) this.#engine.render(gl, options, this.#program, clipOf(this.#map, gl, options));
  }

  renderShadow(gl: WebGL2RenderingContext, options: CustomRenderMethodInput): void {
    if (this.#program && this.#engine) this.#engine.renderShadow(gl, options, this.#program, clipOf(this.#map, gl, options));
  }
}

/** A custom layer for `map.addLayer` streaming the 3D Tiles tileset at `options.url`. */
export function tilesLayer(options: TilesLayerOptions): TilesLayer {
  return new TilesLayer(options);
}

/**
 * An I3S layer: the 3DObject, IntegratedMesh or PointCloud scene layer (I3S 1.7 and later, node pages,
 * WGS 84) at `url` — a SceneServer layer (`…/SceneServer/layers/0`) or a layer document `….json` with
 * its resources beside it — its nodes chosen by their `lodThreshold` as loaders.gl does (a point cloud's
 * by its points' density on screen), with the options of `tilesLayer` (`height`, `maximumLoadedTiles`,
 * `pointSize`; JPEG and PNG textures only) and a point cloud's `color` (as `pointCloudLayer`'s; heights
 * ramp over the root node's box). `queryFeature` gives a feature's attributes.
 */
export type I3sLayerOptions = Omit<TilesLayerOptions, "maximumScreenSpaceError"> & { color?: CloudColor };

/** A custom layer for `map.addLayer` streaming the I3S scene layer at `options.url`. */
export function i3sLayer(options: I3sLayerOptions): TilesLayer {
  return new TilesLayer(options, true);
}


export { measure3d, type Measure3d, type Position3d } from "./measure3d";

/** What `lineOfSight` finds: whether `to` is seen from `from`, and else the first point in the way. */
export interface Sight {
  visible: boolean;
  obstruction: [number, number, number] | null;
}

/**
 * Whether `to` is seen from `from` ([longitude, latitude, meters]) over what `map` draws (extrusions, 3D layers,
 * terrain), through `Map.castRay` (`margin` meters short of `to`, default 0.1, so the surface `to` was picked on
 * does not hide it).
 */
export function lineOfSight(map: { castRay(from: [number, number, number], to: [number, number, number], margin?: number): [number, number, number] | null }, from: [number, number, number], to: [number, number, number], margin?: number): Sight {
  const obstruction = map.castRay(from, to, margin);
  return { visible: !obstruction, obstruction };
}
