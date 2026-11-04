// The import-free part of `mbmap/data`: which reader a name asks for, and CSV
// options as the data worker takes them.

/** The formats `mbmap/data` reads: CSV (or TSV), WKT or EWKT, WKB or EWKB (binary or hexadecimal). */
export type DataFormat = "csv" | "wkt" | "wkb";

/**
 * How CSV is read. `delimiter`: one character (by default guessed as papaparse guesses it from
 * `,`, tab, `|`, `;`); `header`: the first row names the columns (default true; else they are named
 * `"0"`, `"1"`, ...); `dynamicTyping`: numbers, booleans and empty fields become numbers, booleans
 * and nulls as papaparse's `dynamicTyping` makes them (default true; else every value is a string);
 * `latitude` and `longitude`, or `geometry` (WKT, EWKT or hexadecimal WKB): the columns the geometry
 * comes from, found by name when not given.
 */
export interface CsvOptions {
  delimiter?: string;
  header?: boolean;
  dynamicTyping?: boolean;
  latitude?: string;
  longitude?: string;
  geometry?: string;
}

const EXTENSIONS: Record<string, DataFormat> = { csv: "csv", tsv: "csv", txt: "csv", wkt: "wkt", wkb: "wkb", ewkb: "wkb" };

/** The format a file name or URL path ends in (`.csv`, `.tsv`, `.txt`, `.wkt`, `.wkb`, `.ewkb`), or null. */
export function formatOf(name: string): DataFormat | null {
  const m = /\.([a-z]+)$/i.exec(name);
  return (m && Object.hasOwn(EXTENSIONS, m[1].toLowerCase()) && EXTENSIONS[m[1].toLowerCase()]) || null;
}

/** `options` as the data worker's `read` takes them (`delimiter` a character code or -1); throws on invalid ones. */
export function csvArgs(options: CsvOptions): { delimiter: number; header: boolean; dynamicTyping: boolean; latitude?: string; longitude?: string; geometry?: string } {
  const { delimiter, header = true, dynamicTyping = true, latitude, longitude, geometry } = options;
  const fail = (what: string): never => {
    throw new Error(`mbmap: data: invalid ${what}`);
  };
  const code = delimiter === undefined ? -1 : typeof delimiter === "string" && delimiter.length === 1 ? delimiter.charCodeAt(0) : -2;
  if (code < -1 || code > 127 || delimiter === '"' || delimiter === "\n" || delimiter === "\r") fail("delimiter");
  if (typeof header !== "boolean") fail("header");
  if (typeof dynamicTyping !== "boolean") fail("dynamicTyping");
  for (const [what, name] of [["latitude", latitude], ["longitude", longitude], ["geometry", geometry]]) {
    if (name !== undefined && (typeof name !== "string" || name === "" || name.includes("\0"))) fail(`${what} column`);
  }
  if ((latitude === undefined) !== (longitude === undefined)) fail("columns: latitude and longitude go together");
  return { delimiter: code, header, dynamicTyping, latitude, longitude, geometry };
}
