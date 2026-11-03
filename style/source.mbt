///|
/// What a source draws from: vector, image (`raster`) or elevation
/// (`raster-dem`) tiles at URLs, or GeoJSON the map cuts into tiles itself
/// (its data is handled outside the style, by the JS facade).
pub(all) enum SourceKind {
  Vector
  GeoJSON
  RasterDem
  Raster
} derive(Debug, Eq)

///|
/// Where a feature's id comes from (MapLibre's `promoteId`): the tile's
/// feature id, one property, or a property per source layer (the feature id
/// for layers not listed).
pub(all) enum PromoteId {
  FeatureId
  Property(String)
  ByLayer(Map[String, String])
} derive(Debug, Eq)

///|
/// The property that holds the ids of `source_layer`'s features, or None for
/// the tile's feature ids.
pub fn PromoteId::property(self : PromoteId, source_layer : String) -> String? {
  match self {
    FeatureId => None
    Property(p) => Some(p)
    ByLayer(m) => m.get(source_layer)
  }
}

///|
/// A source: tile URL templates `tile_size` pixels wide (a DEM's `encoding`) or a
/// GeoJSON source's `buffer` and `tolerance`; `promote_id` names feature ids,
/// `bounds` limit the tiles asked for, `tms` flips tile y.
pub struct Source {
  id : String
  kind : SourceKind
  tiles : Array[String]
  min_zoom : Int32
  max_zoom : Int32
  tile_size : Int32
  encoding : DemEncoding
  buffer : Int32
  tolerance : Double
  promote_id : PromoteId
  bounds : (Double, Double, Double, Double)?
  tms : Bool
}

///|
/// Whether tile z/x/y overlaps the source's `bounds` (MapLibre's
/// `TileBounds.contains`).
pub fn Source::covers(self : Source, z : Int32, x : Int32, y : Int32) -> Bool {
  guard self.bounds is Some((w, s, e, n)) else { return true }
  let size = (1 << z).to_double()
  let mx = (lng : Double) => (180.0 + lng) / 360.0 * size
  let my = (lat : Double) => {
    let l = @cmp.maximum(-85.051129, @cmp.minimum(85.051129, lat))
    (
      180.0 -
      180.0 /
      @math.PI *
      @math.ln(@math.tan(@math.PI / 4.0 + l * @math.PI / 360.0))
    ) /
    360.0 *
    size
  }
  x.to_double() >= mx(w).floor() &&
  x.to_double() < mx(e).ceil() &&
  y.to_double() >= my(n).floor() &&
  y.to_double() < my(s).ceil()
}

///|
/// A source's `bounds`: four numbers clamped to the world, as MapLibre takes
/// them; None for none or for malformed ones (MapLibre then uses the world).
fn parse_bounds(s : Map[String, Json]) -> (Double, Double, Double, Double)? {
  guard s.get("bounds")
    is Some(
      Array([Number(w, ..), Number(so, ..), Number(e, ..), Number(n, ..)])
    ) else {
    return None
  }
  Some(
    (
      @cmp.maximum(-180.0, w),
      @cmp.maximum(-90.0, so),
      @cmp.minimum(180.0, e),
      @cmp.minimum(90.0, n),
    ),
  )
}

///|
fn parse_promote_id(
  s : Map[String, Json],
  path : String,
) -> PromoteId raise StyleError {
  match s.get("promoteId") {
    None | Some(Null) => FeatureId
    Some(String(p)) => Property(p)
    Some(Object(o)) => {
      let m = Map([])
      for k, v in o {
        guard v is String(p) else {
          raise Invalid(path="\{path}.promoteId.\{k}", "not a string")
        }
        m[k] = p
      }
      ByLayer(m)
    }
    _ => raise Invalid(path="\{path}.promoteId", "not a string or an object")
  }
}

