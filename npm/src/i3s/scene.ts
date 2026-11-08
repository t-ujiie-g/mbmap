// I3S scene layers (OGC I3S 1.7 and later, with node pages) for mbmap/3d: the layer's resources, its
// nodes as tiles of the shared traversal, and the level of detail @loaders.gl/tiles 4.5.4 selects I3S
// nodes with (`getLodStatus`, `getProjectedRadius`). Import-free.
import { add, cross, eastNorthUp, length, normalize, scale, sub, toCartesian, toCartographic, type Vec3 } from "../tiles/geo.ts";
import { invert } from "../tiles/frame.ts";
import { checkSpatialReference, nodeResources, type I3sLayer } from "./content.ts";
import { Tile, type FrameState } from "../tiles/tileset.ts";

/** MapLibre's globe radius in meters (as frame.ts). */
const GLOBE_RADIUS = 6371008.8;
/** The most nodes a layer may name. */
export const MAX_NODES = 1_000_000;

/** A node of a node page (I3S 1.7 `node`), as far as mbmap reads it. */
export interface I3sNode {
  index: number;
  lodThreshold?: number;
  obb: { center: [number, number, number]; halfSize: [number, number, number]; quaternion: [number, number, number, number] };
  children?: number[];
  mesh?: {
    material?: { definition: number; resource: number };
    geometry?: { definition: number; resource: number; vertexCount?: number; featureCount?: number };
    attribute?: { resource: number };
  };
}

/** A layer as read: its JSON, where its resources are, and its node pages read so far. */
export interface I3sScene {
  json: I3sLayer & Record<string, any>;
  base: string;
  query: string;
  nodesPerPage: number;
  squared: boolean;
  pages: Map<number, Promise<I3sNode[]>>;
}

/**
 * Where a layer's resources are: beside a layer document `url` ending in `.json` (a layer written out as
 * files), else under `url` itself (a SceneServer layer); a query (a token) goes with every request.
 */
export function layerBase(url: string): { base: string; query: string } {
  const u = new URL(url);
  const query = u.search;
  u.search = "";
  u.hash = "";
  let base = u.href.replace(/\/+$/, "");
  if (/\.json$/i.test(u.pathname)) base = base.slice(0, base.lastIndexOf("/"));
  return { base, query };
}

/** The URL of resource `path` (`nodepages/0`, `nodes/3/geometries/1`, …) of `layer`. */
export const resourceUrl = (layer: Pick<I3sScene, "base" | "query">, path: string): string => `${layer.base}/${path}${layer.query}`;

/** Reads a layer document: 3DObject or IntegratedMesh with node pages. */
export function readLayer(json: Record<string, any>, url: string): I3sScene {
  const type = json?.layerType;
  if (type !== "3DObject" && type !== "IntegratedMesh") throw new Error(`the I3S layer is ${type ?? "of no type"}, not 3DObject or IntegratedMesh`);
  if (!json.nodePages) throw new Error("only I3S layers with node pages (1.7 and later) are read");
  checkSpatialReference(json);
  const nodesPerPage = json.nodePages.nodesPerPage ?? 64;
  if (!Number.isInteger(nodesPerPage) || nodesPerPage < 1 || nodesPerPage > MAX_NODES) throw new Error("the I3S layer's nodesPerPage is not a positive integer");
  return { json, ...layerBase(url), nodesPerPage, squared: json.nodePages.lodSelectionMetricType === "maxScreenThresholdSQ", pages: new Map() };
}

/** Node `id` of `layer`, its node page fetched with `fetchJson` the first time. */
export async function nodeById(layer: I3sScene, id: number, fetchJson: (url: string) => Promise<any>): Promise<I3sNode> {
  if (!Number.isInteger(id) || id < 0 || id >= MAX_NODES) throw new Error(`no I3S node ${id}`);
  const page = Math.floor(id / layer.nodesPerPage);
  let nodes = layer.pages.get(page);
  if (!nodes) {
    nodes = fetchJson(resourceUrl(layer, `nodepages/${page}`)).then((p) => (Array.isArray(p?.nodes) ? p.nodes : []));
    layer.pages.set(page, nodes);
  }
  const node = (await nodes)[id % layer.nodesPerPage];
  if (!node || node.index !== id || !node.obb) throw new Error(`no I3S node ${id}`);
  return node;
}

/** gl-matrix's `mat3.fromQuat`, column-major. */
function fromQuat(q: ArrayLike<number>): number[] {
  const [x, y, z, w] = [q[0], q[1], q[2], q[3]];
  const [x2, y2, z2] = [x + x, y + y, z + z];
  const [xx, yx, yy, zx, zy, zz, wx, wy, wz] = [x * x2, y * x2, y * y2, z * x2, z * y2, z * z2, w * x2, w * y2, w * z2];
  return [1 - yy - zz, yx + wz, zx - wy, yx - wz, 1 - xx - zz, zy + wx, zx + wy, zy - wx, 1 - xx - yy];
}

/** gl-matrix's `vec3.transformQuat`. */
function transformQuat(v: ArrayLike<number>, q: ArrayLike<number>): Vec3 {
  const [qx, qy, qz, qw] = [q[0], q[1], q[2], q[3]];
  const [x, y, z] = [v[0], v[1], v[2]];
  const uv = [qy * z - qz * y, qz * x - qx * z, qx * y - qy * x];
  const uuv = [qy * uv[2] - qz * uv[1], qz * uv[0] - qx * uv[2], qx * uv[1] - qy * uv[0]];
  const w2 = qw * 2;
  return [x + uv[0] * w2 + uuv[0] * 2, y + uv[1] * w2 + uuv[1] * 2, z + uv[2] * w2 + uuv[2] * 2];
}

