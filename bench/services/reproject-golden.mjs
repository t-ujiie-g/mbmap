// `reprojected` sources (mbmap/services' wmtsSource / wmsSource of other CRSs, tiles by mbmap/data's reprojectTile in
// Chromium) vs proj4js 2.22.0: synthetic WMTS sets and WMS GetMaps in EPSG:4326, 6677 and 32654 whose pixels hold their
// own index; each tile pixel must show the source pixel its center falls in. Needs `npm --prefix npm run build`.
import { createServer } from "node:http";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import proj4 from "proj4";
import { decodePng, encodePng } from "../lib/png.mjs";
import { ROOT } from "../lib/root.mjs";
import { serve } from "../lib/serve.mjs";

const R = 6378137;
const WORLD = 2 * Math.PI * R;
const DEGREE = WORLD / 360;
const DEFS = {
  4326: "+proj=longlat +datum=WGS84 +no_defs",
  6677: "+proj=tmerc +lat_0=36 +lon_0=139.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs",
  32654: "+proj=utm +zone=54 +datum=WGS84 +units=m +no_defs",
};

// A pixel holding its index (column, row) modulo 4096.
const code = (gx, gy) => [gx & 255, gy & 255, (((gx >> 8) & 15) << 4) | ((gy >> 8) & 15), 255];
const decode = (rgba, o) => [rgba[o] | ((rgba[o + 2] >> 4) << 8), rgba[o + 1] | ((rgba[o + 2] & 15) << 8)];
function image(width, height, at) {
  const rgba = new Uint8Array(width * height * 4);
  for (let j = 0; j < height; j++) for (let i = 0; i < width; i++) rgba.set(code(...at(i, j)), (j * width + i) * 4);
  return encodePng(width, height, rgba, { alpha: true });
}

// --- The services: WMTS tiles of every set, and GetMap of any box; each GetMap is recorded. ---
const getMaps = [];
const services = createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  res.setHeader("access-control-allow-origin", "*");
  const tile = /^\/wmts\/(\w+)\/m(\d+)\/(\d+)\/(\d+)\.png$/.exec(url.pathname);
  if (tile) {
    const [row, col] = [Number(tile[3]), Number(tile[4])];
    res.setHeader("content-type", "image/png");
    return res.end(image(256, 256, (i, j) => [col * 256 + i, row * 256 + j]));
  }
  if (url.pathname === "/wms") {
    const q = Object.fromEntries([...url.searchParams].map(([k, v]) => [k.toUpperCase(), v]));
    const [w, h] = [Number(q.WIDTH), Number(q.HEIGHT)];
    getMaps.push({ ...q, bbox: q.BBOX.split(",").map(Number), width: w, height: h });
    res.setHeader("content-type", "image/png");
    return res.end(image(w, h, (i, j) => [i, j]));
  }
  res.statusCode = 404;
  res.end();
});
await new Promise((r) => services.listen(0, "127.0.0.1", r));
const host = `http://127.0.0.1:${services.address().port}`;

// Two sets: the world in EPSG:4326 (zooms 0-12) and 50 m to 800 m around Tokyo in EPSG:6677, corners northing first.
const matrix = (id, scale, corner, cols, rows) =>
  `<TileMatrix><ows:Identifier>${id}</ows:Identifier><ScaleDenominator>${scale}</ScaleDenominator><TopLeftCorner>${corner}</TopLeftCorner>` +
  `<TileWidth>256</TileWidth><TileHeight>256</TileHeight><MatrixWidth>${cols}</MatrixWidth><MatrixHeight>${rows}</MatrixHeight></TileMatrix>`;
