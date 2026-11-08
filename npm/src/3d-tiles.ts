// The work of mbmap/3d's tiles layer, loaded with the first `tilesLayer`: the tileset read and
// selected each frame, contents asked of the 3D worker and drawn with the model program.
import type { CustomRenderMethodInput } from "./custom";
import type { LoadedModel, TilesLayerOptions } from "./3d";
import type { GpuModel, ModelProgram } from "./model/draw";
import type { StructuralMetadata } from "./model/gltf";
import { batchTableProperties, propertyTableProperties } from "./tiles/properties";
import { Y_UP, mercatorFrame, mul, sphereFrame } from "./model/place";
import { eastNorthUp, multiply, toCartographic } from "./tiles/geo";
import { frameState } from "./tiles/frame";
import { expandTileset } from "./tiles/implicit";
import { buildTree, Traversal, type Tile } from "./tiles/tileset";

/** What the layer lends the engine: the 3D worker's `tile` call, the model upload, a repaint. */
export interface TilesParts {
  loadTile(url: string): Promise<{ parts: ContentPart[] }>;
  upload(gl: WebGL2RenderingContext, model: LoadedModel, axis: ArrayLike<number>): GpuModel;
  release(gl: WebGL2RenderingContext, model: GpuModel): void;
  repaint(): void;
}

/** Contents loading at once. */
const MAX_LOADS = 6;

const IDENTITY = new Float64Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

/** A loaded tile's model on the GPU and where its meters (east, north, up) stand. */
/** A part of a tile's content as the 3D worker gives it: a b3dm, i3dm, pnts or glTF (a cmpt's are several). */
export interface ContentPart extends LoadedModel {
  kind: "b3dm" | "i3dm" | "pnts" | "glTF";
  rtc: [number, number, number] | null;
  batchLength: number;
  batchTable: Record<string, unknown> | null;
  batchBinary: Uint8Array;
  instances: { matrices: Float64Array; batchIds: Uint32Array } | null;
  metadata?: StructuralMetadata;
}

/** A part on the GPU: its model, where each instance goes (meters, east, north, up) and its batch. */
export interface GpuPart {
  gpu: GpuModel;
  places: Float64Array[];
  batchIds: Uint32Array | null;
  /** The properties of feature `id` (batch table, EXT_structural_metadata property table, I3S attributes). */
  properties(id: number): Record<string, unknown> | Promise<Record<string, unknown>>;
}

/** A tile's part drawn in the pick pass, and the feature hit in it. */
interface Picked {
  tile: Tile;
  part: GpuPart;
}
export interface Hit extends Picked {
  feature: number;
}

