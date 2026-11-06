// mbmap/data on bench/npm/pages/data, run by npm/pack-test.mjs.
import proj4 from "proj4";
import { HILL, STATIONS, WARDS } from "../../data/pack-fixtures.mjs";
import { pixel } from "./pixels.mjs";

// Vector formats read, drawn and counted (each lazy part loaded when first needed), written and
// read back, and refused; then GeoTIFF windows and `geotiff` sources.
export async function dataChecks(page, requests) {
  const names = () => requests.map((u) => u.split("/").pop());
  const startup = names();
  const [x, y] = proj4("EPSG:4326", "EPSG:6677", [139.7671, 35.6812]); // as pack-fixtures.mjs defines it
  const r = await page.evaluate(async ([x, y]) => {
    const { read, parse } = await import("mbmap/data");
    const map = window.__map;
    const drawn = (await map.queryRenderedFeatures({ layers: ["stations"] })).length;
    const linesDrawn = (await map.queryRenderedFeatures({ layers: ["lines"] })).length;
    const file = await read(new File(["POINT (1 2)\nGEOMETRYCOLLECTION (POINT (3 4), LINESTRING (0 0, 1 1))"], "shapes.wkt"));
    const bytes = new Uint8Array([1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xf0, 0x3f, 0, 0, 0, 0, 0, 0, 0, 0x40]);
    const wkb = await read(bytes, { format: "wkb" });
    const hex = await parse("0101000020E6100000000000000000F03F0000000000000040", { format: "wkb" });
    const tsv = await parse("x\ty\tname\n1\t2\ta\n", { format: "csv" });
    const plane = await parse(`SRID=6677;POINT (${x} ${y})\nPOINT (139.7671 35.6812)`, { format: "wkt" });
    const fail = (p) => p.then(() => "", (e) => e.message);
    return {
      ...window.__data,
      drawn,
      linesDrawn,
      file: file.toGeoJSON().features.map((f) => f.geometry.type),
      wkb: wkb.toGeoJSON().features[0].geometry.coordinates,
      hex: hex.toGeoJSON().features[0].geometry.coordinates,
      tsv: [tsv.columns, tsv.toGeoJSON().features[0].geometry.coordinates],
      plane: plane.toGeoJSON().features.map((f) => f.geometry.coordinates),
      bytesKept: bytes.length,
      refused: await fail(read("data:text/csv,a,b")),
      noFormat: await fail(read(new Uint8Array([1]))),
      malformed: await fail(parse("a,b\n\"x,1\n", { format: "csv" })),
      srid: await fail(parse("SRID=9999;POINT (1 2)", { format: "wkt" })),
      badOption: await fail(parse("a\n", { format: "csv", delimiter: ";;" })),
      missing: await fail(read("./missing.csv")),
    };
  }, [x, y]);
  const afterPlane = names();
  const z = await page.evaluate(async () => {
    const { read } = await import("mbmap/data");
    const map = window.__map;
    const wards = await read("./wards.zip");
    map.addSource("wards", { type: "geojson", data: wards.toGeoJSON() });
    map.addLayer({ id: "wards", type: "fill", source: "wards", paint: { "fill-color": "#9333ea", "fill-opacity": 0.4 } }, "stations");
    await map.once("idle");
    const drawn = (await map.queryRenderedFeatures({ layers: ["wards"] })).length;
    const fetched = async (name) => new File([await (await fetch(`./${name}`)).blob()], name);
    const asFile = await read(await fetched("wards.zip"));
    const shpUrl = await read("./wards.shp");
    const looseFiles = await read(await Promise.all(["wards.shp", "wards.dbf", "wards.prj", "wards.cpg"].map(fetched)));
    const byCrs = await read({ shp: "./wards.shp", dbf: "./wards.dbf" }, { crs: "EPSG:6677", encoding: "shift_jis" });
    const fail = (p) => p.then(() => "", (e) => e.message);
    const summary = (t) => ({ length: t.length, columns: t.columns, layer: t.layer, layers: t.layers, features: t.toGeoJSON().features });
    return {
      drawn,
      wards: summary(wards),
      same: [asFile, shpUrl, looseFiles, byCrs].map((t) => JSON.stringify(t.toGeoJSON()) === JSON.stringify(wards.toGeoJSON())),
      encrypted: await fail(read("./encrypted.zip")),
      bomb: await fail(read("./bomb.zip")),
      noLayer: await fail(read("./wards.zip", { layer: "nope" })),
    };
  });
  const loaded = names().filter((n) => /^(data|stations|lines|wards|proj|prjwkt)/.test(n));
  const station = r.features[0];
  const near = (a, b) => Math.abs(a - b) < 1e-7;
  const sameRings = (got, want) => got.length === want.length && got.every((ring, i) => ring.length === want[i].length && ring.every((p, j) => near(p[0], want[i][j][0]) && near(p[1], want[i][j][1])));
  const wardFeatures = z.wards.features;
  const ok =
    ["data.js", "data-worker.js", "data.wasm", "stations.csv", "lines.topojson"].every((n) => startup.includes(n)) &&
    !["proj.wasm", "prjwkt.js", "data-zip.js", "data-crs.js", "xml.wasm"].some((n) => startup.includes(n)) &&
    ["proj.wasm", "data-crs.js"].every((n) => afterPlane.includes(n)) && !["prjwkt.js", "data-zip.js", "xml.wasm"].some((n) => afterPlane.includes(n)) &&
    ["prjwkt.js", "data-zip.js", "wards.zip", "wards.shp", "wards.dbf", "wards.prj", "wards.cpg"].every((n) => loaded.includes(n)) &&
    r.length === 5 &&
    JSON.stringify(r.columns) === JSON.stringify(["名前", "緯度", "経度", "乗降客数", "備考"]) &&
    JSON.stringify(station.geometry) === JSON.stringify({ type: "Point", coordinates: [139.7671, 35.6812] }) &&
    station.properties.名前 === "東京" && station.properties.乗降客数 === 462589 && station.properties.備考 === "丸の内, 八重洲" &&
    r.features[3].properties.乗降客数 === null && r.features[4].geometry === null &&
    r.area === "Polygon" &&
    JSON.stringify(r.datasets) === JSON.stringify([5, 1]) &&
    JSON.stringify(r.inside) === JSON.stringify([0, 1, 3]) &&
    r.drawn === 4 &&
    r.linesDrawn > 0 &&
    JSON.stringify([r.lines.layer, r.lines.layers]) === JSON.stringify(["lines", ["lines"]]) &&
    JSON.stringify(r.lines.features.map((f) => [f.id, f.properties.name, f.geometry.type])) === JSON.stringify([["a", "内堀通り", "LineString"], [2, "永代通り", "LineString"]]) &&
    JSON.stringify(r.file) === JSON.stringify(["Point", "Point", "LineString"]) &&
    JSON.stringify(r.wkb) === JSON.stringify([1, 2]) &&
    JSON.stringify(r.hex) === JSON.stringify([1, 2]) &&
    JSON.stringify(r.tsv) === JSON.stringify([["x", "y", "name"], [1, 2]]) &&
    r.plane.length === 2 && near(r.plane[0][0], 139.7671) && near(r.plane[0][1], 35.6812) && JSON.stringify(r.plane[1]) === JSON.stringify([139.7671, 35.6812]) &&
    r.bytesKept === 21 &&
    /http\(s\) URL/.test(r.refused) &&
    /format cannot be told/.test(r.noFormat) &&
    r.malformed === "mbmap: data: malformed CSV at 4: unterminated quoted field" &&
    r.srid === "mbmap: data: SRID 9999: unsupported CRS EPSG:9999" &&
    /invalid delimiter/.test(r.badOption) &&
    /HTTP 404/.test(r.missing) &&
    z.drawn > 0 &&
    z.wards.length === 2 && JSON.stringify(z.wards.columns) === JSON.stringify(["名前", "番号"]) &&
    JSON.stringify([z.wards.layer, z.wards.layers]) === JSON.stringify(["tokyo/wards", ["tokyo/wards"]]) &&
    JSON.stringify(wardFeatures.map((f) => [f.properties.名前, f.properties.番号, f.geometry.type])) === JSON.stringify([["丸の内", 1, "Polygon"], ["八重洲", 2, "Polygon"]]) &&
    WARDS.every((w, i) => sameRings(wardFeatures[i].geometry.coordinates, w.rings)) &&
    z.same.every(Boolean) &&
    /encrypted entries are not supported/.test(z.encrypted) &&
    /inflates to more than 268435456 bytes/.test(z.bomb) &&
    /no shapefile named nope/.test(z.noLayer);
  // KML (by URL, as a File, as a KMZ made here) and GPX: xml.wasm is fetched on the first
  // of them only, and a KML is drawn.
  const xmlBefore = requests.filter((u) => u.endsWith("/xml.wasm")).length;
  const k = await page.evaluate(async () => {
    const { read, parse } = await import("mbmap/data");
    const map = window.__map;
    const kml = await read("./places.kml");
    const text = await (await fetch("./places.kml")).text();
    const file = await read(new File([text], "places.kml"));
    // A KMZ: a deflated doc.kml beside an image, zipped by hand.
    const deflated = new Uint8Array(await new Response(new Blob([text]).stream().pipeThrough(new CompressionStream("deflate-raw"))).arrayBuffer());
    const zip = (entries) => {
      const parts = [];
      const central = [];
      let offset = 0;
      for (const [name, data, method, size = data.length] of entries) {
        const n = new TextEncoder().encode(name);
        const local = new DataView(new ArrayBuffer(30));
        local.setUint32(0, 0x04034b50, true);
        local.setUint16(8, method, true);
        local.setUint32(18, data.length, true);
        local.setUint32(22, size, true);
        local.setUint16(26, n.length, true);
        const cd = new DataView(new ArrayBuffer(46));
        cd.setUint32(0, 0x02014b50, true);
        cd.setUint16(10, method, true);
        cd.setUint32(20, data.length, true);
        cd.setUint32(24, size, true);
        cd.setUint16(28, n.length, true);
        cd.setUint32(42, offset, true);
        parts.push(new Uint8Array(local.buffer), n, data);
        central.push(new Uint8Array(cd.buffer), n);
        offset += 30 + n.length + data.length;
      }
      const end = new DataView(new ArrayBuffer(22));
      end.setUint32(0, 0x06054b50, true);
      end.setUint16(8, entries.length, true);
      end.setUint16(10, entries.length, true);
      end.setUint32(12, central.reduce((s, b) => s + b.length, 0), true);
      end.setUint32(16, offset, true);
      return new Blob([...parts, ...central, new Uint8Array(end.buffer)]);
    };
    const kmz = await read(new File([zip([["files/icon.png", new Uint8Array(8), 0], ["doc.kml", deflated, 8, new TextEncoder().encode(text).length]])], "places.kmz"));
    const gpx = await read("./walk.gpx");
    const parsed = await parse("<gpx><wpt lat='1' lon='2'><name>a</name></wpt></gpx>", { format: "gpx" });
    map.addSource("kml", { type: "geojson", data: kml.toGeoJSON() });
    map.addLayer({ id: "kml-points", type: "circle", source: "kml", filter: ["==", ["geometry-type"], "Point"], paint: { "circle-radius": 5, "circle-color": "#2e7d32" } });
    map.addLayer({ id: "kml-lines", type: "line", source: "kml", paint: { "line-color": ["coalesce", ["get", "stroke"], "#000"], "line-width": 3 } });
    await map.once("idle");
    const fail = (p) => p.then(() => "", (e) => e.message);
    const props = (t) => t.toGeoJSON().features.map((f) => f.properties);
    return {
      kml: kml.toGeoJSON().features.map((f) => [f.geometry.type, f.properties.name]),
      ids: kml.toGeoJSON().features.map((f) => f.id ?? null),
      styles: props(kml).map((p) => [p.styleUrl, p.icon ?? p.stroke]),
      extended: props(kml)[0].備考,
      description: JSON.parse(props(kml)[0].description).value,
      file: file.length,
      kmz: JSON.stringify(kmz.toGeoJSON()) === JSON.stringify(kml.toGeoJSON()),
      gpx: gpx.toGeoJSON().features.map((f) => [f.geometry.type, f.properties.name, f.properties._gpxType ?? null]),
      heart: JSON.parse(props(gpx)[0].coordinateProperties).heart,
      parsed: parsed.toGeoJSON().features[0].geometry.coordinates,
      drawn: [...new Set((await map.queryRenderedFeatures({ layers: ["kml-points", "kml-lines"] })).map((f) => `${f.layer.id} ${f.properties.name}`))],
      malformed: await fail(parse("<kml><Placemark></kml>", { format: "kml" })),
      badKmz: await fail(read(new File([zip([["a.png", new Uint8Array(4), 0]])], "x.kmz"))),
      crs: await fail(read("./places.kml", { crs: "EPSG:6677" })),
    };
  });
  const xmlAfter = requests.filter((u) => u.endsWith("/xml.wasm")).length;
  const okXml =
    xmlBefore === 0 && xmlAfter === 1 &&
    JSON.stringify(k.kml) === JSON.stringify([["Point", "東京駅"], ["Point", "日本橋"], ["LineString", "経路"]]) &&
    JSON.stringify(k.ids) === JSON.stringify(["tokyo", null, null]) &&
    JSON.stringify(k.styles) === JSON.stringify([["#Point_080", "https://maps.gsi.go.jp/portal/sys/v4/symbols/080.png"], ["#Point_080", "https://maps.gsi.go.jp/portal/sys/v4/symbols/080.png"], ["#Line_ff0000ff_3", "#ff0000"]]) &&
    k.extended === "丸の内口" && k.description.includes("<td>東京駅</td>") &&
    k.file === 3 && k.kmz &&
    JSON.stringify(k.gpx) === JSON.stringify([["LineString", "散歩", "trk"], ["Point", "東京駅", null]]) &&
    JSON.stringify(k.heart) === JSON.stringify([90, 95]) &&
    JSON.stringify(k.parsed) === JSON.stringify([2, 1]) &&
    ["kml-points 東京駅", "kml-points 日本橋", "kml-lines 経路"].every((d) => k.drawn.includes(d)) &&
    k.malformed === "mbmap: data: malformed XML at 16: opening and ending tag mismatch: Placemark != kml" &&
    /no \.kml file/.test(k.badKmz) &&
    /always in EPSG:4326/.test(k.crs);
  // FlatGeobuf whole, by bbox through its index (range requests from the URL, and from bytes):
  // data-fgb.js is fetched with the first read only.
  const fgbBefore = requests.filter((u) => u.endsWith("/data-fgb.js")).length;
  const g = await page.evaluate(async () => {
    const { read } = await import("mbmap/data");
    const bbox = [139.766, 35.68, 139.775, 35.683];
    const rows = (t) => t.toGeoJSON().features.map((f) => [f.id, f.properties.名前, f.properties.番号]);
    const fail = (p) => p.then(() => "", (e) => e.message);
    const bytes = await (await fetch("./stations.fgb")).arrayBuffer();
    return {
      all: rows(await read("./stations.fgb")),
      near: rows(await read("./stations.fgb", { bbox })),
      fromBytes: rows(await read(bytes, { format: "flatgeobuf", bbox })),
      badBbox: await fail(read("./stations.fgb", { bbox: [1, 2, 0, 3] })),
      csvBbox: await fail(read("./stations.csv", { bbox })),
    };
  });
  const fgbAfter = requests.filter((u) => u.endsWith("/data-fgb.js")).length;
  const okFgb =
    fgbBefore === 0 && fgbAfter === 1 &&
    JSON.stringify(g.all) === JSON.stringify(STATIONS.map(([name], i) => [i, name, i + 1])) &&
    JSON.stringify(g.near) === JSON.stringify([[1, "東京", 2], [2, "日本橋", 3]]) &&
    JSON.stringify(g.fromBytes) === JSON.stringify(g.near) &&
    /invalid bbox/.test(g.badBbox) && /bbox is for FlatGeobuf/.test(g.csvBbox);
  // Writing: a DataTable as GeoJSON, CSV and KML, a GeoJSON object as KML, each read back.
  const w = await page.evaluate(async () => {
    const { read, parse, write } = await import("mbmap/data");
    const stations = await read("./stations.csv");
    const drawn = {
      type: "FeatureCollection",
      features: [
        { type: "Feature", id: "d1", properties: { name: "区画A", 面積: 12.5 }, geometry: { type: "Polygon", coordinates: [[[139.76, 35.68], [139.77, 35.68], [139.77, 35.69], [139.76, 35.68]]] } },
        { type: "Feature", properties: { name: "線" }, geometry: { type: "LineString", coordinates: [[139.76, 35.68], [139.77, 35.69]] } },
      ],
    };
    const fail = (p) => p.then(() => "", (e) => e.message);
    const geojson = await write(stations, { format: "geojson" });
    const csv = await write(stations, { format: "csv" });
    const kml = await write(drawn, { format: "kml" });
    const wkt = await write(drawn, { format: "csv", delimiter: ";" });
    const back = await parse(csv, { format: "csv" });
    const kmlBack = await parse(kml, { format: "kml" });
    const read2 = await parse(JSON.stringify(drawn), { format: "geojson" });
    return {
      geojson: geojson === JSON.stringify(stations.toGeoJSON()),
      csvHead: csv.split("\r\n")[0],
      csvRows: back.length,
      csvSame: JSON.stringify(back.toGeoJSON().features.map((f) => f.geometry)) === JSON.stringify(stations.toGeoJSON().features.map((f) => f.geometry)),
      kmlNames: kmlBack.toGeoJSON().features.map((f) => [f.id ?? null, f.properties.name, f.geometry.type]),
      wktHead: wkt.split("\r\n")[0],
      geojsonIds: read2.toGeoJSON().features.map((f) => f.id ?? null),
      badFormat: await fail(write(stations, { format: "shp" })),
      lonlat: await fail(write(drawn, { format: "csv", geometryFormat: "lonlat" })),
    };
  });
  const okWrite =
    w.geojson && w.csvRows === 5 && w.csvSame &&
    w.csvHead === "名前,緯度,経度,乗降客数,備考,longitude,latitude" &&
    JSON.stringify(w.kmlNames) === JSON.stringify([["d1", "区画A", "Polygon"], [null, "線", "LineString"]]) &&
    w.wktHead === "name;面積;wkt" &&
    JSON.stringify(w.geojsonIds) === JSON.stringify(["d1", null]) &&
    /unknown write format shp/.test(w.badFormat) && /not a point/.test(w.lonlat);
  // Rasters: a COG by URL (range requests) whole, by bbox and as an overview; JPEG and WebP
  // tiles the browser decodes; a band as an analysis grid. geotiff.wasm is fetched once.
  const tiffBefore = requests.filter((u) => u.endsWith("/geotiff.wasm")).length;
  const t = await page.evaluate(async (HILL) => {
    const { readRaster } = await import("mbmap/data");
    const { loadGrid } = await import("mbmap/analysis");
    // bench/data/pack-fixtures.mjs HILL.at.
    const at = (x, y) => Math.fround(40 + 30 * Math.exp(-(((x - 120) / 40) ** 2 + ((y - 80) / 30) ** 2)));
    const whole = await readRaster("./dem.tif");
    const box = await readRaster("./dem.tif", { bbox: [139.75, 35.66, 139.76, 35.67] });
    const small = await readRaster("./dem.tif", { width: 50, height: 40 });
    // One 64 x 64 RGB tile, compressed by the browser, in a TIFF written here.
    const tile = async (type, compression) => {
      const canvas = new OffscreenCanvas(64, 64);
      const ctx = canvas.getContext("2d");
      for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
        ctx.fillStyle = `rgb(${x * 4},${y * 4},${128})`;
        ctx.fillRect(x, y, 1, 1);
      }
      const img = new Uint8Array(await (await canvas.convertToBlob({ type, quality: 1 })).arrayBuffer());
      const tags = [[256, 3, 64], [257, 3, 64], [258, 3, [8, 8, 8]], [259, 3, compression], [262, 3, 2], [277, 3, 3], [322, 3, 64], [323, 3, 64], [324, 4, 0], [325, 4, img.length]];
      const ifd = 8 + img.length + (img.length % 2);
      const bits = ifd + 2 + tags.length * 12 + 4;
      const out = new Uint8Array(bits + 6);
      const v = new DataView(out.buffer);
      out.set([0x49, 0x49, 42, 0]);
      v.setUint32(4, ifd, true);
      out.set(img, 8);
      v.setUint16(ifd, tags.length, true);
      tags.forEach(([tag, type2, value], i) => {
        const e = ifd + 2 + i * 12;
        v.setUint16(e, tag, true);
        v.setUint16(e + 2, type2, true);
        v.setUint32(e + 4, Array.isArray(value) ? value.length : 1, true);
        if (Array.isArray(value)) {
          v.setUint32(e + 8, bits, true);
          value.forEach((x, k) => v.setUint16(bits + k * 2, x, true));
        } else if (type2 === 3) v.setUint16(e + 8, value, true);
        else v.setUint32(e + 8, tag === 324 ? 8 : value, true);
      });
      const r = await readRaster(new Blob([out]));
      let worst = 0;
      for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
        const i = y * 64 + x;
        worst = Math.max(worst, Math.abs(r.bands[0][i] - x * 4), Math.abs(r.bands[1][i] - y * 4), Math.abs(r.bands[2][i] - 128));
      }
      return { bands: r.bands.length, worst };
    };
    const grid = await loadGrid(whole);
    const [x, y] = [150, 90];
    const center = [HILL.west + (x + 0.5) * HILL.step, HILL.north - (y + 0.5) * HILL.step];
    const sampled = await grid.sample([center]);
    const slope = await grid.slope();
    grid.dispose();
    return {
      whole: [whole.width, whole.height, whole.bands[0].constructor.name, whole.image, whole.images, whole.crs, whole.noData],
      value: whole.bands[0][90 * HILL.width + 150] === at(150, 90),
      empty: whole.bands[0][0],
      box: [box.width, box.height, box.window.join(",")],
      boxValue: box.bands[0][0] === at(box.window[0], box.window[1]),
      small: [small.width, small.height, small.image],
      jpeg: await tile("image/jpeg", 7),
      webp: await tile("image/webp", 50001),
      sampled: Math.abs(sampled[0] - at(x, y)) < 1e-9,
      slope: Number.isFinite(slope[90 * HILL.width + 150]) && slope[90 * HILL.width + 150] > 0,
      refused: await readRaster(new Blob([new Uint8Array(16)])).then(() => "", (e) => e.message),
    };
  }, { ...HILL, at: undefined });
  // geotiff sources: dem.tif drawn gray as a raster and as a hillshade of a DEM source.
  const sourceBefore = requests.filter((u) => u.endsWith("/geotiff-source.js")).length;
  const drawn = await page.evaluate(async (HILL) => {
    const map = window.__map;
    map.jumpTo({ center: [HILL.west + 150 * HILL.step, HILL.north - 90 * HILL.step], zoom: 15 });
    // Source URLs resolve against the style's, as MapLibre's do.
    const url = new URL("./dem.tif", location.href).href;
    map.addSource("cog", { type: "geotiff", url, range: [40, 70] });
    map.addSource("cog-dem", { type: "geotiff", url, dem: true });
    map.addLayer({ id: "cog", type: "raster", source: "cog" });
    map.addLayer({ id: "cog-shade", type: "hillshade", source: "cog-dem" });
    await new Promise((resolve) => map.once("idle", resolve));
    const r = map.getCanvas().getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2, kept: map.getStyle().sources.cog?.type ?? null };
  }, { ...HILL, at: undefined });
  drawn.pixel = await pixel(page, drawn.x, drawn.y);
  await page.evaluate(() => {
    const map = window.__map;
    map.removeLayer("cog-shade");
    map.removeLayer("cog");
    map.removeSource("cog-dem");
    map.removeSource("cog");
  });
  const sourceAfter = requests.filter((u) => u.endsWith("/geotiff-source.js")).length;
  const tiffAfter = requests.filter((u) => u.endsWith("/geotiff.wasm")).length;
  const okTiff =
    tiffBefore === 0 && tiffAfter === 1 &&
    JSON.stringify(t.whole) === JSON.stringify([200, 150, "Float32Array", 0, 2, 4326, -9999]) &&
    t.value && t.empty === -9999 &&
    JSON.stringify(t.box) === JSON.stringify([20, 20, "100,100,120,120"]) && t.boxValue &&
    JSON.stringify(t.small) === JSON.stringify([50, 40, 1]) &&
    t.jpeg.bands === 3 && t.jpeg.worst <= 12 && t.webp.bands === 3 && t.webp.worst <= 12 &&
    t.sampled && t.slope && /not a TIFF file/.test(t.refused) &&
    sourceBefore === 0 && sourceAfter === 1 && drawn.kept === "geotiff" &&
    drawn.pixel.every((v) => v > 30 && v < 220);
  return [ok && okXml && okFgb && okWrite && okTiff, { raster: { tiffBefore, tiffAfter, ...t, drawn }, loaded, ...r, features: r.features.length, wards: { ...z, wards: { ...z.wards, features: wardFeatures.length } }, xml: { xmlBefore, xmlAfter, ...k }, fgb: { fgbBefore, fgbAfter, ...g }, written: w }];
}
