// `mbmap/analysis`: spatial analysis in a worker of its own, started on the
// first `load`. Measures and predicates match Turf.js; the index is flatbush;
// geometry operations are Clipper2's, spatial relations JTS's (DE-9IM),
// simplification, hulls, Delaunay, Voronoi and line operations Turf's, concaveman's
// and d3-delaunay's, and grids, IDW, clusters, contours and density Turf's and
// d3-contour's, each in a module loaded on their first use.
import { crsArg as crsArgOf, type Crs } from "./crs";
import { demZoom } from "./dem-zoom";
import { packPattern } from "./relate-pattern";
import { CURVATURE_COEFF, groundDistance, sight } from "./sight";

export { classBreaks, classStep, MAX_CLASS_VALUES, MAX_CLASSES, statistics, type ClassMethod, type Statistics } from "./classify";
import { httpUrl, resolveTemplate, wasmUrl } from "./urls";
import { WorkerClient } from "./worker-client";

/** `[minX, minY, maxX, maxY]` in degrees. */
export type BBox = [number, number, number, number];

/**
 * Where the analysis worker and its wasm (`workerUrl`, `wasmUrl`), the geometry module
 * (`geometryWasmUrl`), the spatial relation module (`relateWasmUrl`), the shape module
 * (`shapesWasmUrl`), the surface module (`surfaceWasmUrl`), the viewshed module (`viewshedWasmUrl`) and
 * the coordinate system module (`projWasmUrl`) are served; by default next to this module.
 */
export interface AnalysisOptions {
  workerUrl?: string | URL;
  wasmUrl?: string | URL;
  geometryWasmUrl?: string | URL;
  relateWasmUrl?: string | URL;
  shapesWasmUrl?: string | URL;
  surfaceWasmUrl?: string | URL;
  viewshedWasmUrl?: string | URL;
  projWasmUrl?: string | URL;
}

export type { Crs };

const named = new Map<string, string>();

/**
 * Names `projString` so that `name` can be passed wherever a CRS is taken, as
 * `proj4.defs` does (`defineCrs("EPSG:2154", "+proj=lcc ...")`); it overrides
 * a known EPSG code of that name. The string is parsed when first used.
 */
export function defineCrs(name: string, projString: string): void {
  if (typeof projString !== "string" || !projString.trim().startsWith("+")) throw new Error(`mbmap: analysis: not a PROJ string: ${String(projString)}`);
  named.set(name.trim().toUpperCase(), projString);
}

const crsArg = (crs: Crs) => crsArgOf(crs, "analysis", named);

/**
 * How `buffer` measures its distance: `"geodesic"` on the ground (true meters
 * anywhere), `"planar"` in a projected CRS's plane (`crs`, Web Mercator by default).
 */
export type BufferMode = "geodesic" | "planar";

/**
 * `mode` (default `"geodesic"`); `join` and `cap` (default `"round"`); `arcTolerance`: how far round
 * edges may stray from true arcs in meters (default distance / 500); `crs`: the projected CRS a
 * planar buffer is measured in (default EPSG:3857).
 */
export interface BufferOptions {
  mode?: BufferMode;
  join?: "round" | "miter" | "square" | "bevel";
  cap?: "round" | "butt" | "square";
  arcTolerance?: number;
  crs?: Crs;
}

/** `crs`: the CRS of the data's coordinates (default EPSG:4326); they are kept as longitude and latitude. */
export interface LoadOptions extends AnalysisOptions {
  crs?: Crs;
}

/** `DemGrid.viewshed`'s options, as gdal_viewshed's `-oz`, `-tz`, `-md`, `-cc`, `-om`, `-vv`, `-iv`, `-ov`. */
export interface ViewshedOptions {
  observerHeight?: number;
  targetHeight?: number;
  maxDistance?: number;
  curvatureCoeff?: number;
  mode?: keyof typeof VIEWSHED_MODES;
  visibleValue?: number;
  invisibleValue?: number;
  outOfRangeValue?: number;
}

/** A viewshed: its cells row by row from the north over `bounds`. */
export interface ViewshedResult {
  width: number;
  height: number;
  bounds: BBox;
  values: Float64Array;
}

/** `DemGrid.lineOfSight`'s options. */
export interface LineOfSightOptions {
  observerHeight?: number;
  targetHeight?: number;
  curvatureCoeff?: number;
  samples?: number;
}

const VIEWSHED_MODES = { normal: 0, dem: 1, ground: 2 } as const;
const MAX_SIGHT_SAMPLES = 100_000;

/** `Dataset.interpolate`'s options. */
export interface InterpolateOptions {
  gridType?: "square" | "point" | "hex" | "triangle";
  property?: string;
  weight?: number;
}

/** `Dataset.density`'s options. */
export interface DensityOptions {
  bbox?: BBox;
  width?: number;
  height?: number;
  cellSize?: number;
  bandwidth?: number;
  thresholds?: number;
  weight?: string;
}

/** What a DBSCAN point is. */
export type DbscanKind = "core" | "edge" | "noise";
const DBSCAN_KINDS: DbscanKind[] = ["core", "edge", "noise"];

