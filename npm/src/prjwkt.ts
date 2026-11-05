// A .prj (Esri or OGC WKT1) read as wkt-parser 1.6.0 and proj4js 2.22.0 (lib/Proj.js, parseCode.js)
// read one, MIT License, Copyright (c) 2014 Mike Adair et al.; see NOTICE. Loaded by the data
// worker on the first .prj; imports only the datum table of projstring.ts.
import { DATUMS, lookup } from "./projstring.ts";

const D2R = 0.01745329251994329577;
// `@proj.DEFINITION_SLOTS` (proj/encoding.mbt).
const SLOTS = 34;
// Longest WKT read and most items in one of its nodes: EPSG's definitions take a few KB and some 20 items.
const MAX_TEXT = 65536;
const MAX_ITEMS = 1024;

// proj4js's projection names (each module's `names`), by `proj/encoding.mbt` `methods` index.
const NAMES = [
  "longlat,identity,lonlat,latlon,latlong", "mercator,popular visualisation pseudo mercator,mercator_1sp,mercator_auxiliary_sphere,mercator_variant_a,merc",
  "extended_transverse_mercator,extended transverse mercator,etmerc,transverse_mercator,transverse mercator,gauss kruger,gauss_kruger,tmerc",
  "universal transverse mercator system,utm",
  "lambert tangential conformal conic projection,lambert_conformal_conic,lambert_conformal_conic_1sp,lambert_conformal_conic_2sp,lcc,lambert conic conformal (1sp),lambert conic conformal (2sp)",
  "albers_conic_equal_area,albers_equal_area,albers,aea", "azimuthal_equidistant,aeqd",
  "stere,stereographic_south_pole,polar_stereographic_variant_a,polar_stereographic_variant_b,polar_stereographic",
  "stereographic_north_pole,oblique_stereographic,sterea,oblique stereographic alternative,double_stereographic",
  "cassini,cassini_soldner,cass", "lambert azimuthal equal area,lambert_azimuthal_equal_area,laea",
  "equirectangular,equidistant_cylindrical,equidistant_cylindrical_spherical,eqc", "equidistant_conic,eqdc", "sinusoidal,sinu",
  "eckert_vi,eck6", "mollweide,moll", "robinson,robin", "cea", "miller_cylindrical,mill", "polyconic,american_polyconic,poly",
  "hotine_oblique_mercator,hotine oblique mercator,hotine_oblique_mercator_variant_a,hotine_oblique_mercator_variant_b,hotine_oblique_mercator_azimuth_natural_origin,hotine_oblique_mercator_two_point_natural_origin,hotine_oblique_mercator_azimuth_center,oblique_mercator,omerc",
  "somerc", "krovak,krovak modified,krovak (north orientated),krovak modified (north orientated),krovak", "ortho", "gnom",
  "eqearth,equal earth,equal_earth", "bonne,bonne (werner lat_1=90)",
].map((names) => names.split(","));

// proj4js's `projections.get`: the name in lower case, else with runs of `-`, `(`, `)` and spaces as `_`.
function methodOf(name: string): number {
  const n = name.toLowerCase();
  const normal = n.replace(/[-()\s]+/g, " ").trim().replace(/ /g, "_");
  return NAMES.findIndex((names) => names.includes(n) || names.includes(normal));
}

type Node = (string | number | Node)[];

function fail(message: string): never {
  throw new Error(`.prj: ${message}`);
}

// The WKT as nested lists [keyword, ...values], as wkt-parser's `parser` makes them.
function parse(text: string): Node {
  const re = /\s*(?:([A-Za-z][A-Za-z0-9_]*)\s*([[(])?|"((?:[^"]|"")*)"|([-+.\d][-+.\dEe]*)|([\])])|,)/y;
  const stack: Node[] = [];
  let root: Node | null = null;
  let at = 0;
  for (;;) {
    re.lastIndex = at;
    const m = re.exec(text);
    if (!m) break;
    at = re.lastIndex;
    const top = stack[stack.length - 1];
    if (m[2] !== undefined) {
      const node: Node = [m[1]];
      if (top) top.push(node);
      else if (root) fail("text after the WKT");
      else root = node;
      stack.push(node);
    } else if (!top) fail("expected a keyword");
    else if (m[1] !== undefined) top.push(m[1]);
    else if (m[3] !== undefined) top.push(m[3].replace(/""/g, '"'));
    else if (m[4] !== undefined) top.push(parseFloat(m[4]));
    else if (m[5] !== undefined) stack.pop();
    if (stack.length > 32) fail("nested too deep");
    if (top && top.length > MAX_ITEMS) fail("a node with too many items");
  }
  if (!root || stack.length > 0 || text.slice(at).trim() !== "") fail("not WKT");
  return root;
}

