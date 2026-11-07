import { type Bounds, resolved, validBounds } from "./common.ts";
import { at, attributeBox, children, corners, first, href, optional, parseXml, text, texts } from "./xml.ts";

/** A feature type: `bounds` from its WGS84BoundingBox (1.0.0's LatLongBoundingBox); CRSs as written. */
export interface WFSFeatureType {
  name: string;
  title?: string;
  abstract?: string;
  defaultCrs?: string;
  otherCrs: string[];
  bounds?: Bounds;
  outputFormats: string[];
}

/** What a WFS 1.0.0, 1.1.0 or 2.0 GetCapabilities document says; `getFeatureUrl` is the HTTP GET endpoint. */
export interface WFSCapabilities {
  service: "WFS";
  version: string;
  title: string;
  getFeatureUrl?: string;
  outputFormats: string[];
  featureTypes: WFSFeatureType[];
}

/** Reads a WFS GetCapabilities document; `base`: its URL, which relative URLs in it are resolved against. */
export function readWFSCapabilities(xml: string | Document, base?: string): WFSCapabilities {
  const root = parseXml(xml, "WFS capabilities");
  if (root.localName !== "WFS_Capabilities") throw new Error("mbmap: services: not a WFS capabilities document");
  const version = root.getAttribute("version") ?? "";
  const v10 = version.startsWith("1.0");
  const crs = version.startsWith("2.") ? "CRS" : "SRS";
  const operation = children(first(root, "OperationsMetadata"), "Operation").find((o) => o.getAttribute("name") === "GetFeature");
  const outputFormats = v10
    ? children(at(root, "Capability", "Request", "GetFeature", "ResultFormat")).map((e) => e.localName)
    : children(operation, "Parameter").filter((p) => p.getAttribute("name") === "outputFormat").flatMap((p) => [...p.getElementsByTagNameNS("*", "Value")].map(text));
  const getFeature = v10
    ? at(root, "Capability", "Request", "GetFeature", "DCPType", "HTTP", "Get")?.getAttribute("onlineResource") || undefined
    : href(at(operation, "DCP", "HTTP", "Get"));
  return {
    service: "WFS",
    version,
    title: text(at(root, v10 ? "Service" : "ServiceIdentification", "Title")),
    getFeatureUrl: getFeature && resolved(getFeature, base),
    outputFormats,
    featureTypes: children(first(root, "FeatureTypeList"), "FeatureType").map((f) => {
      const latLong = first(f, "LatLongBoundingBox");
      const wgs84 = first(f, "WGS84BoundingBox");
      return {
        name: text(first(f, "Name")),
        title: optional(f, "Title"),
        abstract: optional(f, "Abstract"),
        defaultCrs: optional(f, v10 ? "SRS" : `Default${crs}`),
        otherCrs: v10 ? [] : texts(f, `Other${crs}`),
        bounds: validBounds(
          latLong ? attributeBox(latLong) : wgs84 ? corners(wgs84) : undefined,
        ),
        outputFormats: texts(first(f, "OutputFormats"), "Format"),
      };
    }),
  };
}
