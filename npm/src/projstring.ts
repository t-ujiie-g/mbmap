// PROJ strings for `mbmap/analysis`, parsed as proj4js 2.22.0 reads them (lib/projString.js, lib/Proj.js,
// lib/deriveConstants.js and the tables of lib/constants/; MIT License,
// Copyright (c) 2014, Mike Adair, Richard Greenwood, Didier Richard, Stephen
// Irons, Olivier Terral, Calvin Metcalf; see NOTICE). Loaded by
// `mbmap/analysis` on the first PROJ string; import-free, so that `npm test`
// can load it.

const D2R = 0.01745329251994329577;
// `@proj.DEFINITION_SLOTS` (proj/encoding.mbt).
const SLOTS = 34;

// The order of `proj/encoding.mbt` `methods`.
const METHODS = ["longlat", "merc", "tmerc", "utm", "lcc", "aea", "aeqd", "stere", "sterea", "cass", "laea", "eqc", "eqdc",
  "sinu", "eck6", "moll", "robin", "cea", "mill", "poly", "omerc", "somerc", "krovak", "ortho", "gnom", "eqearth", "bonne"];
const ALIASES: Record<string, string> = { lonlat: "longlat", latlon: "longlat", latlong: "longlat", etmerc: "tmerc" };

// a, rf, b (0 where the table gives the other).
const ELLIPSOIDS: Record<string, [number, number, number]> = {
  MERIT: [6378137, 298.257, 0], SGS85: [6378136, 298.257, 0], GRS80: [6378137, 298.257222101, 0],
  IAU76: [6378140, 298.257, 0], airy: [6377563.396, 0, 6356256.91], APL4: [6378137, 298.25, 0],
  NWL9D: [6378145, 298.25, 0], mod_airy: [6377340.189, 0, 6356034.446], andrae: [6377104.43, 300, 0],
  aust_SA: [6378160, 298.25, 0], GRS67: [6378160, 298.247167427, 0], bessel: [6377397.155, 299.1528128, 0],
  bess_nam: [6377483.865, 299.1528128, 0], clrk66: [6378206.4, 0, 6356583.8], clrk80: [6378249.145, 293.4663, 0],
  clrk80ign: [6378249.2, 293.4660213, 6356515], clrk58: [6378293.645208759, 294.2606763692654, 0],
  CPM: [6375738.7, 334.29, 0], delmbr: [6376428, 311.5, 0], engelis: [6378136.05, 298.2566, 0],
  evrst30: [6377276.345, 300.8017, 0], evrst48: [6377304.063, 300.8017, 0], evrst56: [6377301.243, 300.8017, 0],
  evrst69: [6377295.664, 300.8017, 0], evrstSS: [6377298.556, 300.8017, 0], fschr60: [6378166, 298.3, 0],
  fschr60m: [6378155, 298.3, 0], fschr68: [6378150, 298.3, 0], helmert: [6378200, 298.3, 0],
  hough: [6378270, 297, 0], intl: [6378388, 297, 0], kaula: [6378163, 298.24, 0], lerch: [6378139, 298.257, 0],
  mprts: [6397300, 191, 0], new_intl: [6378157.5, 0, 6356772.2], plessis: [6376523, 0, 6355863],
  krass: [6378245, 298.3, 0], SEasia: [6378155, 0, 6356773.3205], walbeck: [6376896, 0, 6355834.8467],
  WGS60: [6378165, 298.3, 0], WGS66: [6378145, 298.25, 0], WGS7: [6378135, 298.26, 0],
  WGS84: [6378137, 298.257223563, 0], sphere: [6370997, 0, 6370997],
};

// towgs84, ellipsoid (nad27 needs grids, which are not supported).
const DATUMS: Record<string, [string, string]> = {
  wgs84: ["0,0,0", "WGS84"], ch1903: ["674.374,15.056,405.346", "bessel"], ggrs87: ["-199.87,74.79,246.62", "GRS80"],
  nad83: ["0,0,0", "GRS80"], potsdam: ["598.1,73.7,418.2,0.202,0.045,-2.455,6.7", "bessel"],
  carthage: ["-263.0,6.0,431.0", "clrk80ign"], hermannskogel: ["577.326,90.129,463.919,5.137,1.474,5.297,2.4232", "bessel"],
  mgi: ["577.326,90.129,463.919,5.137,1.474,5.297,2.4232", "bessel"],
  osni52: ["482.530,-130.596,564.557,-1.042,-0.214,-0.631,8.15", "airy"],
  ire65: ["482.530,-130.596,564.557,-1.042,-0.214,-0.631,8.15", "mod_airy"], rassadiran: ["-133.63,-157.5,-158.62", "intl"],
  nzgd49: ["59.47,-5.04,187.44,0.47,-0.1,1.024,-4.5993", "intl"],
  osgb36: ["446.448,-125.157,542.060,0.1502,0.2470,0.8421,-20.4894", "airy"], s_jtsk: ["589,76,480", "bessel"],
  beduaram: ["-106,-87,188", "clrk80"], gunung_segara: ["-403,684,41", "bessel"],
  rnb72: ["106.869,-52.2978,103.724,-0.33657,0.456955,-1.84218,1", "intl"],
};

const UNITS: Record<string, number> = {
  mm: 0.001, cm: 0.01, ft: 0.3048, "us-ft": 1200 / 3937, fath: 1.8288, kmi: 1852, "us-ch": 20.1168402336805,
  "us-mi": 1609.34721869444, km: 1000, "ind-ft": 0.30479841, "ind-yd": 0.91439523, mi: 1609.344, yd: 0.9144,
  ch: 20.1168, link: 0.201168, dm: 0.1, in: 0.0254, "ind-ch": 20.11669506, "us-in": 0.025400050800101,
  "us-yd": 0.914401828803658,
};

