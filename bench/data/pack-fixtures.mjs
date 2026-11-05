// The pack test's fixtures in bench/npm/pages/data/: WARDS in plane IX as shapefiles (Shift_JIS, an
// Esri .prj; loose and zipped), refused archives, quantized TopoJSON lines, STATIONS as a FlatGeobuf, HILL as a COG.
// Usage: node data/pack-fixtures.mjs (bench/npm/pack-test.mjs imports WARDS and STATIONS).
import { writeFile } from "node:fs/promises";
import path from "node:path";
import proj4 from "proj4";
import topojsonServer from "topojson-server";
import { ROOT } from "../lib/root.mjs";
import { fgbFile, T } from "./fgb-write.mjs";
import { encodeText, writeShapefile, writeZip } from "./shapefile.mjs";
import { tiffFile } from "./tiff-write.mjs";

/** The areas' rings in longitude and latitude: outer rings counter-clockwise, holes clockwise. */
export const WARDS = [
  { name: "丸の内", number: 1, rings: [[[139.760, 35.676], [139.768, 35.676], [139.768, 35.684], [139.760, 35.684], [139.760, 35.676]], [[139.762, 35.678], [139.762, 35.680], [139.764, 35.680], [139.764, 35.678], [139.762, 35.678]]] },
  { name: "八重洲", number: 2, rings: [[[139.769, 35.678], [139.775, 35.678], [139.775, 35.684], [139.769, 35.684], [139.769, 35.678]]] },
];

/** dem.tif's elevation at column `x`, row `y`: a hill (float32), -9999 in its first tile. */
export const HILL = { width: 200, height: 150, west: 139.7, north: 35.72, step: 0.0005, at: (x, y) => Math.fround(40 + 30 * Math.exp(-(((x - 120) / 40) ** 2 + ((y - 80) / 30) ** 2))) };

/** The points of stations.fgb (name, longitude, latitude), in file order. */
export const STATIONS = [["有楽町", 139.7631, 35.6751], ["東京", 139.7671, 35.6812], ["日本橋", 139.7745, 35.6820], ["三越前", 139.7732, 35.6853], ["神田", 139.7709, 35.6918]];

const IX = 139 + 50 / 60;
proj4.defs("EPSG:6677", `+proj=tmerc +lat_0=36 +lon_0=${IX} +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs`);
const PRJ = `PROJCS["JGD_2011_Japan_Zone_9",GEOGCS["GCS_JGD_2011",DATUM["D_JGD_2011",SPHEROID["GRS_1980",6378137.0,298.257222101]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]],PROJECTION["Transverse_Mercator"],PARAMETER["False_Easting",0.0],PARAMETER["False_Northing",0.0],PARAMETER["Central_Meridian",${IX}],PARAMETER["Scale_Factor",0.9999],PARAMETER["Latitude_Of_Origin",36.0],UNIT["Meter",1.0]]`;

if (import.meta.url === `file://${process.argv[1]}`) {
  const dir = path.join(ROOT, "bench/npm/pages/data");
  // Shapefiles keep outer rings clockwise, holes counter-clockwise.
  const records = WARDS.map((w) => ({
    parts: w.rings.map((r) => r.slice().reverse().map((p) => proj4("EPSG:4326", "EPSG:6677", p))),
    values: [w.name, w.number],
  }));
  const fields = [{ name: "名前", type: "C", length: 20 }, { name: "番号", type: "N", length: 4 }];
  const { shp, shx, dbf } = writeShapefile(records, { type: 5, fields, encoding: "shift_jis" });
  const files = { shp, shx, dbf, prj: encodeText(PRJ), cpg: encodeText("CP932") };
  for (const [ext, data] of Object.entries(files)) await writeFile(path.join(dir, `wards.${ext}`), data);
  await writeFile(path.join(dir, "wards.zip"), writeZip(Object.entries(files).map(([ext, data]) => ({ name: `tokyo/wards.${ext}`, data }))));
  await writeFile(path.join(dir, "encrypted.zip"), writeZip([{ name: "a.shp", data: shp, flags: 1 }]));
  await writeFile(path.join(dir, "bomb.zip"), writeZip([{ name: "a.shp", data: shp, size: 300 * 1024 * 1024 }]));
  const lines = {
    type: "FeatureCollection",
    features: [
      { type: "Feature", id: "a", properties: { name: "内堀通り" }, geometry: { type: "LineString", coordinates: [[139.755, 35.672], [139.757, 35.680], [139.756, 35.688]] } },
      { type: "Feature", id: 2, properties: { name: "永代通り" }, geometry: { type: "LineString", coordinates: [[139.757, 35.680], [139.770, 35.686], [139.780, 35.684]] } },
    ],
  };
  await writeFile(path.join(dir, "lines.topojson"), JSON.stringify(topojsonServer.topology({ lines }, 1e5)));
  const hill = Array.from({ length: HILL.width * HILL.height }, (_, i) => HILL.at(i % HILL.width, Math.floor(i / HILL.width)));
  const half = Array.from({ length: (HILL.width / 2) * (HILL.height / 2) }, (_, i) => hill[Math.floor(i / (HILL.width / 2)) * 2 * HILL.width + (i % (HILL.width / 2)) * 2]);
  const geo = { pixelScale: [HILL.step, HILL.step, 0], tiepoint: [0, 0, 0, HILL.west, HILL.north, 0] };
  await writeFile(path.join(dir, "dem.tif"), tiffFile([
    { width: HILL.width, height: HILL.height, bits: 32, format: 3, values: [hill], tile: [64, 64], compression: 8, predictor: 3, geo, keys: [[1024, 2], [1025, 1], [2048, 4326]], nodata: "-9999", empty: [0] },
    { width: HILL.width / 2, height: HILL.height / 2, bits: 32, format: 3, values: [half], tile: [64, 64], compression: 5, subfile: 1, nodata: "-9999" },
  ], { ifdsFirst: true }));
  const stations = STATIONS.map(([name, x, y], i) => ({ type: "Feature", geometry: { type: "Point", coordinates: [x, y] }, properties: { 名前: name, 番号: i + 1 } }));
  await writeFile(path.join(dir, "stations.fgb"), fgbFile(stations, { columns: [{ name: "名前", type: T.String }, { name: "番号", type: T.Int }], nodeSize: 2, crs: { org: "EPSG", code: 4326 } }));
}
