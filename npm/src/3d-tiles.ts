// The work of mbmap/3d's tiles layer, loaded with the first `tilesLayer`: the tileset read and
// selected each frame, contents asked of the 3D worker and drawn with the model program.
import type { CustomRenderMethodInput } from "./custom";
import type { LoadedModel, TilesLayerOptions } from "./3d";
import type { GpuModel, ModelProgram } from "./model/draw";
import { Y_UP, mercatorFrame, mul, sphereFrame } from "./model/place";
import { eastNorthUp, multiply, toCartographic } from "./tiles/geo";
import { frameState } from "./tiles/frame";
import { expandTileset } from "./tiles/implicit";
import { buildTree, Traversal, type Tile } from "./tiles/tileset";

/** What the layer lends the engine: the 3D worker's `tile` call, the model upload, a repaint. */
export interface TilesParts {
  loadTile(url: string): Promise<LoadedModel & { rtc: [number, number, number] | null; batchTable: Record<string, unknown> | null }>;
  upload(gl: WebGL2RenderingContext, model: LoadedModel, axis: ArrayLike<number>): GpuModel;
  release(gl: WebGL2RenderingContext, model: GpuModel): void;
  repaint(): void;
}

/** Contents loading at once. */
const MAX_LOADS = 6;

const IDENTITY = new Float64Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

/** A loaded tile's model on the GPU and where its meters (east, north, up) stand. */
export interface TileModel {
  gpu: GpuModel;
  batchTable: Record<string, unknown> | null;
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

/** Reads the tileset at `url` (implicit tiling expanded) and returns its engine. */
export async function openTileset(url: string, options: TilesLayerOptions, parts: TilesParts): Promise<TilesEngine> {
  const json = await expandTileset(JSON.parse(new TextDecoder().decode(await fetchBytes(url))), url, fetchBytes);
  return new TilesEngine(buildTree(json, url), options, parts);
}

/** A tileset's tree, its selection each frame, and its loaded contents. */
export class TilesEngine {
  #options: TilesLayerOptions;
  #parts: TilesParts;
  #root: Tile;
  #traversal: Traversal;
  #loading = 0;
  #loaded = new Set<Tile>();
  #gl: WebGL2RenderingContext | null = null;
  #generation = 0;
  #picks: { x: number; y: number; resolve: (hit: { tile: Tile; feature: number } | null) => void }[] = [];
  #target: { fb: WebGLFramebuffer; color: WebGLRenderbuffer; depth: WebGLRenderbuffer; w: number; h: number } | null = null;

  constructor(root: Tile, options: TilesLayerOptions, parts: TilesParts) {
    this.#root = root;
    this.#options = options;
    this.#parts = parts;
    this.#traversal = new Traversal(options.maximumScreenSpaceError ?? 8);
  }

  get selected(): Tile[] {
    return [...this.#traversal.selected.values()];
  }

  get idle(): boolean {
    return this.#loading === 0 && this.#traversal.requested.size === 0;
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
    const root = this.#root;
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
    program.begin(gl, t);
    for (const pass of [0, 1]) {
      gl.depthMask(pass === 0);
      this.#drawTiles(gl, program, options, pass);
    }
    gl.depthMask(true);
    if (this.#picks.length) this.#pick(gl, program, options);
    this.#evict(gl);
  }

  /** Draws the selected tiles' meshes of `pass`, each told its place in the list first when picking. */
  #drawTiles(gl: WebGL2RenderingContext, program: ModelProgram, options: CustomRenderMethodInput, pass: number, picking = false): Tile[] {
    const d = options.defaultProjectionData;
    const t = d.projectionTransition;
    const flat = t > 0 ? d.fallbackMatrix : d.mainMatrix;
    const plane = d.clippingPlane;
    const offset = this.#options.height ?? 0;
    const drawn: Tile[] = [];
    for (const tile of this.#traversal.selected.values()) {
      const m = tile.content as TileModel | null;
      if (!m) continue;
      const sphere = sphereFrame(m.lng, m.lat, m.height + offset);
      if (t > 0 && sphere[12] * plane[0] + sphere[13] * plane[1] + sphere[14] * plane[2] + plane[3] < 0) continue;
      drawn.push(tile);
      if (picking) program.setPickId(gl, drawn.length);
      const flatMatrix = mul(flat, mercatorFrame(m.lng, m.lat, m.height + offset));
      const globe = t > 0 ? mul(options.modelViewProjectionMatrix, sphere) : null;
      program.draw(gl, m.gpu, IDENTITY, flatMatrix, globe, 1, false, pass);
    }
    return drawn;
  }

  /** Asks which tile and feature are drawn at CSS pixel (`x`, `y`) of the canvas, answered after the next frame. */
  pick(x: number, y: number): Promise<{ tile: Tile; feature: number } | null> {
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
    let drawn: Tile[] = [];
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
      const tile = drawn[px[0] * 256 + px[1] - 1];
      resolve(tile ? { tile, feature: px[2] * 256 + px[3] } : null);
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
    const url = tile.contentUrl!;
    const generation = this.#generation;
    tile.state = "loading";
    this.#loading++;
    const done = () => {
      this.#loading--;
      this.#parts.repaint();
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
    this.#parts
      .loadTile(url)
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
        tile.content = { gpu: this.#parts.upload(gl, content, axis), lng: carto[0], lat: carto[1], height: carto[2], batchTable: content.batchTable } satisfies TileModel;
        tile.state = "ready";
        this.#loaded.add(tile);
      })
      .catch(() => (tile.state = "failed"))
      .finally(done);
  }

  #unload(tile: Tile, gl: WebGL2RenderingContext): void {
    const m = tile.content as TileModel | null;
    if (m) this.#parts.release(gl, m.gpu);
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