type Obj = Record<string, any>;

// Objects without a prototype, so that a WKT key like `__proto__` is a key like any other.
const obj = (fields: Obj = {}): Obj => Object.assign(Object.create(null), fields);

// wkt-parser's `sExpr`: a node added to `into` under its keyword. Where it calls itself on the rest
// of a node (each item the key of the next) this loops, so that a wide node takes no stack.
function sExpr(node: Node | string | number, into: Obj): void {
  if (!Array.isArray(node)) {
    into[node] = true;
    return;
  }
  const v = node.slice();
  for (;;) {
    let key = v.shift() as string;
    if (key === "PARAMETER") key = v.shift() as string;
    if (v.length === 1) {
      if (Array.isArray(v[0])) {
        into[key] = obj();
        sExpr(v[0], into[key]);
      } else into[key] = v[0];
      return;
    }
    if (!v.length) {
      into[key] = true;
      return;
    }
    if (key === "TOWGS84") {
      into[key] = v;
      return;
    }
    if (key === "AXIS") {
      (into[key] ??= []).push(v);
      return;
    }
    switch (key) {
      case "UNIT":
      case "PRIMEM":
      case "VERT_DATUM":
        into[key] = obj({ name: String(v[0]).toLowerCase(), convert: v[1] });
        if (v.length === 3) sExpr(v[2], into[key]);
        return;
      case "SPHEROID":
      case "ELLIPSOID":
        into[key] = obj({ name: v[0], a: v[1], rf: v[2] });
        if (v.length === 4) sExpr(v[3], into[key]);
        return;
      case "DATUM":
      case "VERT_CS":
      case "COMPD_CS":
      case "FITTED_CS":
      case "PROJCS":
      case "GEOGCS":
      case "GEOCCS":
      case "LOCAL_CS":
        into[key] = v.slice(1).reduce((o: Obj, item) => (sExpr(item, o), o), obj({ name: v[0] }));
        if (key !== "DATUM" && key !== "VERT_CS") into[key].type = key;
        return;
      default:
        into[key] = obj();
        if (!v.some((item) => !Array.isArray(item))) {
          for (const item of v) sExpr(item, into[key]);
          return;
        }
        into = into[key];
    }
  }
}

// The renames of wkt-parser's `cleanWKT`, in its order: [to, from, convert?].
const RENAMES: [string, string, number?][] = [
  ["standard_parallel_1", "Standard_Parallel_1"], ["standard_parallel_1", "Latitude of 1st standard parallel"],
  ["standard_parallel_2", "Standard_Parallel_2"], ["standard_parallel_2", "Latitude of 2nd standard parallel"],
  ["false_easting", "False_Easting"], ["false_easting", "False easting"], ["false_northing", "False_Northing"],
  ["false_northing", "False northing"], ["false_northing", "Northing at false origin"],
  ["central_meridian", "Central_Meridian"], ["central_meridian", "Longitude of natural origin"],
  ["central_meridian", "Longitude of false origin"], ["latitude_of_origin", "Latitude_Of_Origin"],
  ["latitude_of_origin", "Central_Parallel"], ["latitude_of_origin", "Latitude of natural origin"],
  ["latitude_of_origin", "Latitude of false origin"], ["scale_factor", "Scale_Factor"], ["k0", "scale_factor"],
  ["latitude_of_center", "Latitude_Of_Center"], ["latitude_of_center", "Latitude_of_center"],
  ["lat0", "latitude_of_center", 1], ["longitude_of_center", "Longitude_Of_Center"],
  ["longitude_of_center", "Longitude_of_center"], ["longc", "longitude_of_center", 1], ["x0", "false_easting", 2],
  ["y0", "false_northing", 2], ["long0", "central_meridian", 1], ["lat0", "latitude_of_origin", 1],
  ["lat0", "standard_parallel_1", 1], ["lat1", "standard_parallel_1", 1], ["lat2", "standard_parallel_2", 1],
  ["azimuth", "Azimuth"], ["alpha", "azimuth", 1],
];

/**
 * The CRS a .prj names: `code` its EPSG code (from the root's AUTHORITY, or 3857 for Web Mercator), and
 * `definition` as docs/FORMATS.md "CRS definition" encodes it (absent for a projection proj.wasm lacks).
 * Axis order is not read: shapefiles keep x as easting.
 */