const geo = Array.from({ length: 13 }, (_, z) => matrix(`m${z}`, ((0.703125 / 2 ** z) * DEGREE) / 0.00028, "90 -180", 2 * 2 ** z, 2 ** z)).join("");
const plane = [50, 100, 200, 400, 800].map((m, i) => matrix(`m${i}`, m / 0.00028, "20000 -40000", Math.ceil(80000 / (m * 256)), Math.ceil(60000 / (m * 256)))).join("");
const wmtsXml = `<Capabilities xmlns="http://www.opengis.net/wmts/1.0" xmlns:ows="http://www.opengis.net/ows/1.1" version="1.0.0"><Contents>
  <Layer><ows:Identifier>l</ows:Identifier><Format>image/png</Format>
    <TileMatrixSetLink><TileMatrixSet>GEO</TileMatrixSet></TileMatrixSetLink><TileMatrixSetLink><TileMatrixSet>PLANE</TileMatrixSet></TileMatrixSetLink>
    <ResourceURL format="image/png" resourceType="tile" template="${host}/wmts/{TileMatrixSet}/{TileMatrix}/{TileRow}/{TileCol}.png"/></Layer>
  <TileMatrixSet><ows:Identifier>GEO</ows:Identifier><ows:SupportedCRS>urn:ogc:def:crs:EPSG::4326</ows:SupportedCRS>${geo}</TileMatrixSet>
  <TileMatrixSet><ows:Identifier>PLANE</ows:Identifier><ows:SupportedCRS>urn:ogc:def:crs:EPSG::6677</ows:SupportedCRS>${plane}</TileMatrixSet>
</Contents></Capabilities>`;
const wmsXml = (version) => `<WMS_Capabilities version="${version}"><Capability><Request><GetMap><Format>image/png</Format>
  <DCPType><HTTP><Get><OnlineResource xmlns:xlink="http://www.w3.org/1999/xlink" xlink:href="${host}/wms?"/></Get></HTTP></DCPType></GetMap></Request>
  <Layer><Title>t</Title><${version === "1.3.0" ? "CRS" : "SRS"}>EPSG:4326</${version === "1.3.0" ? "CRS" : "SRS"}><${version === "1.3.0" ? "CRS" : "SRS"}>EPSG:6677</${version === "1.3.0" ? "CRS" : "SRS"}><${version === "1.3.0" ? "CRS" : "SRS"}>EPSG:32654</${version === "1.3.0" ? "CRS" : "SRS"}>
  <Layer><Name>l</Name><Title>l</Title></Layer></Layer></Capability></WMS_Capabilities>`;

// The tile pixel's center in `crs`.
function centers(crs, z, x, y) {
  const to = proj4(DEFS[4326], DEFS[crs]);
  const px = WORLD / 2 ** z / 256;
  return Array.from({ length: 256 * 256 }, (_, k) => {
    const [i, j] = [k % 256, Math.floor(k / 256)];
    const lon = ((-WORLD / 2 + x * (WORLD / 2 ** z) + (i + 0.5) * px) / R) * (180 / Math.PI);
    const lat = (Math.atan(Math.sinh((WORLD / 2 - y * (WORLD / 2 ** z) - (j + 0.5) * px) / R)) * 180) / Math.PI;
    return crs === 4326 ? [lon, lat] : to.forward([lon, lat]);
  });
}
// Tile pixels (where `inside`) whose source pixel (column, row from `index`) differs, leaving out those within 1e-6 pixel of a border.
function mismatches(rgba, points, index, inside = () => true) {
  let bad = 0;
  let lit = 0;
  for (let k = 0; k < points.length; k++) {
    if (!inside(points[k])) continue;
    const [sx, sy] = index(points[k]);
    if ([sx, sy].some((v) => Math.abs(v - Math.round(v)) < 1e-6)) continue;
    if (!rgba || rgba[k * 4 + 3] === 0) {
      bad++;
      continue;
    }
    lit++;
    const [gx, gy] = decode(rgba, k * 4);
    if (gx !== (Math.floor(sx) & 4095) || gy !== (Math.floor(sy) & 4095)) bad++;
  }
  return { bad, lit };
}

