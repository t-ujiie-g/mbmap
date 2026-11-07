// GML 2, 3.1 and 3.2 feature collections (WFS GetFeature answers) as GeoJSON in EPSG:4326 longitude, latitude.
// Properties are read as OpenLayers' GMLBase reads them; axis order follows the srsName, which OpenLayers does not.
import { epsgCode, northFirst } from "./common.ts";
import type { FeatureCollection } from "./features.ts";
import { children, first, parseXml } from "./xml.ts";

const GML = /^http:\/\/www\.opengis\.net\/gml/;
const XSI = "http://www.w3.org/2001/XMLSchema-instance";
const MEMBERS = new Set(["featureMember", "featureMembers", "member"]);
// The GML geometries read, by local name.
const GEOMETRIES = new Set([
  "Point", "LineString", "LinearRing", "Curve", "Polygon", "Surface",
  "MultiPoint", "MultiLineString", "MultiCurve", "MultiPolygon", "MultiSurface", "MultiGeometry",
]);

interface Geometry {
  type: string;
  coordinates?: unknown;
  geometries?: Geometry[];
}

/**
 * Whether a srsName lists northing first: URNs and OGC URLs by the CRS's own order, GML 2's `…epsg.xml#` URLs never; a bare
 * `EPSG:4326` as asked (`asked`: WFS 1.1 and 2.0 servers write the order of the URN they were asked for under it).
 */
export function srsNorthFirst(srs: string, asked: boolean): boolean {
  if (/^(urn:|http:\/\/www\.opengis\.net\/def\/crs\/)/i.test(srs)) return northFirst(srs);
  return /^EPSG:\d+$/i.test(srs) ? asked && northFirst(srs) : false;
}

/**
 * The features of a GML document (`xml`) as GeoJSON; `latitudeFirst` whether a bare `EPSG:4326` (or no srsName) is latitude
 * first, as it is when asked for as `urn:ogc:def:crs:EPSG::4326`. Only EPSG:4326 (and CRS84) is read: another srsName throws.
 */
export function readGml(xml: string | Document, latitudeFirst = false): FeatureCollection {
  const defaultSrs = "EPSG:4326";
  const root = parseXml(xml, "GML");
  const features: unknown[] = [];
  const visit = (e: Element) => {
    for (const c of children(e)) {
      if (MEMBERS.has(c.localName)) for (const f of children(c)) features.push(feature(f, defaultSrs, latitudeFirst));
      else if (c.localName === "additionalObjects" || c.localName === "FeatureCollection" || c.localName === "SimpleFeatureCollection") visit(c);
    }
  };
  visit(root);
  return { type: "FeatureCollection", features };
}

function feature(e: Element, srs: string, latitudeFirst: boolean): unknown {
  let geometry: Geometry | null = null;
  const properties = values(e, srs, latitudeFirst, (g) => {
    geometry ??= g;
  });
  const id = e.getAttribute("fid") || e.getAttributeNS("http://www.opengis.net/gml/3.2", "id") || e.getAttributeNS("http://www.opengis.net/gml", "id") || e.getAttribute("gml:id");
  return { type: "Feature", ...(id && { id }), geometry, properties };
}

// The properties of `e` as OpenLayers reads them: text of leaves, objects of the rest, repeated names as arrays; a
// geometry goes to `found` instead, and boundedBy is left out.
function values(e: Element, srs: string, latitudeFirst: boolean, found: (g: Geometry) => void): Record<string, unknown> {
  const out: Record<string, unknown> = Object.create(null);
  for (const c of children(e)) {
    const name = c.localName;
    if (name === "boundedBy") continue;
    let value: unknown;
    const kids = children(c);
    if (kids.length === 0) {
      const t = c.textContent ?? "";
      value = c.getAttributeNS(XSI, "nil") === "true" ? null : /^\s*$/.test(t) ? undefined : t;
    } else if (kids.length === 1 && GML.test(kids[0].namespaceURI ?? "") && GEOMETRIES.has(kids[0].localName)) {
      found(geometryOf(kids[0], srsOf(kids[0]) ?? srs, latitudeFirst));
      continue;
    } else {
      value = values(c, srs, latitudeFirst, found);
    }
    if (name in out) out[name] = [...(Array.isArray(out[name]) ? (out[name] as unknown[]) : [out[name]]), value];
    else out[name] = value;
  }
  return out;
}

const srsOf = (e: Element): string | undefined => e.getAttribute("srsName") ?? undefined;

