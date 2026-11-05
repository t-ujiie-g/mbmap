// xml.wasm (KML, GPX) vs @tmcw/togeojson 7.1.3 over @xmldom/xmldom 0.9.12 on hand-written
// documents, hostile XML, GSI tile features (国土地理院ベクトルタイル提供実験) written as KML and
// GPX, and KMZ archives: rows identical or refused by both.
// Usage: node data/xml-golden.mjs; writes bench/results/xml-golden.json.
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { deflateRawSync } from "node:zlib";
import { VectorTile } from "@mapbox/vector-tile";
import { gpx, kml } from "@tmcw/togeojson";
import { DOMParser } from "@xmldom/xmldom";
import { PbfReader } from "pbf";
import { kmlOfKmz } from "../../data_worker/js/kmz.mjs";
import { hostText } from "../../wasmio/js/host.mjs";
import { tableToGeoJSON } from "../../wasmio/js/table.mjs";
import { ROOT } from "../lib/root.mjs";

const { instance } = await WebAssembly.instantiate(
  await readFile(path.join(ROOT, "_build/wasm-gc/release/build/xml_worker/xml_worker.wasm")),
  { Math, host: hostText() },
);
const w = instance.exports;
const encoder = new TextEncoder();
const bytesOf = (data) => (typeof data === "string" ? encoder.encode(data) : data);

// Our rows ({geometry, properties}), or {error}.
function ours(format, data) {
  const b = bytesOf(data);
  const at = w.prepare_input(b.length);
  if (at < 0) return { error: "input too large" };
  new Uint8Array(w.memory.buffer, at, b.length).set(b);
  let n;
  try {
    n = format === "kml" ? w.read_kml() : w.read_gpx();
  } catch (e) {
    return { error: `trapped: ${e.message}` };
  }
  const out = new Uint8Array(w.memory.buffer.slice(w.output_addr(), w.output_addr() + Math.abs(n)));
  if (n < 0) return { error: new TextDecoder().decode(out) };
  return tableToGeoJSON(out).features.map((f) => ({ geometry: f.geometry, properties: f.properties }));
}

// A reference geometry as our tables hold it: collections flattened, x and y only, empty rings
// left out, a member with a coordinate that is not finite (or missing) left out.
function flatten(g) {
  if (!g) return [];
  if (g.type === "GeometryCollection") return g.geometries.flatMap(flatten);
  const xy = (p) => [p[0] ?? NaN, p[1] ?? NaN];
  const c = g.coordinates;
  const coordinates =
    g.type === "Point" ? xy(c) :
    g.type === "LineString" ? c.map(xy) :
    g.type === "MultiLineString" ? c.map((l) => l.map(xy)) :
    c.map((r) => r.map(xy)).filter((r) => r.length > 0);
  if (coordinates.length === 0 || !coordinates.flat(2).every(Number.isFinite)) return [];
  return [{ type: g.type, coordinates }];
}

// The reference's rows: a row per member with the feature's properties, nested values as
// their JSON text, lone surrogates as U+FFFD (as UTF-8 carries text); ids and bounding boxes
// are left out (tables carry neither), as are network links (mbmap/data reads none).
function rowsOf(collection) {
  const value = (v) => (v !== null && typeof v === "object" ? JSON.stringify(v) : typeof v === "string" ? v.toWellFormed() : v);
  return collection.features.filter((f) => f.properties["@geometry-type"] !== "networklink").flatMap((f) => {
    const properties = Object.fromEntries(Object.entries(f.properties).map(([k, v]) => [k.toWellFormed(), value(v)]));
    const gs = flatten(f.geometry);
    return gs.length > 0 ? gs.map((geometry) => ({ geometry, properties })) : [{ geometry: null, properties }];
  });
}

// togeojson's rows of `text` read by xmldom as a browser's TextDecoder gives it, or null if xmldom throws.
function theirs(format, data) {
  const text = typeof data === "string" ? data : new TextDecoder().decode(data);
  let doc;
  try {
    doc = new DOMParser({ onError: () => {} }).parseFromString(text, "text/xml");
  } catch {
    return null;
  }
  return rowsOf(format === "kml" ? kml(doc) : gpx(doc));
}

// Equal as JSON with numbers by Object.is.
function same(a, b) {
  if (typeof a === "number" || typeof b === "number") return Object.is(a, b);
  if (a === null || b === null || typeof a !== "object" || typeof b !== "object") return a === b;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  const ka = Object.keys(a);
  const kb = Object.keys(b);
  return ka.length === kb.length && ka.every((k) => Object.hasOwn(b, k) && same(a[k], b[k]));
}

