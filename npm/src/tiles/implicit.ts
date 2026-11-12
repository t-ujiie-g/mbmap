// Implicit tiling (3D Tiles 1.1, 3DTILES_implicit_tiling): a tile's quadtree or octree expanded from
// its subtrees into tile headers, eagerly as @loaders.gl/3d-tiles 4.5.4's `parseImplicitTiles` (regions
// split per level; boxes and spheres split by the specification, which loaders.gl leaves whole).

/** A subtree's availability bitstreams: tiles, content (the first content only) and child subtrees. */
export interface Subtree {
  tile: Availability;
  content: Availability;
  childSubtrees: Availability;
}

type Availability = { constant: boolean } | { bits: Uint8Array };

const SUBTREE_MAGIC = 0x74627573;
/** Most tiles one implicit tileset may expand into. */
export const MAX_IMPLICIT_TILES = 200_000;

const available = (a: Availability, index: number): boolean =>
  "constant" in a ? a.constant : ((a.bits[Math.floor(index / 8)] ?? 0) >> index % 8) & 1 ? true : false;

/** Reads a subtree file (binary, or its JSON alone), fetching external buffers through `load`. */
export async function readSubtree(bytes: Uint8Array, load: (uri: string) => Promise<Uint8Array>): Promise<Subtree> {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let json: Record<string, any>;
  let bin: Uint8Array = new Uint8Array(0);
  if (bytes.length >= 24 && view.getUint32(0, true) === SUBTREE_MAGIC) {
    if (view.getUint32(4, true) !== 1) throw new Error("subtree files must be version 1");
    const jsonLength = view.getUint32(8, true) + 2 ** 32 * view.getUint32(12, true);
    const binLength = view.getUint32(16, true) + 2 ** 32 * view.getUint32(20, true);
    if (24 + jsonLength > bytes.length) throw new Error("the subtree's JSON runs past the file");
    json = JSON.parse(new TextDecoder().decode(bytes.subarray(24, 24 + jsonLength)));
    if (binLength) bin = bytes.subarray(24 + jsonLength);
  } else {
    json = JSON.parse(new TextDecoder().decode(bytes));
  }
  const buffers: Record<string, any>[] = Array.isArray(json.buffers) ? json.buffers : [];
  const views: Record<string, any>[] = Array.isArray(json.bufferViews) ? json.bufferViews : [];
  const loaded = new Map<number, Uint8Array>();
  const read = async (a: unknown): Promise<Availability> => {
    const o = (a ?? {}) as Record<string, any>;
    const index = Number.isFinite(o.bitstream) ? o.bitstream : o.bufferView;
    if (typeof index !== "number") return { constant: Boolean(o.constant) };
    const v = views[index];
    const b = v && buffers[v.buffer];
    if (!b) throw new Error("a subtree bitstream names no buffer view");
    let data = loaded.get(v.buffer);
    if (!data) {
      if (typeof b.uri === "string") data = await load(b.uri);
      else {
        const start = buffers.slice(0, v.buffer).reduce((sum, x) => sum + (x.byteLength ?? 0), 0);
        data = bin.subarray(start, start + (b.byteLength ?? 0));
      }
      loaded.set(v.buffer, data);
    }
    const offset = v.byteOffset ?? 0;
    if (offset + v.byteLength > data.length) throw new Error("a subtree bitstream runs past its buffer");
    return { bits: data.subarray(offset, offset + v.byteLength) };
  };
  const contents = Array.isArray(json.contentAvailability) ? json.contentAvailability[0] : json.contentAvailability;
  return { tile: await read(json.tileAvailability), content: await read(contents), childSubtrees: await read(json.childSubtreeAvailability) };
}

const template = (t: string, level: number, x: number, y: number, z: number) =>
  t.replace(/{level}|{x}|{y}|{z}/gi, (m) => String({ "{level}": level, "{x}": x, "{y}": y, "{z}": z }[m.toLowerCase()]));

/** `volume` of the implicit root split for the tile at `level`, `x`, `y`, `z`. */
function childVolume(volume: Record<string, any>, level: number, x: number, y: number, z: number, octree: boolean): Record<string, any> {
  const n = 2 ** level;
  if (volume.region) {
    const [west, south, east, north, minH, maxH] = volume.region;
    const sx = (east - west) / n;
    const sy = (north - south) / n;
    const sz = (maxH - minH) / n;
    return { region: [west + sx * x, south + sy * y, west + sx * (x + 1), south + sy * (y + 1), octree ? minH + sz * z : minH, octree ? minH + sz * (z + 1) : maxH] };
  }
  if (volume.box) {
    const b = volume.box;
    const c = [b[0], b[1], b[2]];
    const axes = [[b[3], b[4], b[5]], [b[6], b[7], b[8]], [b[9], b[10], b[11]]];
    const at = [x, y, z].map((i) => -1 + (2 * i + 1) / n);
    for (let k = 0; k < 3; k++) {
      if (k === 2 && !octree) break;
      for (let j = 0; j < 3; j++) c[j] += axes[k][j] * at[k];
    }
    return { box: [...c, ...axes.flatMap((a, k) => a.map((v) => (k === 2 && !octree ? v : v / n)))] };
  }
  throw new Error("implicit tiling needs a region or box bounding volume");
}