export function parsePrj(text: string): { code?: number; definition?: Float64Array } {
  if (text.length > MAX_TEXT) fail(`WKT over ${MAX_TEXT} characters`);
  if (/PROJCRS|GEOGCRS|BOUNDCRS|VERTCRS|LENGTHUNIT|ANGLEUNIT|SCALEUNIT/i.test(text)) fail("WKT2 is not supported");
  const tree = parse(text);
  const type = tree[0];
  if (type !== "PROJCS" && type !== "GEOGCS") fail(`unsupported CRS type ${String(type)}`);
  const holder = obj();
  sExpr(tree, holder);
  const w = holder[type as string];
  const authority = w.AUTHORITY && Object.keys(w.AUTHORITY)[0];
  let code = authority?.toUpperCase() === "EPSG" ? Number(w.AUTHORITY[authority]) : undefined;
  const projName = type === "GEOGCS" ? "longlat" : typeof w.PROJECTION === "object" ? Object.keys(w.PROJECTION)[0] : String(w.PROJECTION);
  if ([3857, 900913, 3785, 102113].includes(code!) || projName === "Mercator_Auxiliary_Sphere") code = 3857;
  if (code !== undefined && !Number.isInteger(code)) code = undefined;
  const method = methodOf(projName);
  if (method < 0) {
    if (code !== undefined) return { code };
    fail(`unsupported projection ${projName}`);
  }
  const geogcs = type === "GEOGCS" ? w : w.GEOGCS ?? obj();
  const units = w.UNIT?.convert;
  const toMeter = type === "PROJCS" && units ? units : undefined;
  for (const [to, from, convert] of RENAMES) {
    if (!(to in w) && from in w) w[to] = convert === 1 ? w[from] * D2R : convert === 2 ? w[from] * (toMeter || 1) : w[from];
  }
  const norm = (projName || "").toLowerCase().replace(/_/g, " ");
  if (w.long0 === undefined && w.longc !== undefined) w.long0 = w.longc;
  if (!w.lat_ts && w.lat1 && (norm === "stereographic south pole" || norm === "polar stereographic (variant b)")) {
    w.lat0 = (w.lat1 > 0 ? 90 : -90) * D2R;
    w.lat_ts = w.lat1;
    delete w.lat1;
  } else if (!w.lat_ts && w.lat0 && (norm === "polar stereographic" || norm === "polar stereographic (variant a)")) {
    w.lat_ts = w.lat0;
    w.lat0 = (w.lat0 > 0 ? 90 : -90) * D2R;
    delete w.lat1;
  }
  let datumCode = String(geogcs.DATUM?.name ?? geogcs.name ?? "").toLowerCase();
  if (datumCode.startsWith("d_")) datumCode = datumCode.slice(2);
  if (datumCode === "new_zealand_1949") datumCode = "nzgd49";
  if (datumCode === "wgs_1984" || datumCode === "world_geodetic_system_1984") datumCode = "wgs84";
  if (datumCode === "belge_1972") datumCode = "rnb72";
  if (datumCode.includes("osgb_1936")) datumCode = "osgb36";
  if (datumCode.includes("osni_1952")) datumCode = "osni52";
  if (datumCode.includes("tm65") || datumCode.includes("geodetic_datum_of_1965")) datumCode = "ire65";
  if (datumCode === "ch1903+") datumCode = "ch1903";
  if (datumCode.includes("israel")) datumCode = "isr93";
  const spheroid = geogcs.DATUM?.SPHEROID;
  let towgs84: number[] | undefined = geogcs.DATUM?.TOWGS84?.map(Number);
  towgs84 ??= lookup(DATUMS, datumCode)?.[0].split(",").map(Number);
  if (towgs84 && towgs84.length !== 3 && towgs84.length !== 7) fail("TOWGS84 takes 3 or 7 values");
  const a = Number(spheroid?.a ?? 6378137);
  const rf = spheroid ? parseFloat(spheroid.rf) : 298.257223563;
  const s = new Float64Array(SLOTS).fill(NaN);
  s[0] = method;
  s[1] = a;
  s[2] = rf === 0 ? a : (1 - 1 / rf) * a;
  if (Math.abs(a - s[2]) < 1e-10) s[2] = a;
  s[3] = 0;
  s[4] = towgs84?.length ?? 0;
  towgs84?.forEach((v, i) => (s[5 + i] = v));
  s[12] = 0;
  s[13] = toMeter ?? NaN;
  s[14] = geogcs.PRIMEM?.convert ? geogcs.PRIMEM.convert * D2R : 0;
  const keys = ["lat0", "lat1", "lat2", "lat_ts", "long0", "", "", "alpha", "", "longc", "x0", "y0", "k0"];
  keys.forEach((k, i) => {
    if (k && typeof w[k] === "number") s[16 + i] = w[k];
  });
  if (typeof w.rectified_grid_angle === "number") s[24] = w.rectified_grid_angle * D2R;
  s[30] = s[31] = s[32] = s[33] = 0;
  return code === undefined ? { definition: s } : { code, definition: s };
}