// surface_worker's grid codes.
const GRIDS = { point: 0, square: 1, hex: 2, triangle: 3 } as const;

/**
 * A grid over `bbox` as Turf makes it (`cellSide` in kilometers): `point` (pointGrid), `square`
 * (squareGrid), `hex` (hexGrid; `triangles` splits each hexagon in six) or `triangle` (triangleGrid).
 */
export function grid(bbox: BBox, cellSide: number, type: keyof typeof GRIDS = "square", options: AnalysisOptions & { triangles?: boolean } = {}): Promise<Dataset> {
  if (!Array.isArray(bbox) || bbox.length !== 4 || !bbox.every(Number.isFinite) || !(cellSide > 0) || !(type in GRIDS)) {
    return Promise.reject(new Error("mbmap: analysis: invalid grid"));
  }
  start(options);
  const fn = ["point_grid", "square_grid", "hex_grid", "triangle_grid"][GRIDS[type]];
  return call<{ dataset: number; features: number }>("surface", { dataset: -1, fn, args: [...bbox, cellSide, options.triangles ? 1 : 0] }).then(
    ({ dataset, features }) => new Dataset(dataset, features),
  );
}

/** Where a feature's lines come nearest to a point (`Dataset.nearestPointOnLine`). */
export interface NearestOnLine {
  point: [number, number];
  dist: number;
  location: number;
  index: number;
  multiFeatureIndex: number;
}

/** Per polygon: the points inside, how many have a numeric value, their sum and mean (NaN without one). */
export interface Collected {
  count: Float64Array;
  numbers: Float64Array;
  sum: Float64Array;
  mean: Float64Array;
}

const client = new WorkerClient("analysis");

function start(options: AnalysisOptions): void {
  client.start(options.workerUrl ?? new URL("./analysis-worker.js", import.meta.url), (page) => ({
    wasm: wasmUrl(options.wasmUrl ?? new URL("./analysis.wasm", import.meta.url), page),
    geometry: wasmUrl(options.geometryWasmUrl ?? new URL("./geometry.wasm", import.meta.url), page),
    relate: wasmUrl(options.relateWasmUrl ?? new URL("./relate.wasm", import.meta.url), page),
    shapes: wasmUrl(options.shapesWasmUrl ?? new URL("./shapes.wasm", import.meta.url), page),
    surface: wasmUrl(options.surfaceWasmUrl ?? new URL("./surface.wasm", import.meta.url), page),
    viewshed: wasmUrl(options.viewshedWasmUrl ?? new URL("./viewshed.wasm", import.meta.url), page),
    proj: wasmUrl(options.projWasmUrl ?? new URL("./proj.wasm", import.meta.url), page),
  }));
}

function call<T>(op: string, args: object, transfer: Transferable[] = []): Promise<T> {
  if (!client.started) return Promise.reject(new Error("mbmap: analysis: no dataset has been loaded"));
  return client.call<T>(op, args, transfer);
}

// Codes of geometry_worker/geometry.mbt.
const JOIN = { round: 0, miter: 1, square: 2, bevel: 3 } as const;
const CAP = { round: 0, butt: 1, square: 2 } as const;
const OVERLAY = { clip: 0, erase: 1, intersect: 2, split: 3 } as const;

// The predicates of relate_worker/relate.mbt, by code.
const RELATIONS = ["intersects", "contains", "within", "covers", "coveredBy", "touches", "crosses", "overlaps", "equals"] as const;

/** A spatial relation as JTS names it (`Geometry.intersects`, `contains`, …, `equals` for `equalsTopo`). */
export type Relation = (typeof RELATIONS)[number];

// Mirrors MEASURE_* in analysis_worker/datasets.mbt.
const MEASURE = { area: 0, length: 1, centroid: 2, bbox: 3 } as const;

/** GeoJSON read into the analysis worker, with its spatial index built on first use. */
export class Dataset {
  #id: number;
  #disposed = false;
  /** The number of features (a GeometryCollection counts once per member). */
  readonly length: number;

  /** @internal */
  constructor(id: number, length: number) {
    this.#id = id;
    this.length = length;
  }