const MERIDIANS: Record<string, number> = {
  greenwich: 0, lisbon: -9.131906111111, paris: 2.337229166667, bogota: -74.080916666667, madrid: -3.687938888889,
  rome: 12.452333333333, bern: 7.439583333333, jakarta: 106.807719444444, ferro: -17.666666666667,
  brussels: 4.367975, stockholm: 18.058277777778, athens: 23.7163375, oslo: 10.722916666667,
};

/** proj4js's `match`: exact, else ignoring case, spaces, `_`, `-`, `/` and parentheses. */
function lookup<T>(table: Record<string, T>, key: string): T | undefined {
  if (Object.hasOwn(table, key)) return table[key];
  const norm = (k: string) => k.toLowerCase().replace(/[\s_\-/()]/g, "");
  const found = Object.keys(table).find((k) => norm(k) === norm(key));
  return found === undefined ? undefined : table[found];
}

function fail(message: string): never {
  throw new Error(`mbmap: analysis: ${message}`);
}

function number(key: string, v: string | true): number {
  const n = v === true ? NaN : Number(v);
  if (!Number.isFinite(n)) fail(`+${key}: not a number: ${String(v)}`);
  return n;
}

/** `text` (a PROJ string) as docs/FORMATS.md "CRS definition" encodes it. */
export function parseProjString(text: string): Float64Array {
  const params = new Map<string, string | true>();
  for (const part of text.split("+")) {
    const token = part.trim();
    if (!token) continue;
    const at = token.indexOf("=");
    if (at < 0) params.set(token.toLowerCase(), true);
    else params.set(token.slice(0, at).toLowerCase(), token.slice(at + 1));
  }
  const s = new Float64Array(SLOTS).fill(NaN);
  const get = (k: string) => params.get(k);
  const angle = (k: string) => (params.has(k) ? number(k, get(k)!) * D2R : NaN);
  const real = (k: string) => (params.has(k) ? number(k, get(k)!) : NaN);
  const flag = (k: string) => (params.has(k) ? 1 : 0);

  const name = String(get("proj") ?? "");
  const method = METHODS.indexOf(ALIASES[name] ?? name);
  if (method < 0) fail(`unsupported projection: +proj=${name}`);
  s[0] = method;

  let towgs84: number[] | undefined;
  const t = get("towgs84");
  if (t !== undefined) towgs84 = String(t).split(",").map((v) => number("towgs84", v));
  let ellps = String(get("ellps") ?? "wgs84");
  const nadgrids = get("nadgrids");
  let datumCode = nadgrids === "@null" ? "none" : get("datum");
  if (nadgrids !== undefined && nadgrids !== "@null") fail("+nadgrids: grid shifts are not supported");
  if (typeof datumCode === "string" && datumCode !== "WGS84") datumCode = datumCode.toLowerCase();
  if (typeof datumCode === "string" && datumCode !== "none") {
    if (datumCode === "nad27") fail("+datum=nad27 needs grid shifts, which are not supported");
    const datum = lookup(DATUMS, datumCode);
    if (datum) {
      towgs84 ??= datum[0].split(",").map(Number);
      ellps = datum[1];
    }
  }
  if (towgs84 && towgs84.length !== 3 && towgs84.length !== 7) fail("+towgs84 takes 3 or 7 values");

  let a = real("a");
  let b = real("b");
  let rf = real("rf");
  if (params.has("r")) a = b = real("r");
  if (Number.isNaN(a)) {
    const e = lookup(ELLIPSOIDS, ellps) ?? ELLIPSOIDS.WGS84;
    [a, rf, b] = [e[0], e[1] || NaN, e[2] || NaN];
  }
  if (!Number.isNaN(rf) && Number.isNaN(b)) b = rf === 0 ? a : (1 - 1 / rf) * a;
  if (Number.isNaN(b)) b = a;
  s[1] = a;
  s[2] = b;
  s[3] = flag("r_a");
  s[4] = towgs84 ? towgs84.length : 0;
  towgs84?.forEach((v, i) => (s[5 + i] = v));
  s[12] = datumCode === "WGS84" ? 1 : 0;

  const units = get("units");
  s[13] = params.has("to_meter") ? real("to_meter") : typeof units === "string" ? (lookup(UNITS, units) ?? NaN) : NaN;
  const pm = get("pm");
  s[14] = params.has("from_greenwich")
    ? angle("from_greenwich")
    : pm === undefined ? 0 : (lookup(MERIDIANS, String(pm)) ?? number("pm", pm)) * D2R;
  s[15] = angle("lon_wrap");
  s[16] = angle("lat_0");
  s[17] = angle("lat_1");
  s[18] = angle("lat_2");
  s[19] = angle("lat_ts");
  s[20] = angle("lon_0");
  s[21] = angle("lon_1");
  s[22] = angle("lon_2");
  s[23] = angle("alpha");
  s[24] = angle("gamma");
  s[25] = angle("lonc");
  s[26] = real("x_0");
  s[27] = real("y_0");
  s[28] = params.has("k_0") ? real("k_0") : real("k");
  s[29] = params.has("zone") ? Number.parseInt(String(get("zone")), 10) : NaN;
  if (params.has("zone") && !(s[29] >= 1 && s[29] <= 60)) fail(`+zone: not a UTM zone: ${String(get("zone"))}`);
  s[30] = flag("south");
  s[31] = params.has("no_uoff") || params.has("no_off") ? 1 : 0;
  s[32] = flag("no_rot");
  s[33] = flag("czech");
  return s;
}