const results = {};
const failures = [];
function compare(group, label, got, want) {
  const r = (results[group] ??= { cases: 0, rows: 0, identical: 0, bothRefuse: 0, differ: 0 });
  r.cases++;
  const ok = want === null ? "error" in got : !("error" in got) && same(got, want);
  if (!ok) {
    r.differ++;
    if (failures.length < 20) failures.push({ group, label, got: "error" in got ? got.error : got.slice(0, 2), want: want?.slice(0, 2) ?? "refused" });
  } else if (want === null) r.bothRefuse++;
  else {
    r.identical++;
    r.rows += want.length;
  }
}
const check = (group, format, label, data) => compare(group, label, ours(format, data), theirs(format, data));
// Inputs where we deliberately differ: only our side is checked, and the case is listed.
const deviations = [];
function deviation(group, label, got, expectError, why) {
  const ok = expectError ? "error" in got : !("error" in got);
  deviations.push({ group, label, why, ok });
  if (!ok) failures.push({ group, label, got: got.error ?? got.slice(0, 2), want: expectError ? "refused" : "read" });
}

const KML = (body, ns = "") => `<?xml version="1.0" encoding="UTF-8"?>\n<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2"${ns}>\n<Document>\n${body}\n</Document>\n</kml>\n`;
const GPX = (body, ns = "") => `<?xml version="1.0" encoding="UTF-8"?>\n<gpx version="1.1" creator="mbmap" xmlns="http://www.topografix.com/GPX/1/1"${ns}>\n${body}\n</gpx>\n`;
const pm = (inner, attrs = "") => `<Placemark${attrs}>${inner}</Placemark>`;