  #call<T>(op: string, args: object = {}): Promise<T> {
    if (this.#disposed) return Promise.reject(new Error("mbmap: analysis: the dataset was disposed"));
    return call<T>(op, { dataset: this.#id, ...args });
  }

  static #idOf(d: Dataset, role: string): number {
    if (d.#disposed) throw new Error(`mbmap: analysis: the ${role} dataset was disposed`);
    return d.#id;
  }

  /** Each feature's area in square meters (0 for points and lines). */
  areas(): Promise<Float64Array> {
    return this.#call("measure", { kind: MEASURE.area });
  }

  /** Each feature's length in meters, rings included (0 for points). */
  lengths(): Promise<Float64Array> {
    return this.#call("measure", { kind: MEASURE.length });
  }

  /** Each feature's centroid as x, y pairs (the mean of its points, as Turf's `centroid`). */
  centroids(): Promise<Float64Array> {
    return this.#call("measure", { kind: MEASURE.centroid });
  }

  /** Each feature's box as min x, min y, max x, max y. */
  bboxes(): Promise<Float64Array> {
    return this.#call("measure", { kind: MEASURE.bbox });
  }

  /** The features whose boxes meet `bbox`. */
  search(bbox: BBox): Promise<Int32Array> {
    return this.#call("search", { bbox });
  }

  /** Up to `k` features nearest to (x, y) by box distance in degrees, nearest first. */
  nearest(x: number, y: number, { k = 1, maxDistance = Infinity }: { k?: number; maxDistance?: number } = {}): Promise<Int32Array> {
    return this.#call("nearest", { x, y, k, maxDistance });
  }

  /** This dataset's point features with a point inside some polygon of `polygons` (boundaries count). */
  pointsWithin(polygons: Dataset): Promise<Int32Array> {
    return call("within", { points: Dataset.#idOf(this, "points"), polygons: Dataset.#idOf(polygons, "polygons") });
  }

  /** Per polygon of this dataset, the points of `points` inside it and their `property` values. */
  async collect(points: Dataset, property: string): Promise<Collected> {
    const v = await call<Float64Array>("collect", { polygons: Dataset.#idOf(this, "polygons"), points: Dataset.#idOf(points, "points"), property });
    const n = v.length / 3;
    const out = { count: new Float64Array(n), numbers: new Float64Array(n), sum: new Float64Array(n), mean: new Float64Array(n) };
    for (let i = 0; i < n; i++) {
      out.count[i] = v[i * 3];
      out.numbers[i] = v[i * 3 + 1];
      out.sum[i] = v[i * 3 + 2];
      out.mean[i] = out.numbers[i] > 0 ? out.sum[i] / out.numbers[i] : NaN;
    }
    return out;
  }

  /** Point counts of a `cols` x `rows` grid over `bbox`, row by row from its south edge. */
  grid(bbox: BBox, cols: number, rows: number): Promise<Int32Array> {
    return this.#call("grid", { bbox, cols, rows });
  }

  /**
   * The pairs of a feature here and a feature of `other` in `relation` (JTS's predicates on
   * longitude and latitude as a plane) or matching a DE-9IM `pattern`, as `[i0, j0, i1, j1, …]`
   * by `i` then `j`. Only features whose boxes meet are tested, so `disjoint` is not offered.
   */
  relate(other: Dataset, relation: Relation | { pattern: string }): Promise<Int32Array> {
    let predicate: number;
    let pattern = 0;
    try {
      predicate = typeof relation === "string" ? RELATIONS.indexOf(relation) : -1;
      if (typeof relation === "string" && predicate < 0) throw new Error(`mbmap: analysis: unknown relation ${relation}`);
      if (typeof relation !== "string") pattern = packPattern(relation.pattern);
      return call("relate", { a: Dataset.#idOf(this, "related"), b: Dataset.#idOf(other, "relating"), predicate, pattern });
    } catch (err) {
      return Promise.reject(err);
    }
  }

  #shapes(shape: string, args: number[] = []): Promise<Dataset> {
    try {
      return this.#geometry("shapes", { dataset: Dataset.#idOf(this, "shaped"), shape, args });
    } catch (err) {
      return Promise.reject(err);
    }
  }

  /**
   * Every feature simplified as Turf's `simplify` does (radial distance, then Douglas-Peucker;
   * `highQuality` skips the first), `tolerance` in degrees; properties kept.
   */
  simplify({ tolerance = 1, highQuality = false }: { tolerance?: number; highQuality?: boolean } = {}): Promise<Dataset> {
    if (!(tolerance >= 0)) return Promise.reject(new Error("mbmap: analysis: invalid tolerance"));
    return this.#shapes("simplify", [tolerance, highQuality ? 1 : 0]);
  }

  /** The convex hull of every vertex here as one polygon (Turf's `convex`), or no feature for fewer than three. */
  convexHull(): Promise<Dataset> {
    return this.#shapes("convex");
  }

  /**
   * A concave hull of every vertex here as one polygon (concaveman's: `concavity` from 1, tight, up;
   * edges shorter than `lengthThreshold` degrees stay), or no feature for fewer than three.
   */
  concaveHull({ concavity = 2, lengthThreshold = 0 }: { concavity?: number; lengthThreshold?: number } = {}): Promise<Dataset> {
    if (!(concavity > 0) || !(lengthThreshold >= 0)) return Promise.reject(new Error("mbmap: analysis: invalid concave hull options"));
    return this.#shapes("concave", [concavity, lengthThreshold]);
  }

  /** The Delaunay triangles of the points here as polygons, in d3-delaunay's order. */
  delaunay(): Promise<Dataset> {
    return this.#shapes("delaunay");
  }

  /**
   * The Voronoi cell of each point here, cut to `bbox`, with that point's properties (d3-delaunay's
   * `cellPolygon`); a point without a cell (a duplicate) keeps its row without geometry.
   */
  voronoi(bbox: BBox): Promise<Dataset> {
    if (!Array.isArray(bbox) || bbox.length !== 4 || !bbox.every(Number.isFinite) || bbox[0] > bbox[2] || bbox[1] > bbox[3]) {
      return Promise.reject(new Error("mbmap: analysis: invalid bbox"));
    }
    return this.#shapes("voronoi", bbox);
  }

  /** Each line cut between the points on it nearest to `start` and `stop`, as Turf's `lineSlice`; properties kept. */
  lineSlice(start: [number, number], stop: [number, number]): Promise<Dataset> {
    if (![...start, ...stop].every(Number.isFinite) || start.length !== 2 || stop.length !== 2) {
      return Promise.reject(new Error("mbmap: analysis: invalid points"));
    }
    return this.#shapes("line_slice", [...start, ...stop]);
  }

  /**
   * Per feature, the point of its lines nearest to (x, y) as Turf's `nearestPointOnLine`: where it is,
   * its distance (`dist`, km), how far along the line (`location`, km), the segment (`index`) and line
   * (`multiFeatureIndex`); null for features without lines.
   */
  async nearestPointOnLine(x: number, y: number): Promise<(NearestOnLine | null)[]> {
    if (!Number.isFinite(x) || !Number.isFinite(y)) throw new Error("mbmap: analysis: invalid point");
    const v = await this.#call<Float64Array>("nearestOnLine", { x, y });
    return Array.from({ length: v.length / 6 }, (_, i) => {
      const [px, py, dist, location, index, multiFeatureIndex] = v.subarray(i * 6, i * 6 + 6);
      return Number.isNaN(px) ? null : { point: [px, py] as [number, number], dist, location, index, multiFeatureIndex };
    });
  }

  #surface(fn: string, args: number[], text = "", numbers: number[] = []): Promise<Dataset> {
    try {
      return this.#geometry("surface", { dataset: Dataset.#idOf(this, "used"), fn, args, text, numbers });
    } catch (err) {
      return Promise.reject(err);
    }
  }

  /**
   * A grid over the box of the points here, each cell with the `property` value interpolated from
   * the points' by inverse distance weighting (Turf's `interpolate`): `gridType` `square` (default),
   * `point`, `hex` or `triangle`, `cellSize` in kilometers, `weight` the power of the distance.
   */
  interpolate(cellSize: number, { gridType = "square", property = "elevation", weight = 1 }: InterpolateOptions = {}): Promise<Dataset> {
    if (!(cellSize > 0) || !(gridType in GRIDS) || !Number.isFinite(weight)) return Promise.reject(new Error("mbmap: analysis: invalid interpolation options"));
    return this.#surface("interpolate", [cellSize, GRIDS[gridType], weight], property);
  }

  /** Lines where the grid of points here (a `pointGrid`) crosses each of `breaks` in `zProperty` (Turf's `isolines`). */
  isolines(breaks: number[], { zProperty = "elevation" }: { zProperty?: string } = {}): Promise<Dataset> {
    if (!Array.isArray(breaks) || !breaks.every(Number.isFinite)) return Promise.reject(new Error("mbmap: analysis: invalid breaks"));
    return this.#surface("isolines", [], zProperty, breaks);
  }

  /** Polygons of the grid of points here between each two of `breaks` in `zProperty` (Turf's `isobands`). */
  isobands(breaks: number[], { zProperty = "elevation" }: { zProperty?: string } = {}): Promise<Dataset> {
    if (!Array.isArray(breaks) || !breaks.every(Number.isFinite)) return Promise.reject(new Error("mbmap: analysis: invalid breaks"));
    return this.#surface("isobands", [], zProperty, breaks);
  }

  /**
   * Contours of the points' kernel density as d3-contour's `contourDensity` draws them, on a `width`
   * x `height` pixel grid over `bbox` (by default the points' box; `cellSize`, `bandwidth` in pixels,
   * `thresholds` how many), each a MultiPolygon with its density `value`; `weight` names a property.
   */
  density({ bbox, width = 960, height = 500, cellSize = 4, bandwidth = 20.4939015319192, thresholds = 20, weight }: DensityOptions = {}): Promise<Dataset> {
    const box = bbox ?? [NaN, NaN, NaN, NaN];
    if (!(width > 0 && height > 0 && cellSize >= 1 && bandwidth >= 0 && Number.isInteger(thresholds) && thresholds >= 0) || box.length !== 4) {
      return Promise.reject(new Error("mbmap: analysis: invalid density options"));
    }
    return this.#surface("density", [...box, width, height, cellSize, bandwidth, thresholds, weight === undefined ? 0 : 1], weight ?? "");
  }

  /**
   * DBSCAN over the points here as Turf's `clustersDbscan` (`maxDistance` in kilometers): per feature its
   * cluster (-1 for none) and whether it is a `core`, `edge` or `noise` point (null for other features).
   */
  async dbscan(maxDistance: number, { minPoints = 3 }: { minPoints?: number } = {}): Promise<{ clusters: Int32Array; kinds: (DbscanKind | null)[] }> {
    if (!(maxDistance >= 0) || !Number.isInteger(minPoints) || minPoints < 1) throw new Error("mbmap: analysis: invalid DBSCAN options");
    const v = await this.#call<Float64Array>("surface", { fn: "dbscan", args: [maxDistance, minPoints] });
    const kinds: (DbscanKind | null)[] = [];
    const clusters = new Int32Array(v.length / 2);
    for (let i = 0; i < clusters.length; i++) {
      clusters[i] = v[i * 2];
      kinds.push(DBSCAN_KINDS[v[i * 2 + 1]] ?? null);
    }
    return { clusters, kinds };
  }

  /**
   * k-means over the points here as Turf's `clustersKmeans` (`k` by default `round(sqrt(n / 2))`): per
   * feature its cluster (-1 for features that are not points) and the centroids as x, y pairs.
   */
  async kmeans(k?: number): Promise<{ clusters: Int32Array; centroids: Float64Array }> {
    if (k !== undefined && !(Number.isInteger(k) && k > 0)) throw new Error("mbmap: analysis: invalid k");
    const v = await this.#call<Float64Array>("surface", { fn: "kmeans", args: [k ?? 0] });
    const n = v[0];
    return { clusters: Int32Array.from(v.subarray(1, 1 + n)), centroids: v.slice(1 + n) };
  }

  /** The DE-9IM matrix of feature `i` here and feature `j` of `other`, as JTS writes it (`"FF2F11212"`). */
  relateMatrix(other: Dataset, i: number, j: number): Promise<string> {
    if (!Number.isInteger(i) || !Number.isInteger(j) || i < 0 || j < 0) return Promise.reject(new Error("mbmap: analysis: invalid feature indices"));
    try {
      return call("relate", { a: Dataset.#idOf(this, "related"), b: Dataset.#idOf(other, "relating"), predicate: 0, pattern: 0, pair: [i, j] });
    } catch (err) {
      return Promise.reject(err);
    }
  }

  async #geometry(op: string, args: object): Promise<Dataset> {
    const { dataset, features } = await call<{ dataset: number; features: number }>(op, args);
    return new Dataset(dataset, features);
  }

  /**
   * Every feature grown by `meters` (shrunk if negative; lines and points only
   * grow) as polygons with its properties; vanished features keep their row
   * without geometry.
   */
  buffer(meters: number, { mode = "geodesic", join = "round", cap = "round", arcTolerance = 0, crs = 3857 }: BufferOptions = {}): Promise<Dataset> {
    if (!(mode in { geodesic: 0, planar: 1 }) || !(join in JOIN) || !(cap in CAP) || !Number.isFinite(meters) || !(arcTolerance >= 0)) {
      return Promise.reject(new Error("mbmap: analysis: invalid buffer options"));
    }
    return crsArg(crs).then((code) => this.#geometry("buffer", {
      dataset: Dataset.#idOf(this, "buffered"), meters, mode: mode === "planar" ? 1 : 0, join: JOIN[join], cap: CAP[cap], arcTolerance, crs: code,
    }));
  }

  /** All polygons merged into one feature without properties (lines and points are left out). */
  dissolve(): Promise<Dataset> {
    return this.#geometry("dissolve", { dataset: Dataset.#idOf(this, "dissolved") });
  }

  /** This dataset's features cut to the area of `other`'s polygons, with their properties. */
  clip(other: Dataset): Promise<Dataset> {
    return this.#geometry("overlay", { a: Dataset.#idOf(this, "clipped"), b: Dataset.#idOf(other, "clipping"), kind: OVERLAY.clip });
  }

  /** This dataset's features without the area of `other`'s polygons, with their properties. */
  erase(other: Dataset): Promise<Dataset> {
    return this.#geometry("overlay", { a: Dataset.#idOf(this, "erased"), b: Dataset.#idOf(other, "erasing"), kind: OVERLAY.erase });
  }

  /**
   * One feature per overlap of a feature here with a polygon of `other`, with
   * the properties of both (`other`'s keys also found here get the suffix `_2`).
   */
  intersect(other: Dataset): Promise<Dataset> {
    return this.#geometry("overlay", { a: Dataset.#idOf(this, "intersected"), b: Dataset.#idOf(other, "intersecting"), kind: OVERLAY.intersect });
  }

  /**
   * Each feature split by `lines`' lines, its pieces as features with its properties: a polygon by
   * the stretches that cross it from edge to edge, a line where they cross it; the rest stays whole.
   */
  split(lines: Dataset): Promise<Dataset> {
    return this.#geometry("overlay", { a: Dataset.#idOf(this, "split"), b: Dataset.#idOf(lines, "splitting"), kind: OVERLAY.split });
  }

  /**
   * The features as one with the first one's properties: polygons united, lines joined end to end,
   * points gathered; rejects when their kinds differ.
   */
  merge(): Promise<Dataset> {
    return this.#geometry("merge", { dataset: Dataset.#idOf(this, "merged") });
  }

  /** The dataset as a GeoJSON FeatureCollection (feature ids are not kept), in `crs` if given. */
  async toGeoJSON({ crs }: { crs?: Crs } = {}): Promise<{ type: "FeatureCollection"; features: object[] }> {
    return this.#call("toGeoJSON", crs === undefined ? {} : { crs: await crsArg(crs) });
  }

  /** Frees the dataset in the worker; later calls on it reject. */
  dispose(): void {
    if (this.#disposed) return;
    this.#disposed = true;
    call("dispose", { dataset: this.#id }).catch(() => {});
  }
}

/** How a DEM's RGB holds elevations: MapLibre's encodings, GSI's, or custom factors. */
export type DemEncoding = "mapbox" | "terrarium" | "gsi" | { redFactor: number; greenFactor: number; blueFactor: number; baseShift?: number };

/** `zoom`: the tile zoom to read (the grid's cells are its pixels); `bounds`: the area to cover (the grid snaps outward to whole tiles). */
export interface DemOptions extends AnalysisOptions {
  zoom: number;
  bounds: BBox;
  encoding?: DemEncoding;
}

// Mirrors `load_dem`'s encodings in analysis_worker/dem.mbt.
function encodingArgs(e: DemEncoding = "mapbox"): number[] {
  if (e === "mapbox") return [0, 0, 0, 0, 0];
  if (e === "terrarium") return [1, 0, 0, 0, 0];
  if (e === "gsi") return [2, 0, 0, 0, 0];
  return [3, e.redFactor, e.greenFactor, e.blueFactor, e.baseShift ?? 0];
}

/** An elevation grid in the analysis worker, row by row from the north. */
export class DemGrid {
  #id: number;
  #disposed = false;
  readonly width: number;
  readonly height: number;
  /** `[west, south, east, north]` of the whole tiles it covers. */
  readonly bounds: BBox;

  /** @internal */
  constructor(id: number, width: number, height: number, bounds: BBox) {
    this.#id = id;
    this.width = width;
    this.height = height;
    this.bounds = bounds;
  }

  #call<T>(op: string, args: object = {}): Promise<T> {
    if (this.#disposed) return Promise.reject(new Error("mbmap: analysis: the grid was disposed"));
    return call<T>(op, { grid: this.#id, ...args });
  }

  /**
   * The cells seen from `observer` (`[lng, lat]`) as gdal_viewshed computes them (`observerHeight`,
   * `targetHeight` above the ground, `maxDistance` meters, 0 for no limit, `curvatureCoeff`): `normal`
   * gives `visibleValue` / `invisibleValue` / `outOfRangeValue` per cell, `dem` and `ground` the height a
   * target there must reach to be seen (above sea level or above the ground). The grid is cut to
   * `maxDistance`; a DEM grid is measured in ground meters at its middle latitude.
   */
  async viewshed(observer: [number, number], options: ViewshedOptions = {}): Promise<ViewshedResult> {
    const { observerHeight = 2, targetHeight = 0, maxDistance = 0, curvatureCoeff = CURVATURE_COEFF, mode = "normal", visibleValue = 255, invisibleValue = 0, outOfRangeValue = 0 } = options;
    if (!(mode in VIEWSHED_MODES)) throw new Error(`mbmap: analysis: unknown viewshed mode ${mode}`);
    return this.#call("viewshed", {
      observer,
      options: { observerHeight, targetHeight, maxDistance, curvatureCoeff, mode: VIEWSHED_MODES[mode], visible: visibleValue, invisible: invisibleValue, outOfRange: outOfRangeValue },
    });
  }

  /**
   * Whether `to` can be seen from `from` (both `[lng, lat]`) over the grid's elevations sampled bilinearly
   * along the line (`samples`, by default one per cell), with gdal_viewshed's curvature correction and
   * distances on Turf's sphere; `blockedAt` is the first sample that hides it.
   */
  async lineOfSight(from: [number, number], to: [number, number], { observerHeight = 2, targetHeight = 0, curvatureCoeff = CURVATURE_COEFF, samples }: LineOfSightOptions = {}): Promise<{ visible: boolean; blockedAt: [number, number] | null }> {
    const cell = groundDistance([this.bounds[0], this.bounds[1]], [this.bounds[2], this.bounds[1]]) / this.width;
    const n = samples ?? Math.min(MAX_SIGHT_SAMPLES, Math.max(2, Math.ceil(groundDistance(from, to) / cell) + 1));
    if (!Number.isInteger(n) || n < 2 || n > MAX_SIGHT_SAMPLES) throw new Error("mbmap: analysis: invalid number of samples");
    const points = Array.from({ length: n }, (_, i): [number, number] => [from[0] + ((to[0] - from[0]) * i) / (n - 1), from[1] + ((to[1] - from[1]) * i) / (n - 1)]);
    const heights = await this.sample(points);
    const s = sight(heights, points.map((p) => groundDistance(from, p)), observerHeight, targetHeight, curvatureCoeff);
    return { visible: s.visible, blockedAt: s.blockedAt === null ? null : points[s.blockedAt] };
  }

  /** Elevations in meters; NaN where the DEM has no data. */
  elevations(): Promise<Float64Array> {
    return this.#call("gridValues", { kind: 0 });
  }

  /** Slopes in degrees (gdaldem's Horn method). */
  slope(): Promise<Float64Array> {
    return this.#call("gridValues", { kind: 1 });
  }

  /** Aspects in degrees clockwise from north, facing downhill; NaN where flat. */
  aspect(): Promise<Float64Array> {
    return this.#call("gridValues", { kind: 2 });
  }

  /**
   * The elevation in meters at each `[lng, lat]`, interpolated bilinearly between cell centers as
   * GDAL's `-r bilinear` does; NaN off the grid or next to a cell without data.
   */
  sample(positions: ArrayLike<[number, number]>): Promise<Float64Array> {
    const coords = new Float64Array(positions.length * 2);
    for (let i = 0; i < positions.length; i++) coords.set(positions[i], i * 2);
    return this.#call("gridSample", { coords: coords.buffer });
  }

  /** Shades from 1 to 255 under light from `azimuth` degrees at `altitude` degrees (gdaldem's hillshade). */
  hillshade({ azimuth = 315, altitude = 45, zFactor = 1 }: { azimuth?: number; altitude?: number; zFactor?: number } = {}): Promise<Uint8Array> {
    return this.#call("gridHillshade", { azimuth, altitude, zFactor });
  }

  dispose(): void {
    if (this.#disposed) return;
    this.#disposed = true;
    call("dispose", { dataset: this.#id }).catch(() => {});
  }
}

/** A raster as mbmap/data's `readRaster` gives it, only what `loadGrid` reads: `bands` (rows from the north),
 * `bbox` and `resolution` in `crs` (an EPSG code, null for EPSG:4326), `noData`, `pixelIsPoint`. */
export interface GridRaster {
  width: number;
  height: number;
  bands: ArrayLike<number>[];
  bbox: BBox | null;
  resolution: [number, number] | null;
  crs: number | null;
  noData: number | null;
  pixelIsPoint?: boolean;
}

/** Band `band` (default 0) of `raster` as an elevation grid, `noData` cells empty, cells the resolution divided by
 * `scale` (gdaldem's `-s`), PixelIsPoint as GDAL reads it; `sample` takes longitude and latitude (npm/README.md). */
export async function loadGrid(raster: GridRaster, options: AnalysisOptions & { band?: number; scale?: number } = {}): Promise<DemGrid> {
  const { band = 0, scale = 1 } = options;
  const { width, height, bands, bbox, resolution, crs, noData } = raster ?? ({} as GridRaster);
  const values = bands?.[band];
  if (!values || values.length !== width * height) throw new Error("mbmap: analysis: invalid raster or band");
  if (!(Number.isFinite(scale) && scale > 0)) throw new Error("mbmap: analysis: invalid scale");
  if (!Array.isArray(resolution) || !resolution.every((r) => Number.isFinite(r) && r !== 0) || !Array.isArray(bbox)) throw new Error("mbmap: analysis: a raster without geo tags (resolution and bbox)");
  const f64 = Float64Array.from(values, (v) => (v === noData ? NaN : v));
  const [rx, ry] = resolution;
  const half = raster.pixelIsPoint ? 0.5 : 0;
  const origin = [(rx > 0 ? bbox[0] : bbox[2]) - half * rx, (ry < 0 ? bbox[3] : bbox[1]) - half * ry];
  start(options);
  const r = await call<{ grid: number; width: number; height: number; bounds: BBox }>("loadGrid", {
    values: f64.buffer, width, height, res: [Math.abs(rx) / scale, Math.abs(ry) / scale], origin, step: [rx, ry], crs: crs ?? 4326,
  }, [f64.buffer]);
  return new DemGrid(r.grid, r.width, r.height, r.bounds);
}

/** Mosaics the DEM tiles of `tiles` (a `{z}/{x}/{y}` http(s) template) covering `bounds` into a grid. */
export async function loadDem(tiles: string, options: DemOptions): Promise<DemGrid> {
  start(options);
  const template = resolveTemplate(tiles, document.baseURI, "analysis: DEM tiles");
  const r = await call<{ grid: number; width: number; height: number; bounds: BBox }>("loadDem", {
    url: template, z: options.zoom, bounds: options.bounds, encoding: encodingArgs(options.encoding),
  });
  return new DemGrid(r.grid, r.width, r.height, r.bounds);
}

/**
 * The elevations at `positions` from the DEM tiles of `tiles` (`encoding`, up to `maxZoom`, default
 * 14): the tiles around them at the deepest zoom that fits one grid, sampled as `DemGrid.sample`
 * (a tile the server does not have counts as 0 m, as in `loadDem`).
 */
export async function sampleDem(
  tiles: string,
  positions: ArrayLike<[number, number]>,
  options: AnalysisOptions & { encoding?: DemEncoding; maxZoom?: number; tileSize?: number } = {},
): Promise<Float64Array> {
  if (positions.length === 0) return new Float64Array(0);
  const bounds: BBox = [Infinity, Infinity, -Infinity, -Infinity];
  for (let i = 0; i < positions.length; i++) {
    const [lng, lat] = positions[i];
    bounds[0] = Math.min(bounds[0], lng);
    bounds[1] = Math.min(bounds[1], lat);
    bounds[2] = Math.max(bounds[2], lng);
    bounds[3] = Math.max(bounds[3], lat);
  }
  if (!bounds.every(Number.isFinite)) throw new Error("mbmap: analysis: positions must be finite [lng, lat] pairs");
  const zoom = demZoom(bounds, options.maxZoom ?? 14, options.tileSize);
  const grid = await loadDem(tiles, { ...options, zoom, bounds });
  try {
    return await grid.sample(positions);
  } finally {
    grid.dispose();
  }
}

type Feature = { type?: string; properties?: Record<string, unknown> | null; geometry: { type: string; coordinates: unknown } };

/** `features` loaded, `op` run on the dataset, the result as GeoJSON features; every dataset disposed. */
async function onFeatures(features: Feature[], op: (d: Dataset) => Promise<Dataset>, options: AnalysisOptions): Promise<Feature[]> {
  const d = await load({ type: "FeatureCollection", features: features.map((f) => ({ type: "Feature", properties: f.properties ?? {}, geometry: f.geometry })) }, options);
  try {
    const r = await op(d);
    try {
      return (await r.toGeoJSON()).features as Feature[];
    } finally {
      r.dispose();
    }
  } finally {
    d.dispose();
  }
}

/** `features` split by `line` (a LineString), as `Dataset.split`: what mbmap/draw's `geometry.split` takes. */
export async function splitFeatures(features: Feature[], line: Feature["geometry"], options: AnalysisOptions = {}): Promise<Feature[]> {
  const cut = await load({ type: "Feature", properties: {}, geometry: line }, options);
  try {
    return await onFeatures(features, (d) => d.split(cut), options);
  } finally {
    cut.dispose();
  }
}

/** `features` as one, as `Dataset.merge`: what mbmap/draw's `geometry.merge` takes. */
export async function mergeFeatures(features: Feature[], options: AnalysisOptions = {}): Promise<Feature> {
  return (await onFeatures(features, (d) => d.merge(), options))[0];
}

/** Rows in @geom.Table's byte form, as mbmap/data's `DataTable` gives them. */
export interface TableSource {
  tableBytes(): ArrayBuffer;
}

/**
 * Reads data into the analysis worker: GeoJSON as an object, its UTF-8 bytes, or an http(s) URL
 * (resolved against the page, fetched without credentials), or a table read by mbmap/data.
 */
export async function load(data: unknown, options: LoadOptions = {}): Promise<Dataset> {
  const crs = options.crs === undefined ? undefined : await crsArg(options.crs);
  start(options);
  let args: object;
  let transfer: Transferable[] = [];
  if (typeof data === "string") {
    args = { url: httpUrl(data, document.baseURI, "analysis: data") };
  } else if (typeof (data as TableSource | null)?.tableBytes === "function") {
    const table = (data as TableSource).tableBytes();
    if (!(table instanceof ArrayBuffer)) throw new Error("mbmap: analysis: tableBytes() must give an ArrayBuffer");
    args = { table };
    transfer = [table];
  } else {
    // Copied, so the caller's buffer stays usable after the transfer.
    const bytes =
      data instanceof ArrayBuffer ? data.slice(0) :
      ArrayBuffer.isView(data) ? new Uint8Array(data.buffer, data.byteOffset, data.byteLength).slice().buffer :
      new TextEncoder().encode(JSON.stringify(data)).buffer;
    args = { bytes };
    transfer = [bytes];
  }
  const { dataset, features } = await call<{ dataset: number; features: number }>("load", { ...args, crs }, transfer);
  return new Dataset(dataset, features);
}

/**
 * x, y pairs taken from `from` to `to` (NaN where a projection cannot reach),
 * in the analysis worker; the first call loads the geometry module.
 */
export async function transform(coords: ArrayLike<number>, from: Crs, to: Crs, options: AnalysisOptions = {}): Promise<Float64Array> {
  const codes = { from: await crsArg(from), to: await crsArg(to) };
  start(options);
  const buffer = Float64Array.from(coords).buffer;
  if (buffer.byteLength % 16 !== 0) throw new Error("mbmap: analysis: coordinates must come in x, y pairs");
  return call<Float64Array>("transform", { coords: buffer, ...codes }, [buffer]);
}

/** Great-circle distance in meters between two `[lng, lat]` points; mirrors `@analysis.distance`. */
export function distance(from: [number, number], to: [number, number]): number {
  const rad = (d: number) => ((d % 360) * Math.PI) / 180;
  const sLat = Math.sin(rad(to[1] - from[1]) / 2);
  const sLng = Math.sin(rad(to[0] - from[0]) / 2);
  const a = sLat * sLat + sLng * sLng * Math.cos(rad(from[1])) * Math.cos(rad(to[1]));
  return 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)) * 6371008.8;
}

/** Stops the analysis worker; datasets are lost and pending calls reject. */
export function terminate(): void {
  client.terminate();
}
