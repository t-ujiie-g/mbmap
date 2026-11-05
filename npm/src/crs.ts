// Coordinate reference systems as the workers take them, shared by mbmap/analysis
// and mbmap/data.

/**
 * A coordinate reference system: an EPSG code (`6677`, `"EPSG:6677"`, `"urn:ogc:def:crs:EPSG::6677"`),
 * `"CRS84"` (= 4326), a PROJ string, or (in mbmap/analysis) a name given with `defineCrs`. EPSG codes
 * known without a definition are listed in the package README.
 */
export type Crs = string | number;

/** An EPSG code, or a definition as docs/FORMATS.md "CRS definition" encodes it. */
export type CrsArg = number | Float64Array;

/** `crs` as the workers take it, `named` PROJ strings looked up by name; PROJ strings load their parser on first use. */
export async function crsArg(crs: Crs, entry: string, named?: Map<string, string>): Promise<CrsArg> {
  if (typeof crs === "number" && Number.isInteger(crs) && crs > 0) return crs;
  if (typeof crs === "string") {
    const key = crs.trim().toUpperCase();
    const text = named?.get(key) ?? (key.startsWith("+") ? crs : undefined);
    if (text !== undefined) return (await import("./projstring.js")).parseProjString(text);
    if (/^(OGC:)?CRS84$/.test(key)) return 4326;
    const m = /^(?:EPSG:|URN:OGC:DEF:CRS:EPSG::)?(\d{1,6})$/.exec(key);
    if (m) return Number(m[1]);
  }
  throw new Error(`mbmap: ${entry}: not a CRS: ${String(crs)}`);
}