// --- Hand-written KML ---
const KML_CASES = [
  ["point", pm("<name>A</name><Point><coordinates>139.7671,35.6812,0</coordinates></Point>")],
  ["point 2D, spaces", pm("<Point><coordinates>\n  139.5 , 35.25  \n</coordinates></Point>")],
  ["point with too few numbers", pm("<Point><coordinates>139.5</coordinates></Point>")],
  ["point with junk", pm("<Point><coordinates>1x,2y,3z,4</coordinates></Point>")],
  ["line string", pm("<LineString><coordinates>0,0 1,1,10 2,0</coordinates></LineString>")],
  ["line tuples split by tabs and newlines", pm("<LineString><coordinates>0,0\t1,1\n\n2,0\r\n3,3</coordinates></LineString>")],
  ["line with a space after a comma", pm("<LineString><coordinates>0, 0 1,1 2,2</coordinates></LineString>")],
  ["line of one tuple", pm("<LineString><coordinates>0,0</coordinates></LineString>")],
  ["linear ring as a line", pm("<LinearRing><coordinates>0,0 1,0 1,1 0,0</coordinates></LinearRing>")],
  ["polygon with a hole", pm("<Polygon><outerBoundaryIs><LinearRing><coordinates>0,0 4,0 4,4 0,4 0,0</coordinates></LinearRing></outerBoundaryIs><innerBoundaryIs><LinearRing><coordinates>1,1 2,1 2,2 1,1</coordinates></LinearRing></innerBoundaryIs></Polygon>")],
  ["polygon closed by fixRing, z compared", pm("<Polygon><outerBoundaryIs><LinearRing><coordinates>0,0,1 4,0 4,4 0,0,2</coordinates></LinearRing></outerBoundaryIs></Polygon>")],
  ["polygon rings too short", pm("<Polygon><outerBoundaryIs><LinearRing><coordinates>0,0 1,1</coordinates></LinearRing></outerBoundaryIs></Polygon>")],
  ["multi geometry, mixed and nested", pm("<name>m</name><MultiGeometry><Point><coordinates>1,2</coordinates></Point><LineString><coordinates>0,0 1,1</coordinates></LineString><MultiGeometry><Polygon><outerBoundaryIs><LinearRing><coordinates>0,0 1,0 1,1 0,0</coordinates></LinearRing></outerBoundaryIs></Polygon></MultiGeometry></MultiGeometry>")],
  ["multi geometry of points", pm("<MultiGeometry><Point><coordinates>1,2</coordinates></Point><Point><coordinates>3,4</coordinates></Point></MultiGeometry>")],
  ["no geometry", pm("<name>empty</name>")],
  ["infinite coordinate", pm("<MultiGeometry><Point><coordinates>Infinity,1</coordinates></Point><Point><coordinates>5,6</coordinates></Point></MultiGeometry>")],
  ["gx:Track", pm("<gx:Track><when>2020-01-01T00:00:00Z</when><when>2020-01-01T00:01:00Z</when><gx:coord>139.1 35.1 10</gx:coord><gx:coord>139.2 35.2 20</gx:coord></gx:Track>")],
  ["gx:Track of one coord", pm("<gx:Track><when>t</when><gx:coord>139.1 35.1</gx:coord></gx:Track>")],
  ["gx:Track with double spaces", pm("<gx:Track><gx:coord>1  2</gx:coord><gx:coord>3 4</gx:coord></gx:Track>")],
  ["gx:MultiTrack", pm("<gx:MultiTrack><gx:Track><when>a</when><when>b</when><gx:coord>1 2</gx:coord><gx:coord>3 4</gx:coord></gx:Track><gx:Track><gx:coord>5 6</gx:coord><gx:coord>7 8</gx:coord></gx:Track><gx:Track><when>c</when><gx:coord>9 10</gx:coord><gx:coord>11 12</gx:coord></gx:Track></gx:MultiTrack>")],
  ["KML 2.3 Track with bare coord", pm("<Track><when>a</when><coord>1 2 3</coord><coord>4 5 6</coord></Track>")],
  ["styles: ids, maps, inline", `
<Style id="s1"><LineStyle><color>ff0000ff</color><width>3</width></LineStyle><PolyStyle><color>7f00ff00</color><fill>0</fill><outline>0</outline></PolyStyle></Style>
<Style id="s2"><IconStyle><color>ffffffff</color><scale>1.5</scale><heading>90</heading><hotSpot x="0.5" y="1" xunits="fraction" yunits="pixels"/><Icon><href>https://example.com/i.png</href></Icon></IconStyle><LabelStyle><color>#ff00ff00</color><scale>0.8</scale></LabelStyle></Style>
<StyleMap id="m1"><Pair><key>normal</key><styleUrl>#s2</styleUrl></Pair><Pair><key>highlight</key><styleUrl>#s1</styleUrl></Pair></StyleMap>
<StyleMap id="m2"><Pair><key>normal</key><styleUrl>#missing</styleUrl></Pair></StyleMap>
${pm("<name>a</name><styleUrl>#s1</styleUrl><Point><coordinates>1,2</coordinates></Point>")}
${pm("<name>b</name><styleUrl>m1</styleUrl><Point><coordinates>1,2</coordinates></Point>")}
${pm("<name>c</name><styleUrl>#m2</styleUrl><Point><coordinates>1,2</coordinates></Point>")}
${pm("<name>d</name><styleUrl>other.kml#s1</styleUrl><Point><coordinates>1,2</coordinates></Point>")}
${pm("<name>e</name><styleUrl>#s1</styleUrl><Style><LineStyle><color>abc</color><width>x</width></LineStyle><PolyStyle><color>12345</color></PolyStyle></Style><Point><coordinates>1,2</coordinates></Point>")}
${pm("<name>f</name><Style><LineStyle><color>#00ff00</color></LineStyle><IconStyle><hotSpot x='a' y='1'/><Icon></Icon></IconStyle></Style>")}
${pm("<name>g</name><styleUrl> #s1 </styleUrl>")}
`],
  ["colors: odd lengths and parseInt", pm("<Style><LineStyle><color>zz0000ff</color></LineStyle><PolyStyle><color>-f0000ff</color></PolyStyle><LabelStyle><color>0x0000ff0</color></LabelStyle><IconStyle><color> f0000ff</color></IconStyle></Style>")],
  ["CascadingStyle", `<gx:CascadingStyle kml:id="c1"><Style><LineStyle><width>7</width></LineStyle></Style></gx:CascadingStyle>${pm("<styleUrl>#c1</styleUrl>")}`, ` xmlns:kml="http://www.opengis.net/kml/2.2"`],
  ["extended data and schema", `
<Schema name="s" id="s"><SimpleField name="pop" type="int"/><SimpleField name="area" type="double"/><SimpleField name="ok" type="bool"/><SimpleField name="no" type="bool"/><SimpleField name="t" type="string"/><SimpleField name="u" type="weird"/><SimpleField name="bad" type="float"/><SimpleField name="sp" type="int"/></Schema>
${pm(`<name>x</name><ExtendedData><Data name="a"><value>1</value></Data><Data name="empty"><value></value></Data><Data name="novalue"></Data><Data><value>anon</value></Data><Data name="name"><value>renamed</value></Data><SchemaData schemaUrl="#s"><SimpleData name="pop">1200</SimpleData><SimpleData name="area">1.5e3</SimpleData><SimpleData name="ok">false</SimpleData><SimpleData name="no"></SimpleData><SimpleData name="t">007</SimpleData><SimpleData name="u">u</SimpleData><SimpleData name="bad">12abc</SimpleData><SimpleData name="sp"> 0x1F </SimpleData><SimpleData name="free">x</SimpleData></SchemaData></ExtendedData>`)}
${pm(`<ExtendedData><Data name="visibility"><value>0</value></Data><Data name="__proto__"><value>p</value></Data></ExtendedData>`)}
`],
  ["name, description, visibility, times", `
${pm("<name>Tōkyō &amp; 東京</name><address>Chiyoda</address><phoneNumber>03</phoneNumber><open>1</open><visibility>0</visibility><description>plain &lt;b&gt;</description><TimeStamp><when>2020-01-02</when></TimeStamp>")}
${pm("<name> </name><visibility>1</visibility><description><![CDATA[<b>html</b>]]> and text</description><TimeSpan><begin>2020</begin></TimeSpan>")}
${pm("<description>text <![CDATA[a]]><![CDATA[b]]></description><TimeStamp></TimeStamp><TimeSpan/>")}
`],
  ["ids", `${pm("<name>a</name>", ' id="p1"')}${pm("<name>b</name>", ' id=""')}`],
  ["ground overlays", `
<GroundOverlay id="g1"><name>box</name><Icon><href>img.png</href></Icon><LatLonBox><north>36</north><south>35</south><east>140</east><west>139</west></LatLonBox></GroundOverlay>
<GroundOverlay><name>turned</name><LatLonBox><north>36.5</north><south>35.25</south><east>140.1</east><west>139.3</west><rotation>33.3</rotation></LatLonBox></GroundOverlay>
<GroundOverlay><name>quad</name><gx:LatLonQuad><coordinates>139,35 140,35 140,36 139,36</coordinates></gx:LatLonQuad></GroundOverlay>
<GroundOverlay><name>quad of nothing</name><gx:LatLonQuad/></GroundOverlay>
<GroundOverlay><name>no box</name><visibility>0</visibility></GroundOverlay>
<GroundOverlay><LatLonBox><north>1</north><south>0</south><east>x</east><west>0</west></LatLonBox></GroundOverlay>
`],
  ["network links", `
<NetworkLink id="n1"><name>link</name><refreshVisibility>1</refreshVisibility><flyToView>0</flyToView><styleUrl>s</styleUrl><Link><href>https://example.com/a.kml</href><refreshMode>onInterval</refreshMode><viewFormat>BBOX=[bboxWest]</viewFormat></Link><Region><LatLonAltBox><north>36</north><south>35</south><east>140</east><west>139</west></LatLonAltBox><Lod><minLodPixels>128</minLodPixels><maxFadeExtent>5</maxFadeExtent></Lod></Region></NetworkLink>
<NetworkLink><name>no region</name><Lod><minLodPixels>1</minLodPixels></Lod></NetworkLink>
<NetworkLink><Region><Lod/></Region></NetworkLink>
`],
  ["folders", `<Folder><name>f</name><Folder>${pm("<name>deep</name><Point><coordinates>1,2</coordinates></Point>")}</Folder></Folder>${pm("<name>top</name>")}`],
  ["prefixed placemark ignored", `<kml:Placemark><name>x</name></kml:Placemark>${pm("<name>y</name>")}`, ` xmlns:kml="http://www.opengis.net/kml/2.2"`],
  ["entities and CDATA everywhere", pm("<name>&#x6771;&#20140;&#128512;&#1114112;&lol;&amp</name><description><![CDATA[a]]>&amp;b</description><Point><coordinates>&#49;,2</coordinates></Point>")],
  ["empty document", ""],
];
for (const [label, body, ns] of KML_CASES) check("kml cases", "kml", label, KML(body, ns));
check("kml cases", "kml", "not KML", "<root><a/></root>");
check("kml cases", "kml", "BOM and CRLF", encoder.encode(`\ufeff${KML(pm("<name>a\r\nb\rc</name><Point><coordinates>1,2</coordinates></Point>"))}`.replace(/\n/g, "\r\n")));
check("kml cases", "kml", "no XML declaration", `<kml><Placemark><name>a</name></Placemark></kml>`);
check("kml cases", "kml", "invalid UTF-8", Uint8Array.from([...encoder.encode("<kml><Placemark><name>a"), 0xff, 0xc3, ...encoder.encode("b</name></Placemark></kml>")]));

