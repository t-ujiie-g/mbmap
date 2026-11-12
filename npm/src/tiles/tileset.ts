// 3D Tiles 1.0 and 1.1 tilesets for mbmap/3d: the tile tree (external tilesets under the tile naming
// them, implicit tiling expanded) and the tiles to draw and load for a frame, as @loaders.gl/tiles
// 4.5.4's `Tileset3DTraverser` selects them (without skipping levels of detail).
import { boundingVolume, distanceSquaredTo, IDENTITY, MASK_INDETERMINATE, MASK_OUTSIDE, multiply, visibilityWithPlaneMask, type Plane, type Vec3, type Volume } from "./geo.ts";

/** What a frame is selected for, in ECEF meters: the camera, the culling planes and the screen height in pixels. */
export interface FrameState {
  position: Vec3;
  direction: Vec3;
  up: Vec3;
  planes: Plane[];
  height: number;
  /** loaders.gl's 1.15, `2 tan(fovy / 2)` for a 60° field of view. */
  sseDenominator: number;
  /** The matrix the view was taken from (frame.ts), for I3S's level of detail, which projects onto the screen. */
  view?: { matrix: ArrayLike<number>; globe: boolean; lat0: number; width: number };
}

export type TileState = "unloaded" | "loading" | "ready" | "failed";

/** A tile of the tree: its place (`path` of child indices from the root), what it holds and its state. */
export class Tile {
  readonly path: string;
  readonly header: Record<string, any>;
  readonly parent: Tile | null;
  readonly children: Tile[] = [];
  readonly refine: "ADD" | "REPLACE";
  readonly geometricError: number;
  readonly transform: Float64Array;
  readonly volume: Volume;
  readonly requestVolume: Volume | null;
  /** The content's URL, resolved against the tileset's; undefined for an empty tile. */
  readonly contentUrl: string | undefined;
  /** Whether the content is a tileset (known once loaded, as loaders.gl knows it). */
  isTileset = false;
  state: TileState = "unloaded";
  /** The loaded content, for the renderer. */
  content: unknown = null;
  lastUsed = 0;
  frame = -1;
  distance = 0;
  sse = 0;
  mask = MASK_INDETERMINATE;
  visible = false;
  inRequestVolume = false;
  shouldRefine = false;

  constructor(header: Record<string, any>, parent: Tile | null, path: string, base: string) {
    this.header = header;
    this.parent = parent;
    this.path = path;
    const refine = typeof header.refine === "string" ? header.refine.toUpperCase() : undefined;
    this.refine = refine === "ADD" || refine === "REPLACE" ? refine : (parent?.refine ?? "REPLACE");
    this.geometricError = typeof header.geometricError === "number" ? header.geometricError : NaN;
    const own = Array.isArray(header.transform) && header.transform.length === 16 ? Float64Array.from(header.transform) : IDENTITY;
    this.transform = parent ? multiply(parent.transform, own) : own;
    this.volume = boundingVolume(header.boundingVolume ?? {}, this.transform);
    this.requestVolume = header.viewerRequestVolume ? boundingVolume(header.viewerRequestVolume, this.transform) : null;
    const uri = header.content?.uri ?? header.content?.url;
    this.contentUrl = typeof uri === "string" ? new URL(uri, base).href : undefined;
  }

  get hasRenderContent(): boolean {
    return this.contentUrl !== undefined && !this.isTileset;
  }

  get hasEmptyContent(): boolean {
    return this.contentUrl === undefined;
  }

  get contentAvailable(): boolean {
    return this.state === "ready" && this.hasRenderContent;
  }

  get hasChildren(): boolean {
    return this.children.length > 0 || (Array.isArray(this.header.children) && this.header.children.length > 0);
  }
}

/** The most tiles a tree may hold (implicit tiling can name many). */
export const MAX_TILES = 200_000;