/**
 * Node `node` of `layer` as a tile under `parent`: its OBB as loaders.gl's `createBox` turns each axis,
 * its geometry resource as content, its level-of-detail value (`maxScreenThresholdSQ` as a diameter in
 * pixels) and the radius of the OBB's bounding sphere, which the level of detail projects.
 */
export function nodeTile(layer: I3sScene, node: I3sNode, parent: Tile | null): Tile {
  const { center, halfSize: h, quaternion: q } = node.obb;
  const c = toCartesian(center[0], center[1], center[2]);
  const axes = [transformQuat([1, 0, 0], q), transformQuat([0, 1, 0], q), transformQuat([0, 0, 1], q)].map((a, i) => scale(a, h[i]));
  const d = fromQuat(q);
  const corner = [0, 1, 2].map((k) => d[k] * h[0] + d[3 + k] * h[1] + d[6 + k] * h[2]);
  const geometry = nodeResources(layer.json, node)?.geometry;
  const lod = typeof node.lodThreshold === "number" ? node.lodThreshold : NaN;
  const header = {
    boundingVolume: { box: [...c, ...axes.flat()] },
    refine: "REPLACE",
    content: geometry ? { uri: resourceUrl(layer, geometry) } : undefined,
    children: node.children ?? [],
    node,
    mbs: [center[0], center[1], center[2], length(corner)],
    lodMetricValue: layer.squared ? Math.sqrt(lod / (Math.PI * 0.25)) : lod,
  };
  const tile = new Tile(header, parent, String(node.index), layer.base + "/");
  parent?.children.push(tile);
  return tile;
}

/** gl-matrix's `vec3.transformMat4`, w divided out. */
function transformMat4(m: ArrayLike<number>, p: ArrayLike<number>): Vec3 {
  const w = m[3] * p[0] + m[7] * p[1] + m[11] * p[2] + m[15] || 1;
  return [0, 1, 2].map((r) => (m[r] * p[0] + m[4 + r] * p[1] + m[8 + r] * p[2] + m[12 + r]) / w) as Vec3;
}

/** Longitude, latitude and height to the screen pixels and depth of the view `frame` was taken from, as deck.gl's `viewport.project`. */
export function projector(frame: FrameState): (p: ArrayLike<number>) => Vec3 {
  const { matrix, globe, lat0, width } = frame.view!;
  return (p) => {
    const [l, f, h] = [(p[0] * Math.PI) / 180, (p[1] * Math.PI) / 180, p[2]];
    const r = 1 + h / GLOBE_RADIUS;
    const v = globe
      ? [Math.cos(f) * Math.sin(l) * r, Math.sin(f) * r, Math.cos(f) * Math.cos(l) * r]
      : [(p[0] + 180) / 360, (1 - Math.log(Math.tan(Math.PI / 4 + f / 2)) / Math.PI) / 2, h / (2 * Math.PI * 6378137 * Math.cos((lat0 * Math.PI) / 180))];
    const c = [0, 1, 2, 3].map((k) => matrix[k] * v[0] + matrix[4 + k] * v[1] + matrix[8 + k] * v[2] + matrix[12 + k]);
    return [((c[0] / c[3] + 1) / 2) * width, ((1 - c[1] / c[3]) / 2) * frame.height, c[2] / c[3]];
  };
}

/** loaders.gl's `getProjectedRadius`: the radius on screen of `tile`'s bounding sphere, taken across the view. */
export function projectedRadius(tile: Tile, frame: FrameState, project = projector(frame)): number {
  const mbs: number[] = tile.header.mbs;
  const center = tile.volume.center;
  const cameraCarto = toCartographic(frame.position) ?? [0, 0, 0];
  const camera = toCartesian(cameraCarto[0], cameraCarto[1], cameraCarto[2]);
  const toEye = normalize(sub(camera, center));
  const enuToCartesian = eastNorthUp(center);
  const cartesianToEnu = invert(enuToCartesian)!;
  const eye = transformMat4(cartesianToEnu, camera);
  const projection = Math.sqrt(eye[0] * eye[0] + eye[1] * eye[1]);
  const extra = transformMat4(enuToCartesian, [eye[0], eye[1], (projection * projection) / eye[2]]);
  const radius = scale(normalize(cross(toEye, normalize(sub(extra, center)))), mbs[3]);
  const border = toCartographic(add(radius, center)) ?? [0, 0, 0];
  const a = project([mbs[0], mbs[1], mbs[2]]);
  const b = project(border);
  return length(sub(a, b));
}

/** loaders.gl's `getLodStatus`: whether to refine `tile` ("DIG"), draw it, or leave it ("OUT", under 2 px). */
export function lodStatus(tile: Tile, frame: FrameState): "DIG" | "DRAW" | "OUT" {
  const value: number = tile.header.lodMetricValue;
  if (value === 0 || Number.isNaN(value)) return "DIG";
  const size = 2 * projectedRadius(tile, frame);
  if (size < 2) return "OUT";
  if (!tile.header.children || size <= value) return "DRAW";
  return "DIG";
}