const { server, origin } = await serve();
const browser = await chromium.launch();
const results = [];
let failed = 0;
const report = (r) => {
  if (!r.ok) failed++;
  results.push(r);
  console.log(JSON.stringify(r));
};
try {
  const page = await browser.newPage();
  page.on("pageerror", (e) => console.log("pageerror", e.message));
  await page.goto(`${origin}/bench/geotiff/page.html`);
  await page.waitForFunction(() => window.__ready, null, { timeout: 60000 });
  await page.evaluate(async () => (window.services = await import("/npm/dist/services.js")));
  const sourceOf = (kind, doc, options) =>
    page.evaluate(([kind, doc, options]) => {
      const s = window.services;
      return kind === "wmts" ? s.wmtsSource(s.readWMTSCapabilities(doc), options) : s.wmsSource(s.readWMSCapabilities(doc), options);
    }, [kind, doc, options]);
  const tile = async (spec, z, x, y) => {
    const b64 = await page.evaluate(async ([spec, z, x, y]) => {
      const png = await window.data.reprojectTile(spec, z, x, y);
      if (!png) return null;
      let s = "";
      const bytes = new Uint8Array(png);
      for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
      return btoa(s);
    }, [spec, z, x, y]);
    return b64 === null ? null : decodePng(Buffer.from(b64, "base64")).rgba;
  };
  // Tokyo at zooms 9 to 15, and two world tiles for the geographic set.
  const tokyo = [9, 11, 13, 15].map((z) => [z, Math.floor(((139.767 + 180) / 360) * 2 ** z), Math.floor(((1 - Math.log(Math.tan((35.68 * Math.PI) / 180) + 1 / Math.cos((35.68 * Math.PI) / 180)) / Math.PI) / 2) * 2 ** z)]);

  for (const set of ["GEO", "PLANE"]) {
    const spec = await sourceOf("wmts", wmtsXml, { layer: "l", tileMatrixSet: set });
    const crs = set === "GEO" ? 4326 : 6677;
    report({ check: "wmts source", set, ok: spec.type === "reprojected" && spec.crs === crs && spec.grid.matrices[0].x === (set === "GEO" ? -180 : -40000) && spec.grid.matrices[0].y === (set === "GEO" ? 90 : 20000), maxzoom: spec.maxzoom });
    for (const [z, x, y] of set === "GEO" ? [[1, 1, 0], [2, 3, 1], ...tokyo] : tokyo) {
      const rgba = await tile(spec, z, x, y);
      const points = centers(crs, z, x, y);
      // The matrix the tile reads: the coarsest still finer than its center pixel, as the worker picks it.
      const c = 128 * 256 + 128;
      const want = Math.hypot(points[c][0] - points[c - 1][0], points[c][1] - points[c - 1][1]);
      const ms = spec.grid.matrices;
      const finer = ms.filter((m) => m.resolution <= want * 1.0001);
      const m = finer.length ? finer.reduce((a, b) => (b.resolution > a.resolution ? b : a)) : ms.reduce((a, b) => (b.resolution < a.resolution ? b : a));
      const inside = ([px, py]) => px >= m.x && py <= m.y && px < m.x + m.cols * 256 * m.resolution && py > m.y - m.rows * 256 * m.resolution;
      const r = mismatches(rgba, points, ([px, py]) => [(px - m.x) / m.resolution, (m.y - py) / m.resolution], inside);
      report({ check: "wmts tile", set, tile: `${z}/${x}/${y}`, matrix: m.id, ...r, ok: r.bad === 0 && r.lit > 0 });
    }
  }

  for (const [version, crs] of [["1.3.0", 4326], ["1.3.0", 6677], ["1.1.1", 4326], ["1.3.0", 32654]]) {
    const spec = await sourceOf("wms", wmsXml(version), { layers: "l", crs: `EPSG:${crs}` });
    const north = version === "1.3.0" && crs !== 32654;
    report({ check: "wms source", version, crs, ok: spec.type === "reprojected" && spec.crs === crs && spec.image.northFirst === north });
    for (const [z, x, y] of tokyo) {
      const before = getMaps.length;
      const rgba = await tile(spec, z, x, y);
      const ask = getMaps[before];
      if (!ask || getMaps.length !== before + 1) {
        report({ check: "wms tile", version, crs, tile: `${z}/${x}/${y}`, ok: false, asked: getMaps.length - before });
        continue;
      }
      const [x0, y0, x1, y1] = north ? [ask.bbox[1], ask.bbox[0], ask.bbox[3], ask.bbox[2]] : ask.bbox;
      const [rx, ry] = [(x1 - x0) / ask.width, (y1 - y0) / ask.height];
      const r = mismatches(rgba, centers(crs, z, x, y), ([px, py]) => [(px - x0) / rx, (y1 - py) / ry]);
      const named = ask[version === "1.3.0" ? "CRS" : "SRS"] === `EPSG:${crs}`;
      report({ check: "wms tile", version, crs, tile: `${z}/${x}/${y}`, size: [ask.width, ask.height], ...r, ok: named && r.bad === 0 && r.lit > 0 && ask.width <= 2048 });
    }
  }
} finally {
  await browser.close();
  server.close();
  services.close();
}

await writeFile(path.join(ROOT, "bench/results/reproject-golden.json"), JSON.stringify({ env: { proj4: "2.22.0", node: process.version }, results }, null, 2) + "\n");
console.log(`${results.length - failed} of ${results.length} ok`);
if (failed) process.exit(1);
