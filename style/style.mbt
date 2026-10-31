///|
/// Unusable style JSON. `path` is a JSON pointer-like location, e.g.
/// `layers[3].paint.line-width`.
pub(all) suberror StyleError {
  Invalid(path~ : String, String)
  Unsupported(path~ : String, String)
} derive(Debug, Eq)

///|
pub(all) enum LayerKind {
  Background
  Fill
  Line
  Circle
} derive(Debug, Eq)

///|
pub(all) enum Join {
  Miter
  Bevel
  Round
} derive(Debug, Eq)

///|
pub(all) enum Cap {
  Butt
  Square
  Round
} derive(Debug, Eq)

///|
/// One drawable layer. `filter` (None: every feature) selects features;
/// `filter_id` is shared by the layers whose filters are written identically
/// (-1 without a filter), so they can be compared without walking `Expr`s;
/// `color` and `opacity` are the layer type's paint values (`fill-*`,
/// `line-*`, `circle-*` or `background-*`); `width` is `line-width`;
/// `radius` and the `stroke_*` values are the `circle-*` ones. Sizes are in
/// CSS pixels.
pub struct StyleLayer {
  id : String
  kind : LayerKind
  source : String
  source_layer : String
  min_zoom : Double
  max_zoom : Double
  filter : Expr?
  filter_id : Int32
  color : Expr
  opacity : Expr
  width : Expr
  radius : Expr
  stroke_width : Expr
  stroke_color : Expr
  stroke_opacity : Expr
  join : Join
  cap : Cap
  miter_limit : Double
  round_limit : Double
}

///|
/// What a source draws from: vector tiles at URLs, or GeoJSON the map cuts
/// into tiles itself (its data is handled outside the style, by the JS
/// facade).
pub(all) enum SourceKind {
  Vector
  GeoJSON
} derive(Debug, Eq)

///|
/// A source layers draw from. `tiles` are the URL templates of a vector
/// source (empty for GeoJSON). For GeoJSON, `buffer` (pixels of a 512 px
/// tile kept around each tile) and `tolerance` (simplification in pixels)
/// are MapLibre's GeoJSON source options.
pub struct Source {
  id : String
  kind : SourceKind
  tiles : Array[String]
  min_zoom : Int32
  max_zoom : Int32
  buffer : Int32
  tolerance : Double
}

///|
/// The drawable part of a MapLibre style: vector and GeoJSON sources, and
/// the background, fill, line and circle layers in drawing order. Other
/// source and layer types are skipped.
pub struct Style {
  sources : Array[Source]
  layers : Array[StyleLayer]
}

///|
pub fn Style::source(self : Style, id : String) -> Source? {
  for s in self.sources {
    if s.id == id {
      return Some(s)
    }
  }
  None
}

///|
/// Parses a style. Unsupported values (expressions or layer properties
/// outside the supported subset) are an error rather than being ignored.
pub fn Style::parse(text : StringView) -> Style raise StyleError {
  let json = @json.parse(text, max_nesting_depth=64) catch {
    e => raise Invalid(path="", "not JSON: \{e}")
  }
  Style::from_json(json)
}

///|
/// `Style::parse` for an already parsed document.
pub fn Style::from_json(json : Json) -> Style raise StyleError {
  guard json is Object(root) else { raise Invalid(path="", "not an object") }
  let sources = []
  if root.get("sources") is Some(Object(map)) {
    for id, s in map {
      if parse_source(id, s) is Some(source) {
        sources.push(source)
      }
    }
  }
  let layers = []
  guard root.get("layers") is Some(Array(list)) else {
    raise Invalid(path="layers", "missing")
  }
  let filters : Array[Json] = []
  for i, l in list {
    let filter_id = match l {
      Object(o) if o.get("filter") is Some(f) =>
        match filters.search(f) {
          Some(id) => id
          None => {
            filters.push(f)
            filters.length() - 1
          }
        }
      _ => -1
    }
    if parse_layer("layers[\{i}]", l, filter_id) is Some(layer) {
      layers.push(layer)
    }
  }
  { sources, layers, }
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
    if s.get("cluster") is Some(True) {
      raise Unsupported(path="\{path}.cluster", "clustering")
    }
    return Some({
      id,
      kind: GeoJSON,
      tiles: [],
      min_zoom: 0,
      max_zoom: number_or(s, "maxzoom", path, 18.0).to_int(),
      buffer: buffer.to_int(),
      tolerance,
    })
  }
  guard s.get("type") is Some(String("vector")) else { return None }
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
  Some({
    id,
    kind: Vector,
    tiles,
    min_zoom: number_or(s, "minzoom", path, 0.0).to_int(),
    max_zoom: number_or(s, "maxzoom", path, 22.0).to_int(),
    buffer: 0,
    tolerance: 0.0,
  })
}