///|
fn parse_source(id : String, json : Json) -> Source? raise StyleError {
  let path = "sources.\{id}"
  guard json is Object(s) else { raise Invalid(path~, "not an object") }
  if s.get("type") is Some(String("geojson")) {
    if s.get("data") is None {
      raise Invalid(path="\{path}.data", "missing")
    }
    let buffer = number_or(s, "buffer", path, 128.0)
    if buffer < 0.0 || buffer > 512.0 {
      raise Invalid(path="\{path}.buffer", "not within 0-512")
    }
    let tolerance = number_or(s, "tolerance", path, 0.375)
    if tolerance < 0.0 {
      raise Invalid(path="\{path}.tolerance", "negative")
    }
    match s.get("cluster") {
      None | Some(False) => ()
      Some(True) =>
        if s.get("clusterProperties") is Some(_) {
          raise Unsupported(
            path="\{path}.clusterProperties",
            "cluster properties",
          )
        }
      Some(_) => raise Invalid(path="\{path}.cluster", "not a boolean")
    }
    if s.get("lineMetrics") is Some(v) && !(v is (True | False)) {
      raise Invalid(path="\{path}.lineMetrics", "not a boolean")
    }
    for key in ["clusterRadius", "clusterMaxZoom", "clusterMinPoints"] {
      if number_or(s, key, path, 0.0) < 0.0 {
        raise Invalid(path="\{path}.\{key}", "negative")
      }
    }
    return Some({
      id,
      kind: GeoJSON,
      tiles: [],
      min_zoom: 0,
      max_zoom: number_or(s, "maxzoom", path, 18.0).to_int(),
      tile_size: 512,
      encoding: Mapbox,
      buffer: buffer.to_int(),
      tolerance,
      promote_id: parse_promote_id(s, path),
      bounds: None,
      tms: false,
    })
  }
  let kind = match s.get("type") {
    Some(String("vector")) => Vector
    Some(String("raster-dem")) => RasterDem
    Some(String("raster")) => Raster
    _ => return None
  }
  guard s.get("tiles") is Some(Array(urls)) else {
    raise Unsupported(path~, "only sources with `tiles` are supported")
  }
  let tiles = []
  for u in urls {
    guard u is String(url) else {
      raise Invalid(path="\{path}.tiles", "not a string")
    }
    if !fetchable(url) {
      raise Unsupported(path="\{path}.tiles", "only http(s) tile URLs")
    }
    tiles.push(url)
  }
  let tile_size = number_or(s, "tileSize", path, 512.0).to_int()
  if !(tile_size is (128 | 256 | 512)) {
    raise Unsupported(path="\{path}.tileSize", "only 128, 256 and 512")
  }
  Some({
    id,
    kind,
    tiles,
    min_zoom: number_or(s, "minzoom", path, 0.0).to_int(),
    max_zoom: number_or(s, "maxzoom", path, 22.0).to_int(),
    tile_size,
    encoding: if kind is RasterDem {
      parse_encoding(s, path)
    } else {
      Mapbox
    },
    buffer: 0,
    tolerance: 0.0,
    promote_id: parse_promote_id(s, path),
    bounds: parse_bounds(s),
    tms: match string_or(s, "scheme", path, "xyz") {
      "xyz" => false
      "tms" => true
      x => raise Invalid(path="\{path}.scheme", "unknown scheme \{x}")
    },
  })
}

///|
/// Whether a tile URL template is relative or http(s), or an http(s) PMTiles
/// archive (`pmtiles://https://...`): other schemes (`javascript:`, `data:`,
/// `file:`, ...) are refused (AGENTS.md §8.3).
fn fetchable(url : String) -> Bool {
  if url.has_prefix("pmtiles://") {
    let rest = url[10:].to_lower()
    return rest.has_prefix("http://") || rest.has_prefix("https://")
  }
  for i, c in url {
    match c {
      'a'..<='z' | 'A'..<='Z' => ()
      '0'..<='9' | '+' | '-' | '.' if i > 0 => ()
      ':' if i > 0 => {
        let scheme = url[:i].to_lower()
        return scheme == "http" || scheme == "https"
      }
      _ => return true
    }
  }
  true
}