// The positions under `e` (pos, posList, coordinates, coord), longitude first.
function positions(e: Element, srs: string, latitudeFirst: boolean): number[][] {
  if (epsgCode(srs) !== 4326) {
    throw new Error(`mbmap: services: GML in ${srs} is not read; ask for EPSG:4326`);
  }
  const swap = srsNorthFirst(srs, latitudeFirst);
  const out: number[][] = [];
  const push = (a: number, b: number) => out.push(swap ? [b, a] : [a, b]);
  for (const c of children(e)) {
    const name = c.localName;
    if (name === "pos" || name === "posList") {
      // 2 to 4 values a position (GML's srsDimension); anything else is read as 2, so the loop always moves on.
      const given = Number(c.getAttribute("srsDimension") ?? e.getAttribute("srsDimension") ?? 2);
      const dim = Number.isInteger(given) && given >= 2 && given <= 4 ? given : 2;
      const v = (c.textContent ?? "").trim().split(/\s+/).filter(Boolean).map(Number);
      for (let i = 0; i + 1 < v.length; i += dim) push(v[i], v[i + 1]);
    } else if (name === "coordinates") {
      const cs = c.getAttribute("cs") ?? ",";
      const ts = c.getAttribute("ts") ?? " ";
      const dec = c.getAttribute("decimal") ?? ".";
      const tuples = (c.textContent ?? "").trim().split(ts === " " ? /\s+/ : ts).filter(Boolean);
      for (const t of tuples) {
        const [a, b] = t.split(cs).map((s) => Number(dec === "." ? s : s.replace(dec, ".")));
        push(a, b);
      }
    } else if (name === "coord") {
      push(Number(first(c, "X")?.textContent), Number(first(c, "Y")?.textContent));
    } else if (name === "pointMember" || name === "pointMembers" || name === "Point") {
      out.push(...positions(c, srsOf(c) ?? srs, latitudeFirst));
    }
  }
  return out;
}

// A ring's positions: under exterior/interior (or GML 2's outer/innerBoundaryIs), a LinearRing or a Ring of curves.
function ring(boundary: Element, srs: string, latitudeFirst: boolean): number[][] {
  const r = children(boundary)[0];
  if (!r) return [];
  if (r.localName === "Ring") return children(r, "curveMember").flatMap((m) => children(m).flatMap((g) => line(g, srs, latitudeFirst)));
  return positions(r, srsOf(r) ?? srs, latitudeFirst);
}

// A curve's positions: a LineString, or a Curve's segments one after another.
function line(e: Element, srs: string, latitudeFirst: boolean): number[][] {
  const s = srsOf(e) ?? srs;
  if (e.localName === "Curve") return children(children(e, "segments")[0]).flatMap((seg) => positions(seg, s, latitudeFirst));
  return positions(e, s, latitudeFirst);
}

function polygon(e: Element, srs: string, latitudeFirst: boolean): number[][][] {
  const s = srsOf(e) ?? srs;
  const patches = e.localName === "Surface" ? children(children(e, "patches")[0]) : [e];
  return patches.flatMap((p) =>
    children(p)
      .filter((b) => /^(exterior|interior|outerBoundaryIs|innerBoundaryIs)$/.test(b.localName))
      .map((b) => ring(b, s, latitudeFirst)),
  );
}

// The members of a Multi geometry: the children of each `*Member` and `*Members` child.
const members = (e: Element): Element[] => children(e).flatMap((m) => (/Members?$/.test(m.localName) ? children(m) : []));

function geometryOf(e: Element, srs: string, latitudeFirst: boolean): Geometry {
  const s = srsOf(e) ?? srs;
  switch (e.localName) {
    case "Point":
      return { type: "Point", coordinates: positions(e, s, latitudeFirst)[0] ?? [] };
    case "LineString":
    case "LinearRing":
    case "Curve":
      return { type: "LineString", coordinates: line(e, s, latitudeFirst) };
    case "Polygon":
    case "Surface":
      return { type: "Polygon", coordinates: polygon(e, s, latitudeFirst) };
    case "MultiPoint":
      return { type: "MultiPoint", coordinates: members(e).map((m) => positions(m, srsOf(m) ?? s, latitudeFirst)[0]) };
    case "MultiLineString":
    case "MultiCurve":
      return { type: "MultiLineString", coordinates: members(e).map((m) => line(m, s, latitudeFirst)) };
    case "MultiPolygon":
    case "MultiSurface":
      return { type: "MultiPolygon", coordinates: members(e).map((m) => polygon(m, s, latitudeFirst)) };
    default:
      return { type: "GeometryCollection", geometries: members(e).map((m) => geometryOf(m, s, latitudeFirst)) };
  }
}