/** Adds the tiles of `json` (a tileset) under `parent` (an external tileset's tile), or as a new root. */
/** How deep external tilesets may nest. */
export const MAX_TILESET_DEPTH = 32;

/** Whether `tile` or one of its ancestors meets `test` (a cycle check before hanging content under it). */
export function lineageHas(tile: Tile | null, test: (t: Tile) => boolean): boolean {
  for (let t = tile; t; t = t.parent) if (test(t)) return true;
  return false;
}

export function buildTree(json: Record<string, any>, base: string, parent: Tile | null = null): Tile {
  if (!json?.asset || !["0.0", "1.0", "1.1"].includes(json.asset.version)) throw new Error("the tileset must be 3D Tiles 0.0, 1.0 or 1.1");
  if (!json.root || typeof json.root !== "object") throw new Error("the tileset has no root");
  let count = 0;
  const make = (header: Record<string, any>, up: Tile | null, path: string): Tile => {
    if (++count > MAX_TILES) throw new Error("the tileset has too many tiles");
    const tile = new Tile(header, up, path, base);
    const children = Array.isArray(header.children) ? header.children : [];
    children.forEach((child: Record<string, any>, i: number) => tile.children.push(make(child, tile, `${path}/${i}`)));
    return tile;
  };
  const root = make(json.root, parent, parent ? `${parent.path}/t` : "r");
  parent?.children.push(root);
  return root;
}

/**
 * The tiles to draw and those to load for `frame`, the traversal of loaders.gl's `TilesetTraverser`
 * with `Tileset3DTraverser`'s visibility: refined while the screen-space error exceeds
 * `maximumScreenSpaceError`, a REPLACE tile drawn until all its visible children are loaded.
 */
export class Traversal {
  selected = new Map<string, Tile>();
  requested = new Map<string, Tile>();
  /** Tiles to refine whose children are not built yet (I3S nodes whose node pages are still to load). */
  expand = new Map<string, Tile>();
  #frame = 0;
  #maximumScreenSpaceError: number;
  #refines: ((tile: Tile, frame: FrameState) => boolean) | undefined;

  /** `refines` replaces the screen-space error test (I3S's level of detail). */
  constructor(maximumScreenSpaceError = 8, refines?: (tile: Tile, frame: FrameState) => boolean) {
    this.#maximumScreenSpaceError = maximumScreenSpaceError;
    this.#refines = refines;
  }

  traverse(root: Tile, frame: FrameState): void {
    this.#frame++;
    this.selected = new Map();
    this.requested = new Map();
    this.expand = new Map();
    this.#update(root, frame);
    const stack: Tile[] = [root];
    while (stack.length > 0) {
      const tile = stack.pop()!;
      let shouldRefine = false;
      if (this.#canTraverse(tile, frame)) {
        if (tile.children.length < (tile.header.children?.length ?? 0)) this.expand.set(tile.path, tile);
        for (const child of tile.children) this.#update(child, frame);
        shouldRefine = this.#pushChildren(tile, frame, stack);
      }
      const parentRefines = !tile.parent || tile.parent.shouldRefine;
      const stoppedRefining = !shouldRefine;
      if (!tile.hasRenderContent) {
        this.#load(tile);
        if (stoppedRefining) this.#select(tile);
      } else if (tile.refine === "ADD") {
        this.#load(tile);
        this.#select(tile);
      } else {
        this.#load(tile);
        if (stoppedRefining) this.#select(tile);
      }
      tile.lastUsed = this.#frame;
      tile.shouldRefine = shouldRefine && parentRefines;
    }
  }