// --- GSI 地理院地図 作図-style KML (hand-written in the style its export takes) ---
const SAKUZU = `<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
<name>作図データ</name>
<Style id="Point_080"><IconStyle><Icon><href>https://maps.gsi.go.jp/portal/sys/v4/symbols/080.png</href></Icon><scale>1</scale><hotSpot x="0.5" y="0.5" xunits="fraction" yunits="fraction"/></IconStyle><LabelStyle><scale>0</scale></LabelStyle></Style>
<Style id="Line_ff0000ff_3"><LineStyle><color>ff0000ff</color><width>3</width></LineStyle></Style>
<Style id="Poly_80ff0000"><LineStyle><color>ffff0000</color><width>2</width></LineStyle><PolyStyle><color>80ff0000</color></PolyStyle></Style>
<Placemark>
<name>東京駅</name>
<description><![CDATA[<table><tr><td>名称</td><td>東京駅</td></tr><tr><td>備考</td><td>丸の内口</td></tr></table>]]></description>
<styleUrl>#Point_080</styleUrl>
<ExtendedData><Data name="名称"><value>東京駅</value></Data><Data name="備考"><value>丸の内口</value></Data></ExtendedData>
<Point><coordinates>139.767125,35.681236</coordinates></Point>
</Placemark>
<Placemark>
<name>経路</name>
<styleUrl>#Line_ff0000ff_3</styleUrl>
<LineString><coordinates>139.767125,35.681236 139.763806,35.675131 139.757347,35.671431</coordinates></LineString>
</Placemark>
<Placemark>
<name>範囲</name>
<description>皇居外苑</description>
<styleUrl>#Poly_80ff0000</styleUrl>
<ExtendedData><Data name="面積"><value>1150000</value></Data></ExtendedData>
<Polygon><outerBoundaryIs><LinearRing><coordinates>139.7525,35.6801 139.7601,35.6801 139.7601,35.6754 139.7525,35.6754 139.7525,35.6801</coordinates></LinearRing></outerBoundaryIs></Polygon>
</Placemark>
<Placemark>
<name>円</name>
<Style><LineStyle><color>ff00ff00</color><width>1</width></LineStyle><PolyStyle><color>4000ff00</color></PolyStyle></Style>
<ExtendedData><Data name="_type"><value>circle</value></Data><Data name="_radius"><value>500</value></Data></ExtendedData>
<Polygon><outerBoundaryIs><LinearRing><coordinates>139.7711,35.6812 139.7701,35.6838 139.7671,35.6857 139.7641,35.6838 139.7631,35.6812 139.7641,35.6786 139.7671,35.6767 139.7701,35.6786 139.7711,35.6812</coordinates></LinearRing></outerBoundaryIs></Polygon>
</Placemark>
<Placemark>
<name>文字</name>
<Style><IconStyle><scale>0</scale></IconStyle><LabelStyle><color>ff0000ff</color><scale>1.2</scale></LabelStyle></Style>
<Point><coordinates>139.7700,35.6830</coordinates></Point>
</Placemark>
</Document>
</kml>
`;
check("kml cases", "kml", "地理院地図 作図", SAKUZU);