export interface TileModel {
  parts: GpuPart[];
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

/** How `part`'s feature ids become properties: its EXT_structural_metadata table, else its batch table. */
function propertiesOf(part: ContentPart): (id: number) => Record<string, unknown> {
  const table = part.primitives.flatMap((p) => p.featureIds ?? []).find((f) => f.propertyTable !== undefined)?.propertyTable;
  let props: { count: number; get(id: number): Record<string, unknown> } | null = null;
  try {
    props = part.metadata && table !== undefined ? propertyTableProperties(part.metadata, table) : batchTableProperties(part.batchTable, part.batchBinary, part.batchLength);
  } catch {
    props = null;
  }
  return (id) => (props && id >= 0 && id < props.count ? props.get(id) : Object.create(null));
}

/**
 * Where an engine's tiles come from: the tree's `root`, the `traversal` selecting it, a tile's content
 * (`load`, on `gl`) and the children of the tiles the traversal wants refined (`expand`, which repaints when they come).
 */
export interface TileSource {
  root: Tile;
  traversal: Traversal;
  load(tile: Tile, gl: WebGL2RenderingContext): Promise<TileModel | null>;
  expand?(tiles: Map<string, Tile>, repaint: () => void): void;
}

/** A 3D Tiles tile's content: an external tileset hung under it (null), else its parts placed in meters. */
async function loadTile3D(tile: Tile, gl: WebGL2RenderingContext, parts: TilesParts): Promise<TileModel | null> {
  const url = tile.contentUrl!;
  if (/\.json([?#]|$)/i.test(url)) {
    buildTree(await expandTileset(JSON.parse(new TextDecoder().decode(await fetchBytes(url))), url, fetchBytes), url, tile);
    tile.isTileset = true;
    return null;
  }
  const content = await parts.loadTile(url);
  // Meters of each part: east, north, up at the tile's center from the tile's transform, then
  // RTC_CENTER and glTF's +Y up turned to +Z (a pnts is +Z up already), or each instance's matrix (RTC included).
  const center = tile.volume.center;
  const carto = toCartographic(center) ?? [0, 0, 0];
  const base = multiply(rigidInverse(eastNorthUp(center)), tile.transform);
  const gpuParts = content.parts.map((part): GpuPart => {
    let places: Float64Array[];
    if (part.instances) {
      const m = part.instances.matrices;
      places = Array.from({ length: m.length / 16 }, (_, i) => multiply(multiply(base, m.subarray(i * 16, i * 16 + 16)), Y_UP));
    } else {
      const placed = multiply(base, [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, ...(part.rtc ?? [0, 0, 0]), 1]);
      places = [part.kind === "pnts" ? placed : multiply(placed, Y_UP)];
    }
    return { gpu: parts.upload(gl, part, IDENTITY), places, batchIds: part.instances?.batchIds ?? null, properties: propertiesOf(part) };
  });
  return { parts: gpuParts, lng: carto[0], lat: carto[1], height: carto[2] };
}

/** Reads the tileset at `url` (implicit tiling expanded) and returns its engine. */
export async function openTileset(url: string, options: TilesLayerOptions, parts: TilesParts): Promise<TilesEngine> {
  const json = await expandTileset(JSON.parse(new TextDecoder().decode(await fetchBytes(url))), url, fetchBytes);
  const source: TileSource = { root: buildTree(json, url), traversal: new Traversal(options.maximumScreenSpaceError ?? 8), load: (tile, gl) => loadTile3D(tile, gl, parts) };
  return new TilesEngine(source, options, parts);
}

/** A tileset's tree, its selection each frame, and its loaded contents. */
export class TilesEngine {
  #options: TilesLayerOptions;
  #parts: TilesParts;
  #source: TileSource;
  #traversal: Traversal;
  #loading = 0;
  #loaded = new Set<Tile>();
  #gl: WebGL2RenderingContext | null = null;
  #generation = 0;
  #picks: { x: number; y: number; resolve: (hit: Hit | null) => void }[] = [];
  #target: { fb: WebGLFramebuffer; color: WebGLRenderbuffer; depth: WebGLRenderbuffer; w: number; h: number } | null = null;

  constructor(source: TileSource, options: TilesLayerOptions, parts: TilesParts) {
    this.#source = source;
    this.#options = options;
    this.#parts = parts;
    this.#traversal = source.traversal;
  }

  get selected(): Tile[] {
    return [...this.#traversal.selected.values()];
  }

  get idle(): boolean {
    return this.#loading === 0 && this.#traversal.requested.size === 0 && this.#traversal.expand.size === 0;
  }

  /** `pointSize` (CSS pixels) in the drawing buffer's pixels. */
  #pointPixels(gl: WebGL2RenderingContext): number {
    const css = (gl.canvas as HTMLCanvasElement).clientWidth || gl.drawingBufferWidth;
    return (this.#options.pointSize ?? 2) * (gl.drawingBufferWidth / css);
  }

  /** Frees every loaded content (the layer was removed). */
  release(gl: WebGL2RenderingContext): void {
    for (const tile of this.#loaded) this.#unload(tile, gl);
    if (this.#target) this.#freeTarget(gl);
    for (const p of this.#picks.splice(0)) p.resolve(null);
    this.#gl = null;
    this.#generation++;
  }

  render(gl: WebGL2RenderingContext, options: CustomRenderMethodInput, program: ModelProgram): void {
    this.#gl = gl;
    const d = options.defaultProjectionData;
    const t = d.projectionTransition;
    const flat = t > 0 ? d.fallbackMatrix : d.mainMatrix;
    const canvas = gl.canvas as HTMLCanvasElement;
    const globe = t > 0.5;
    const frame = frameState(globe ? options.modelViewProjectionMatrix : flat, canvas.clientHeight || gl.drawingBufferHeight, globe, canvas.clientWidth || gl.drawingBufferWidth);
    if (!frame) return;
    this.#traversal.traverse(this.#source.root, frame);
    this.#source.expand?.(this.#traversal.expand, this.#parts.repaint);
    const wanted = [...this.#traversal.requested.values()].sort((a, b) => a.distance - b.distance);
    for (const tile of wanted) {
      if (this.#loading >= MAX_LOADS) break;
      this.#load(tile);
    }
    program.begin(gl, t, false, options.lights);
    program.setPointSize(this.#pointPixels(gl));
    for (const pass of [0, 1]) {
      gl.depthMask(pass === 0);
      this.#drawTiles(gl, program, options, pass);
    }
    gl.depthMask(true);
    if (this.#picks.length) this.#pick(gl, program, options);
    this.#evict(gl);
  }

  /** Draws the selected tiles' meshes of `pass`, each told its place in the list first when picking. */
  #drawTiles(gl: WebGL2RenderingContext, program: ModelProgram, options: CustomRenderMethodInput, pass: number, picking = false): Picked[] {
    const d = options.defaultProjectionData;
    const t = d.projectionTransition;
    const flat = t > 0 ? d.fallbackMatrix : d.mainMatrix;
    const plane = d.clippingPlane;
    const offset = this.#options.height ?? 0;
    const drawn: Picked[] = [];
    for (const tile of this.#traversal.selected.values()) {
      const m = tile.content as TileModel | null;
      if (!m) continue;
      const sphere = sphereFrame(m.lng, m.lat, m.height + offset);
      if (t > 0 && sphere[12] * plane[0] + sphere[13] * plane[1] + sphere[14] * plane[2] + plane[3] < 0) continue;
      const flatMatrix = mul(flat, mercatorFrame(m.lng, m.lat, m.height + offset));
      const globe = t > 0 ? mul(options.modelViewProjectionMatrix, sphere) : null;
      for (const part of m.parts) {
        drawn.push({ tile, part });
        if (picking) program.setPickId(gl, drawn.length);
        part.places.forEach((place, i) => program.draw(gl, part.gpu, place, flatMatrix, globe, 1, false, pass, part.batchIds?.[i]));
      }
    }
    return drawn;
  }

  /** Asks which tile and feature are drawn at CSS pixel (`x`, `y`) of the canvas, answered after the next frame. */
  pick(x: number, y: number): Promise<Hit | null> {
    return new Promise((resolve) => {
      this.#picks.push({ x, y, resolve });
      this.#parts.repaint();
    });
  }

  /** Draws the tiles' ids (tile in red and green, feature in blue and alpha) offscreen and reads the picked pixels. */
  #pick(gl: WebGL2RenderingContext, program: ModelProgram, options: CustomRenderMethodInput): void {
    const [w, h] = [gl.drawingBufferWidth, gl.drawingBufferHeight];
    if (!this.#target || this.#target.w !== w || this.#target.h !== h) {
      if (this.#target) this.#freeTarget(gl);
      const fb = gl.createFramebuffer()!;
      const color = gl.createRenderbuffer()!;
      const depth = gl.createRenderbuffer()!;
      gl.bindRenderbuffer(gl.RENDERBUFFER, color);
      gl.renderbufferStorage(gl.RENDERBUFFER, gl.RGBA8, w, h);
      gl.bindRenderbuffer(gl.RENDERBUFFER, depth);
      gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, w, h);
      gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
      gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, color);
      gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, depth);
      this.#target = { fb, color, depth, w, h };
    }
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.#target.fb);
    gl.viewport(0, 0, w, h);
    gl.disable(gl.BLEND);
    gl.enable(gl.DEPTH_TEST);
    gl.depthFunc(gl.LEQUAL);
    gl.depthMask(true);
    gl.clearColor(0, 0, 0, 0);
    gl.clearDepth(1);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    program.begin(gl, options.defaultProjectionData.projectionTransition, true);
    program.setPointSize(this.#pointPixels(gl));
    let drawn: Picked[] = [];
    for (const pass of [0, 1]) drawn = this.#drawTiles(gl, program, options, pass, true);
    const canvas = gl.canvas as HTMLCanvasElement;
    const ratio = w / (canvas.clientWidth || w);
    const px = new Uint8Array(4);
    for (const { x, y, resolve } of this.#picks.splice(0)) {
      const [cx, cy] = [Math.floor(x * ratio), Math.floor(h - 1 - y * ratio)];
      if (cx < 0 || cy < 0 || cx >= w || cy >= h) {
        resolve(null);
        continue;
      }
      gl.readPixels(cx, cy, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px);
      const at = drawn[px[0] * 256 + px[1] - 1];
      resolve(at ? { ...at, feature: px[2] * 256 + px[3] } : null);
    }
  }

  #freeTarget(gl: WebGL2RenderingContext): void {
    const t = this.#target!;
    gl.deleteFramebuffer(t.fb);
    gl.deleteRenderbuffer(t.color);
    gl.deleteRenderbuffer(t.depth);
    this.#target = null;
  }

  #load(tile: Tile): void {
    const generation = this.#generation;
    const gl = this.#gl!;
    tile.state = "loading";
    this.#loading++;
    this.#source
      .load(tile, gl)
      .then((model) => {
        if (generation !== this.#generation) {
          if (model) for (const part of model.parts) this.#parts.release(gl, part.gpu);
          tile.state = "unloaded";
          return;
        }
        tile.content = model;
        tile.state = "ready";
        if (model) this.#loaded.add(tile);
      })
      .catch(() => (tile.state = "failed"))
      .finally(() => {
        this.#loading--;
        this.#parts.repaint();
      });
  }

  #unload(tile: Tile, gl: WebGL2RenderingContext): void {
    const m = tile.content as TileModel | null;
    if (m) for (const part of m.parts) this.#parts.release(gl, part.gpu);
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
