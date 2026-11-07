///|
/// What a source draws from: vector, image (`raster`) or elevation (`raster-dem`)
/// tiles at URLs or made by the facade (`geotiff`, `reprojected`, without `tiles`), GeoJSON the map
/// cuts into tiles itself, or a picture placed by its corners (`image`, `video`, `canvas`).
#derive(Debug, Eq)
pub(all) enum SourceKind {
  Vector
  GeoJSON
  RasterDem
  Raster
  Image
}

///|
/// Where a feature's id comes from (MapLibre's `promoteId`): the tile's
/// feature id, one property, or a property per source layer (the feature id
/// for layers not listed).
#derive(Debug, Eq)
pub(all) enum PromoteId {
  FeatureId
  Property(String)
  ByLayer(Map[String, String])
}

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
        match s.get("clusterProperties") {
          Some(j) =>
            compile_cluster_properties(j, path="\{path}.clusterProperties")
            |> ignore
          None => ()
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
      max_zoom: source_zoom(s, "maxzoom", path, 18.0),
      tile_size: 512,
      encoding: Mapbox,
      buffer: buffer.to_int(),
      tolerance,
      promote_id: parse_promote_id(s, path),
      bounds: None,
      tms: false,
    })
  }
  // The facade checks their `coordinates` and loads their pictures.
  if s.get("type") is Some(String("image" | "video" | "canvas")) {
    return Some({
      id,
      kind: Image,
      tiles: [],
      min_zoom: 0,
      max_zoom: 22,
      tile_size: 512,
      encoding: Mapbox,
      buffer: 0,
      tolerance: 0.0,
      promote_id: FeatureId,
      bounds: None,
      tms: false,
    })
  }
  // GeoTIFF and reprojected tiles come from the facade (npm/src/geotiff-source.ts), which
  // completes a GeoTIFF's `bounds` and zooms from the file; a DEM's are Terrarium PNGs.
  if s.get("type") is Some(String("geotiff" | "reprojected") as kind) {
    let dem = match s.get("dem") {
      None | Some(False) => false
      Some(True) if kind == "geotiff" => true
      Some(True) => raise Unsupported(path="\{path}.dem", "only for geotiff")
      Some(_) => raise Invalid(path="\{path}.dem", "not a boolean")
    }
    let tile_size = number_or(s, "tileSize", path, 256.0).to_int()
    if !(tile_size is (256 | 512)) {
      raise Unsupported(path="\{path}.tileSize", "only 256 and 512")
    }
    let min_zoom = source_zoom(s, "minzoom", path, 0.0)
    let max_zoom = source_zoom(s, "maxzoom", path, 22.0)
    if min_zoom > max_zoom {
      raise Invalid(path="\{path}.minzoom", "above maxzoom")
    }
    return Some({
      id,
      kind: if dem {
        RasterDem
      } else {
        Raster
      },
      tiles: [],
      min_zoom,
      max_zoom,
      tile_size,
      encoding: if dem {
        Terrarium
      } else {
        Mapbox
      },
      buffer: 0,
      tolerance: 0.0,
      promote_id: FeatureId,
      bounds: parse_bounds(s),
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
  if urls.is_empty() {
    raise Invalid(path="\{path}.tiles", "empty")
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
  let min_zoom = source_zoom(s, "minzoom", path, 0.0)
  let max_zoom = source_zoom(s, "maxzoom", path, 22.0)
  if min_zoom > max_zoom {
    raise Invalid(path="\{path}.minzoom", "above maxzoom")
  }
  Some({
    id,
    kind,
    tiles,
    min_zoom,
    max_zoom,
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

///|
/// Deepest zoom tiles are asked for; a source going deeper is read as going this deep.
const MAX_SOURCE_ZOOM : Int32 = 24

///|
/// A source's `minzoom` or `maxzoom` as a tile zoom: 0 or more, at most `MAX_SOURCE_ZOOM`.
fn source_zoom(
  s : Map[String, Json],
  key : String,
  path : String,
  default : Double,
) -> Int32 raise StyleError {
  let z = number_or(s, key, path, default)
  guard z >= 0.0 else { raise Invalid(path="\{path}.\{key}", "not a zoom") }
  @cmp.minimum(z, MAX_SOURCE_ZOOM.to_double()).to_int()
}