// --- Hand-written GPX ---
const TPX = ` xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1" xmlns:gpxx="http://www.garmin.com/xmlschemas/GpxExtensions/v3" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"`;
const GPX_CASES = [
  ["waypoints", `<wpt lat="35.6812" lon="139.7671"><ele>3.5</ele><time>2020-01-01T00:00:00Z</time><name>東京駅</name><cmt>c</cmt><desc>d</desc><src>s</src><sym>Flag</sym><type>station</type><link href="https://example.com"><text>site</text><type>text/html</type></link><link><text>no href</text></link></wpt><wpt lat="x" lon="1"/><wpt lat="1" lon="2"></wpt>`],
  ["route with a line style", `<rte><name>r</name><keywords>k</keywords><rtept lat="1" lon="2"><time>t</time></rtept><rtept lat="3" lon="4"/><rtept lat="5"/><extensions><line xmlns="http://www.topografix.com/GPX/gpx_style/0/2"><color>ff0000</color><opacity>0.5</opacity><width>2</width></line></extensions></rte><rte><rtept lat="1" lon="2"/></rte><rte><extensions><line><opacity>0</opacity><width>x</width></line></extensions><rtept lat="1" lon="2"/><rtept lat="3" lon="4"/></rte>`],
  ["track with Garmin extensions", `<trk><name>run</name><type>running</type><trkseg><trkpt lat="35.1" lon="139.1"><ele>10</ele><time>2020-01-01T00:00:00Z</time><extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>120</gpxtpx:hr><gpxtpx:cad>80</gpxtpx:cad><gpxtpx:atemp>21.5</gpxtpx:atemp></gpxtpx:TrackPointExtension><power>250</power></extensions></trkpt><trkpt lat="35.2" lon="139.2"><time>2020-01-01T00:00:10Z</time><extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>125</gpxtpx:hr></gpxtpx:TrackPointExtension><power>n/a</power></extensions></trkpt><trkpt lat="35.3"/><trkpt lat="35.4" lon="139.4"><extensions><heart>130</heart></extensions></trkpt></trkseg></trk>`, TPX],
  ["track of several segments", `<trk><name>multi</name><trkseg><trkpt lat="1" lon="1"><time>a</time></trkpt><trkpt lat="2" lon="2"><time>b</time></trkpt></trkseg><trkseg><trkpt lat="3" lon="3"><extensions><hr>90</hr><cad>1</cad></extensions></trkpt><trkpt lat="4" lon="4"/></trkseg><trkseg><trkpt lat="5" lon="5"/></trkseg><trkseg><trkpt lat="6" lon="6"><time>c</time><extensions><cad>2</cad></extensions></trkpt><trkpt lat="7" lon="7"/></trkseg></trk>`],
  ["track without points", `<trk><name>none</name><trkseg/></trk><trk><trkseg><trkpt lat="1" lon="1"/><trkpt lat="2" lon="2"/></trkseg></trk>`],
  ["Garmin gpxx and namespaced elements", `<trk><name>t</name><extensions><gpxx:TrackExtension><gpxx:DisplayColor>Red</gpxx:DisplayColor></gpxx:TrackExtension></extensions><trkseg><trkpt lat="1" lon="1"/><trkpt lat="2" lon="2"/></trkseg></trk><wpt lat="1" lon="2"><extensions><gpxx:WaypointExtension><gpxx:Proximity> 5 </gpxx:Proximity></gpxx:WaypointExtension></extensions></wpt>`, TPX],
  ["empty gpx", ""],
];
for (const [label, body, ns] of GPX_CASES) check("gpx cases", "gpx", label, GPX(body, ns));
check("gpx cases", "gpx", "GPX 1.0 without a namespace", `<gpx version="1.0"><wpt lat="1" lon="2"><name>a</name></wpt></gpx>`);