  #pushChildren(tile: Tile, frame: FrameState, stack: Tile[]): boolean {
    // Farthest first, so the nearest is taken first; the order is kept for the next frame, as loaders.gl
    // sorts its children in place.
    tile.children.sort((a, b) => (a.distance === 0 && b.distance === 0 ? 0 : b.distance - a.distance));
    const children = tile.children;
    const checkRefines = tile.refine === "REPLACE" && tile.hasRenderContent;
    let hasVisibleChild = false;
    let refines = true;
    for (const child of children) {
      if (child.visible && child.inRequestVolume) {
        const at = stack.indexOf(child);
        if (at >= 0) stack.splice(at, 1);
        stack.push(child);
        hasVisibleChild = true;
      } else if (checkRefines) {
        this.#load(child);
        child.lastUsed = this.#frame;
      }
      if (checkRefines) {
        let childRefines: boolean;
        if (!child.inRequestVolume) childRefines = false;
        else if (!child.hasRenderContent) childRefines = this.#emptyTraversal(child, frame);
        else childRefines = child.contentAvailable;
        refines = refines && childRefines;
        if (!refines) return false;
      }
    }
    return hasVisibleChild ? refines : false;
  }

  #emptyTraversal(root: Tile, frame: FrameState): boolean {
    let allLoaded = true;
    const stack = [root];
    while (stack.length > 0) {
      const tile = stack.pop()!;
      const traverse = !tile.hasRenderContent && this.#canTraverse(tile, frame);
      const emptyLeaf = !tile.hasRenderContent && tile.children.length === 0;
      if (!traverse && !tile.contentAvailable && !emptyLeaf) allLoaded = false;
      this.#update(tile, frame);
      if (!(tile.visible && tile.inRequestVolume)) {
        this.#load(tile);
        tile.lastUsed = this.#frame;
      }
      if (traverse) stack.push(...tile.children);
    }
    return root.hasEmptyContent || allLoaded;
  }

  #canTraverse(tile: Tile, frame: FrameState): boolean {
    if (!tile.hasChildren) return false;
    if (tile.isTileset) return true;
    if (this.#refines) return this.#refines(tile, frame);
    return tile.sse > this.#maximumScreenSpaceError;
  }

  #select(tile: Tile): void {
    if (tile.contentAvailable) this.selected.set(tile.path, tile);
  }

  #load(tile: Tile): void {
    if (tile.hasRenderContent && tile.state === "unloaded") this.requested.set(tile.path, tile);
  }

  /** loaders.gl's `Tile3D.updateVisibility` and `Tileset3DTraverser.updateTileVisibility`. */
  #update(tile: Tile, frame: FrameState): void {
    this.#visibility(tile, frame);
    if (!(tile.visible && tile.inRequestVolume)) return;
    if (tile.isTileset && tile.children.length > 0) {
      const first = tile.children[0];
      this.#update(first, frame);
      tile.visible = first.visible;
      return;
    }
    const parent = tile.parent;
    if (parent && !parent.isTileset && parent.refine === "ADD" && !(this.#sse(tile, frame, true) > this.#maximumScreenSpaceError)) tile.visible = false;
  }

  #visibility(tile: Tile, frame: FrameState): void {
    if (tile.frame === this.#frame) return;
    const parentMask = tile.parent ? tile.parent.mask : MASK_INDETERMINATE;
    tile.distance = Math.sqrt(Math.max(distanceSquaredTo(tile.volume, frame.position), 0));
    tile.sse = this.#sse(tile, frame, false);
    tile.mask = visibilityWithPlaneMask(frame.planes, tile.volume, parentMask);
    tile.visible = tile.mask !== MASK_OUTSIDE;
    tile.inRequestVolume = !tile.requestVolume || distanceSquaredTo(tile.requestVolume, frame.position) <= 0;
    tile.frame = this.#frame;
  }

  /** loaders.gl's `getTiles3DScreenSpaceError` (no dynamic screen-space error). */
  #sse(tile: Tile, frame: FrameState, useParent: boolean): number {
    const own = tile.geometricError;
    const value = useParent ? (tile.parent?.geometricError || own) : own;
    if (value === 0) return 0;
    const distance = Math.max(tile.distance, 1e-7);
    return (value * frame.height) / (distance * frame.sseDenominator);
  }
}