/**
 * The tile `header` (with `3DTILES_implicit_tiling` or 1.1's `implicitTiling`) expanded into explicit
 * children: `base` resolves its templates, `refine` is the tileset root's, `load` fetches subtrees.
 */
export async function expandImplicit(header: Record<string, any>, base: string, refine: unknown, load: (url: string) => Promise<Uint8Array>): Promise<Record<string, any>> {
  const imp = header.implicitTiling ?? header.extensions?.["3DTILES_implicit_tiling"];
  const octree = imp.subdivisionScheme === "OCTREE";
  const perTile = octree ? 8 : 4;
  const bits = octree ? 3 : 2;
  const maximumLevel = Number.isFinite(imp.availableLevels) ? imp.availableLevels - 1 : imp.maximumLevel;
  const subtreeLevels = imp.subtreeLevels;
  // Morton indices and tile coordinates stay within 32-bit integers.
  if (!Number.isInteger(subtreeLevels) || subtreeLevels < 1 || subtreeLevels > 10 || !Number.isInteger(maximumLevel) || maximumLevel < 0 || maximumLevel > 30) {
    throw new Error("implicit tiling needs subtreeLevels from 1 to 10 and levels up to 30");
  }
  // Templates are resolved once filled in: `new URL` would percent-encode their braces.
  const subtreeTemplate = String(imp.subtrees?.uri ?? "");
  const contentTemplate = typeof header.content?.uri === "string" ? header.content.uri : "";
  const root = header.boundingVolume ?? {};
  const rootError = header.geometricError;
  let count = 0;
  const subtreeAt = async (level: number, x: number, y: number, z: number) => {
    const url = new URL(template(subtreeTemplate, level, x, y, z), base).href;
    return readSubtree(await load(url), (uri) => load(new URL(uri, url).href));
  };
  type Parent = { morton: number; local: number; lx: number; ly: number; lz: number };
  type Place = { level: number; x: number; y: number; z: number };
  const visit = async (subtree: Subtree, at: Place, parent: Parent, child: number): Promise<Record<string, any> | null> => {
    const local = parent.local + 1;
    const level = at.level + local;
    if (level > maximumLevel) return null;
    const lx = (parent.lx << 1) + (child & 1);
    const ly = (parent.ly << 1) + ((child >> 1) & 1);
    const lz = (parent.lz << 1) + ((child >> 2) & 1);
    const x = (at.x << local) + lx;
    const y = (at.y << local) + ly;
    const z = (at.z << local) + lz;
    const morton = (parent.morton << bits) + child;
    let next = subtree;
    let nextAt = at;
    let nextParent: Parent;
    let index: number;
    if (local === subtreeLevels && available(subtree.childSubtrees, morton)) {
      next = await subtreeAt(level, x, y, z);
      nextAt = { level, x, y, z };
      nextParent = { morton: 0, local: 0, lx: 0, ly: 0, lz: 0 };
      index = 0;
    } else {
      nextParent = { morton, local, lx, ly, lz };
      index = (perTile ** local - 1) / (perTile - 1) + morton;
    }
    if (!available(next.tile, index)) return null;
    if (++count > MAX_IMPLICIT_TILES) throw new Error("the implicit tileset has too many tiles");
    const uri = available(next.content, index) && contentTemplate ? new URL(template(contentTemplate, level, x, y, z), base).href : "";
    const children: Record<string, any>[] = [];
    for (let i = 0; i < perTile; i++) {
      const c = await visit(next, nextAt, nextParent, i);
      if (c) children.push(c);
    }
    if (!uri && !children.length) return null;
    const error = rootError / 2 ** level;
    return { boundingVolume: childVolume(root, level, x, y, z, octree), geometricError: error, refine, content: uri ? { uri } : undefined, children };
  };
  const top = await visit(await subtreeAt(0, 0, 0, 0), { level: 0, x: 0, y: 0, z: 0 }, { morton: 0, local: -1, lx: 0, ly: 0, lz: 0 }, 0);
  const expanded: Record<string, any> = { ...header, children: top?.children ?? [] };
  delete expanded.implicitTiling;
  if (expanded.extensions) {
    expanded.extensions = { ...expanded.extensions };
    delete expanded.extensions["3DTILES_implicit_tiling"];
  }
  expanded.content = top?.content;
  return expanded;
}

/** `json` (a tileset) with every implicitly tiled tile expanded into explicit tiles. */
export async function expandTileset(json: Record<string, any>, base: string, load: (url: string) => Promise<Uint8Array>): Promise<Record<string, any>> {
  const refine = json.root?.refine;
  const walk = async (header: Record<string, any>): Promise<Record<string, any>> => {
    if (header?.implicitTiling ?? header?.extensions?.["3DTILES_implicit_tiling"]) return expandImplicit(header, base, refine, load);
    if (!Array.isArray(header?.children)) return header;
    return { ...header, children: await Promise.all(header.children.map(walk)) };
  };
  return { ...json, root: await walk(json.root) };
}