// --- Malformed and hostile XML ---
const lol = `<!DOCTYPE kml [<!ENTITY lol "lol"><!ENTITY lol1 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;"><!ENTITY lol2 "&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;"><!ENTITY lol3 "&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;">]>`;
const HOSTILE = [
  ["billion laughs stays unexpanded", `${lol}<kml><Placemark><name>&lol3;</name></Placemark></kml>`],
  ["external entity stays unexpanded", `<!DOCTYPE kml [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><kml><Placemark><name>&xxe;</name></Placemark></kml>`],
  ["unclosed tag", "<kml><Placemark><name>a</name></kml>"],
  ["mismatched tags", "<kml><Placemark></Folder></kml>"],
  ["two roots", "<kml/><kml/>"],
  ["text only", "hello"],
  ["empty", ""],
  ["< in text recovered", "<kml><Placemark><name>1 < 2</name></Placemark></kml>"],
  ["unquoted and valueless attributes", "<kml><Placemark id=p1 hidden><name>a</name></Placemark></kml>"],
  ["repeated attribute", '<kml><Placemark id="a" id="b"/></kml>'],
  ["< in an attribute", '<kml><Placemark id="<"/></kml>'],
  ["undeclared prefix", "<kml><Placemark><gx:Track/></Placemark></kml>"],
  ["comment with --", "<kml><!-- a -- b --></kml>"],
  ["unterminated CDATA", "<kml><Placemark><name><![CDATA[x</name></Placemark></kml>"],
  ["XML declaration not first", ' <?xml version="1.0"?><kml/>'],
  ["processing instruction and doctype", '<?xml version="1.0"?><?xml-stylesheet href="a"?><!DOCTYPE kml SYSTEM "kml.dtd"><kml><Placemark><name>a</name></Placemark></kml>'],
  ["huge attribute", `<kml><Placemark id="${"x".repeat(1 << 20)}"><name>a</name></Placemark></kml>`],
  ["huge text", `<kml><Placemark><name>${"あ".repeat(1 << 20)}</name></Placemark></kml>`],
  ["deep but allowed", `<kml>${"<Folder>".repeat(200)}<Placemark><name>deep</name></Placemark>${"</Folder>".repeat(200)}</kml>`],
  ["many placemarks", `<kml>${pm("<name>n</name><Point><coordinates>1,2</coordinates></Point>").repeat(20000)}</kml>`],
];
for (const [label, text] of HOSTILE) check("hostile", "kml", label, text);
deviation("hostile", "nesting past MAX_XML_DEPTH", ours("kml", `<kml>${"<Folder>".repeat(300)}${"</Folder>".repeat(300)}</kml>`), true, "xmldom has no depth limit; mbmap/data refuses documents nested deeper than 256 (AGENTS.md §8.2)");
deviation("hostile", "100000 levels", ours("kml", `<kml>${"<a>".repeat(100000)}${"</a>".repeat(100000)}</kml>`), true, "as above; togeojson overflows the stack on it");
deviation("hostile", "attributes past MAX_XML_ATTRIBUTES", ours("kml", `<kml><Placemark${Array.from({ length: 2000 }, (_, i) => ` a${i}="1"`).join("")}/></kml>`), true, "xmldom has no attribute limit; mbmap/data refuses more than 1024 on one element");
deviation("hostile", "malformed internal subset", ours("kml", `<!DOCTYPE kml [<!ENTITY a "%x">]><kml/>`), false, "xmldom checks declarations in an internal subset; mbmap/data skips the subset (nothing in it is ever used)");
deviation("hostile", "XML declaration version 2", ours("kml", '<?xml version="2.0"?><kml/>'), false, "xmldom checks an XML declaration's version, encoding and standalone parts; mbmap/data only that it comes first");
deviation("hostile", "XML declaration with a bad encoding", ours("kml", '<?xml version="1.0" encoding="?"?><kml/>'), false, "as above");