///|
/// Whether a tile URL template is relative or http(s): other schemes
/// (`javascript:`, `data:`, `file:`, ...) are refused (AGENTS.md §8.3).
fn fetchable(url : String) -> Bool {
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
fn number_or(
  obj : Map[String, Json],
  key : String,
  path : String,
  default : Double,
) -> Double raise StyleError {
  match obj.get(key) {
    None => default
    Some(Number(n, ..)) => n
    Some(Array(_)) => raise Unsupported(path="\{path}.\{key}", "expressions")
    Some(_) => raise Invalid(path="\{path}.\{key}", "not a number")
  }
}

///|
fn string_or(
  obj : Map[String, Json],
  key : String,
  path : String,
  default : String,
) -> String raise StyleError {
  match obj.get(key) {
    None => default
    Some(String(s)) => s
    Some(Array(_)) => raise Unsupported(path="\{path}.\{key}", "expressions")
    Some(_) => raise Invalid(path="\{path}.\{key}", "not a string")
  }
}

///|
fn object_at(
  obj : Map[String, Json],
  key : String,
  path : String,
) -> Map[String, Json] raise StyleError {
  match obj.get(key) {
    None => Map([])
    Some(Object(m)) => m
    Some(_) => raise Invalid(path="\{path}.\{key}", "not an object")
  }
}

///|
fn parse_layer(
  path : String,
  json : Json,
  filter_id : Int32,
) -> StyleLayer? raise StyleError {
  guard json is Object(l) else { raise Invalid(path~, "not an object") }
  let kind = match string_or(l, "type", path, "") {
    "background" => Background
    "fill" => Fill
    "line" => Line
    "circle" => Circle
    "" => raise Invalid(path="\{path}.type", "missing")
    _ => return None
  }
  let paint = object_at(l, "paint", path)
  let layout = object_at(l, "layout", path)
  let ppath = "\{path}.paint"
  let lpath = "\{path}.layout"
  if string_or(layout, "visibility", lpath, "visible") == "none" {
    return None
  }
  let prefix = match kind {
    Background => "background"
    Fill => "fill"
    Line => "line"
    Circle => "circle"
  }
  let join = match string_or(layout, "line-join", lpath, "miter") {
    "miter" => Join::Miter
    "bevel" => Bevel
    "round" => Round
    j => raise Invalid(path="\{lpath}.line-join", "unknown join \{j}")
  }
  let cap = match string_or(layout, "line-cap", lpath, "butt") {
    "butt" => Cap::Butt
    "square" => Square
    "round" => Round
    c => raise Invalid(path="\{lpath}.line-cap", "unknown cap \{c}")
  }
  Some({
    id: string_or(l, "id", path, ""),
    kind,
    source: string_or(l, "source", path, ""),
    source_layer: string_or(l, "source-layer", path, ""),
    min_zoom: number_or(l, "minzoom", path, 0.0),
    max_zoom: number_or(l, "maxzoom", path, 24.0),
    filter: match l.get("filter") {
      None => None
      Some(f) => Some(compile(f, expected=BoolType, path="\{path}.filter"))
    },
    filter_id,
    color: paint_expr(
      paint,
      "\{prefix}-color",
      ppath,
      ColorType,
      Json::string("#000000"),
    ),
    opacity: paint_expr(
      paint,
      "\{prefix}-opacity",
      ppath,
      NumberType,
      Json::number(1.0),
    ),
    width: paint_expr(paint, "line-width", ppath, NumberType, Json::number(1.0)),
    radius: paint_expr(
      paint,
      "circle-radius",
      ppath,
      NumberType,
      Json::number(5.0),
    ),
    stroke_width: paint_expr(
      paint,
      "circle-stroke-width",
      ppath,
      NumberType,
      Json::number(0.0),
    ),
    stroke_color: paint_expr(
      paint,
      "circle-stroke-color",
      ppath,
      ColorType,
      Json::string("#000000"),
    ),
    stroke_opacity: paint_expr(
      paint,
      "circle-stroke-opacity",
      ppath,
      NumberType,
      Json::number(1.0),
    ),
    join,
    cap,
    miter_limit: number_or(layout, "line-miter-limit", lpath, 2.0),
    round_limit: number_or(layout, "line-round-limit", lpath, 1.05),
  })
}

///|
fn paint_expr(
  paint : Map[String, Json],
  key : String,
  path : String,
  expected : Expected,
  default : Json,
) -> Expr raise StyleError {
  compile(paint.get(key).unwrap_or(default), expected~, path="\{path}.\{key}")
}

///|
/// A one-line description, e.g. `layers[3].paint.line-width: expressions`.
pub fn StyleError::message(self : StyleError) -> String {
  match self {
    Invalid(path~, m) => if path == "" { m } else { "\{path}: \{m}" }
    Unsupported(path~, m) =>
      if path == "" {
        "unsupported: \{m}"
      } else {
        "\{path}: unsupported: \{m}"
      }
  }
}