// --- GSI tile features written as KML and GPX ---
const manifest = JSON.parse(await readFile(path.join(ROOT, "bench/fixtures/gsi-bvmap.manifest.json"), "utf8"));
const TILES = ["14/14552/6451", "14/14551/6450", "14/14553/6452"].filter((k) => k in manifest.tiles);
if (TILES.length === 0) throw new Error("no GSI fixtures: run npm run fixtures");
const byLayer = {};
for (const key of TILES) {
  const [z, x, y] = key.split("/").map(Number);
  const tile = new VectorTile(new PbfReader(await readFile(path.join(ROOT, "bench/fixtures/gsi-bvmap", `${key}.pbf`))));
  for (const name of ["label", "road", "building", "contour", "railway", "waterarea", "symbol"]) {
    const layer = tile.layers[name];
    for (let i = 0; layer && i < layer.length; i++) (byLayer[name] ??= []).push(layer.feature(i).toGeoJSON(x, y, z));
  }
}
const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const tuple = (p, i) => (i % 3 === 0 ? `${p[0]},${p[1]},${i}` : `${p[0]},${p[1]}`);
const coords = (ring) => ring.map(tuple).join(" ");
const kmlGeometry = (g) => {
  switch (g.type) {
    case "Point": return `<Point><coordinates>${tuple(g.coordinates, 1)}</coordinates></Point>`;
    case "LineString": return `<LineString><coordinates>${coords(g.coordinates)}</coordinates></LineString>`;
    case "Polygon": return `<Polygon>${g.coordinates.map((r, i) => `<${i ? "inner" : "outer"}BoundaryIs><LinearRing><coordinates>${coords(r)}</coordinates></LinearRing></${i ? "inner" : "outer"}BoundaryIs>`).join("")}</Polygon>`;
    default: {
      const t = g.type.slice(5);
      return `<MultiGeometry>${g.coordinates.map((c) => kmlGeometry({ type: t, coordinates: c })).join("")}</MultiGeometry>`;
    }
  }
};
const STYLES = ["line", "poly", "icon"];
const styles = `<Style id="line"><LineStyle><color>ff0000ff</color><width>2</width></LineStyle></Style><Style id="poly"><PolyStyle><color>7f00ff00</color></PolyStyle><LineStyle><color>ff00ff00</color></LineStyle></Style><StyleMap id="icon"><Pair><key>normal</key><styleUrl>#iconn</styleUrl></Pair></StyleMap><Style id="iconn"><IconStyle><scale>1.2</scale><Icon><href>https://maps.gsi.go.jp/portal/sys/v4/symbols/080.png</href></Icon></IconStyle></Style><Schema id="s"><SimpleField name="ftCode" type="int"/><SimpleField name="alti" type="double"/></Schema>`;
const placemark = (f, i) => {
  const props = Object.entries(f.properties);
  const name = f.properties.knj ?? f.properties.ftCode;
  const data = props.map(([k, v]) => (k === "ftCode" || k === "alti" ? "" : `<Data name="${esc(k)}"><value>${esc(v)}</value></Data>`)).join("");
  const simple = props.filter(([k]) => k === "ftCode" || k === "alti").map(([k, v]) => `<SimpleData name="${k}">${esc(v)}</SimpleData>`).join("");
  return `<Placemark id="f${i}">${name !== undefined ? `<name>${esc(name)}</name>` : ""}<styleUrl>#${STYLES[i % 3]}</styleUrl><ExtendedData>${data}<SchemaData schemaUrl="#s">${simple}</SchemaData></ExtendedData>${kmlGeometry(f.geometry)}</Placemark>`;
};
for (const [name, list] of Object.entries(byLayer)) {
  const text = KML(styles + list.map(placemark).join("\n"));
  check("gsi kml", "kml", `${name}: ${list.length} features`, text);
}
const lines = [...(byLayer.road ?? []), ...(byLayer.contour ?? []), ...(byLayer.railway ?? [])].filter((f) => /LineString/.test(f.geometry.type));
const t0 = Date.UTC(2020, 0, 1);
let tick = 0;
const trkpt = (p) => `<trkpt lat="${p[1]}" lon="${p[0]}"><ele>${tick % 50}</ele><time>${new Date(t0 + tick++ * 1000).toISOString()}</time><extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>${100 + (tick % 60)}</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions></trkpt>`;
const trk = (f) => {
  const segs = f.geometry.type === "LineString" ? [f.geometry.coordinates] : f.geometry.coordinates;
  return `<trk><name>${esc(f.properties.knj ?? f.properties.ftCode ?? "")}</name><type>${esc(f.properties.ftCode ?? "")}</type>${segs.map((s) => `<trkseg>${s.map(trkpt).join("")}</trkseg>`).join("")}</trk>`;
};
check("gsi gpx", "gpx", `${lines.length} lines as tracks`, GPX(lines.map(trk).join("\n"), TPX));
const wpts = (byLayer.label ?? []).filter((f) => f.geometry.type === "Point");
const wpt = (f) => `<wpt lat="${f.geometry.coordinates[1]}" lon="${f.geometry.coordinates[0]}"><ele>1</ele><name>${esc(f.properties.knj ?? "")}</name><desc>${esc(f.properties.kana ?? "")}</desc><type>${esc(f.properties.ftCode ?? "")}</type></wpt>`;
check("gsi gpx", "gpx", `${wpts.length} labels as waypoints`, GPX(wpts.map(wpt).join("\n")));
const routes = lines.slice(0, 500).map((f) => `<rte><name>${esc(f.properties.ftCode ?? "")}</name>${(f.geometry.type === "LineString" ? f.geometry.coordinates : f.geometry.coordinates.flat()).map((p) => `<rtept lat="${p[1]}" lon="${p[0]}"/>`).join("")}</rte>`);
check("gsi gpx", "gpx", `${routes.length} lines as routes`, GPX(routes.join("\n")));

// --- KMZ: the zip read by data_worker/js/kmz.mjs, its KML compared ---
function zip(entries) {
  const parts = [];
  const central = [];
  let offset = 0;
  for (const { name, data, store } of entries) {
    const n = encoder.encode(name);
    const body = store ? data : deflateRawSync(data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(store ? 0 : 8, 8);
    local.writeUInt32LE(body.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(n.length, 26);
    const cd = Buffer.alloc(46);
    cd.writeUInt32LE(0x02014b50, 0);
    cd.writeUInt16LE(20, 4);
    cd.writeUInt16LE(20, 6);
    cd.writeUInt16LE(store ? 0 : 8, 10);
    cd.writeUInt32LE(body.length, 20);
    cd.writeUInt32LE(data.length, 24);
    cd.writeUInt16LE(n.length, 28);
    cd.writeUInt32LE(offset, 42);
    parts.push(local, n, body);
    central.push(cd, n);
    offset += 30 + n.length + body.length;
  }
  const size = central.reduce((s, b) => s + b.length, 0);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(size, 12);
  end.writeUInt32LE(offset, 16);
  return new Uint8Array(Buffer.concat([...parts, ...central, end]));
}
async function kmzRows(bytes) {
  try {
    return ours("kml", await kmlOfKmz(bytes, 1 << 28));
  } catch (e) {
    return { error: e.message };
  }
}
const sakuzu = encoder.encode(SAKUZU);
const image = new Uint8Array(1000).fill(7);
compare("kmz", "doc.kml deflated", await kmzRows(zip([{ name: "files/a.png", data: image }, { name: "doc.kml", data: sakuzu }])), theirs("kml", SAKUZU));
compare("kmz", "first .kml stored", await kmzRows(zip([{ name: "x/first.KML", data: sakuzu, store: true }, { name: "second.kml", data: encoder.encode(KML("")) }])), theirs("kml", SAKUZU));
const big = KML(styles + (byLayer.building ?? []).map(placemark).join("\n"));
compare("kmz", "GSI buildings", await kmzRows(zip([{ name: "doc.kml", data: encoder.encode(big) }])), theirs("kml", big));
compare("kmz", "no .kml inside", await kmzRows(zip([{ name: "a.png", data: image }])), null);
compare("kmz", "truncated", await kmzRows(zip([{ name: "doc.kml", data: sakuzu }]).subarray(0, 200)), null);
compare("kmz", "not a zip", await kmzRows(sakuzu), null);
const bomb = zip([{ name: "doc.kml", data: new Uint8Array(1 << 22) }]);
compare("kmz", "inflates past the limit", await kmlOfKmz(bomb, 1 << 20).then(() => ({ rows: [] }), (e) => ({ error: e.message })), null);

let differ = 0;
let cases = 0;
for (const [group, r] of Object.entries(results)) {
  differ += r.differ;
  cases += r.cases;
  console.log(`${group}: ${r.cases} cases, ${r.rows} rows identical, ${r.bothRefuse} refused by both, ${r.differ} differ`);
}
const badDeviations = deviations.filter((d) => !d.ok).length;
console.log(`deviations: ${deviations.length} documented, ${badDeviations} not as documented`);
for (const f of failures) console.log("DIFF", JSON.stringify(f).slice(0, 1500));
console.log(`${cases} cases, ${differ + badDeviations} differ`);
const pkg = async (name) => JSON.parse(await readFile(path.join(ROOT, "bench/node_modules", name, "package.json"), "utf8")).version;
await writeFile(
  path.join(ROOT, "bench/results/xml-golden.json"),
  JSON.stringify({
    env: { node: process.version, togeojson: await pkg("@tmcw/togeojson"), xmldom: await pkg("@xmldom/xmldom"), tiles: TILES },
    normalized: [
      "togeojson's GeometryCollections are a row per member, with the feature's properties",
      "coordinates are x and y; a member with a coordinate that is not finite or missing is left out, as are empty rings",
      "nested property values (objects and arrays) are their JSON.stringify text",
      "lone surrogates in keys and values are U+FFFD, as UTF-8 carries text (TextEncoder's replacement)",
      "feature ids and bounding boxes are left out: tables carry neither",
      "togeojson's NetworkLink features (links to other documents, with their Region's box) are left out: mbmap/data reads none",
    ],
    results,
    deviations,
    differ: differ + badDeviations,
  }, null, 2) + "\n",
);
if (differ + badDeviations > 0) process.exit(1);
