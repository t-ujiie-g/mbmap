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
/// `color`, `opacity` and `width` are the layer type's paint values
/// (`fill-*`, `line-*` or `background-*`), `width` in CSS pixels.
pub struct StyleLayer {
  id : String
  kind : LayerKind
  source : String
  source_layer : String
  min_zoom : Double
  max_zoom : Double
  filter : Expr?
  color : Expr
  opacity : Expr
  width : Expr
  join : Join
  cap : Cap
  miter_limit : Double
  round_limit : Double
}

///|
pub struct VectorSource {
  id : String
  tiles : Array[String]
  min_zoom : Int32
  max_zoom : Int32
}

///|
/// The drawable part of a MapLibre style: vector sources and the background,
/// fill and line layers in drawing order. Other layer types are skipped.
pub struct Style {
  sources : Array[VectorSource]
  layers : Array[StyleLayer]
}

///|
pub fn Style::source(self : Style, id : String) -> VectorSource? {
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
  for i, l in list {
    if parse_layer("layers[\{i}]", l) is Some(layer) {
      layers.push(layer)
    }
  }
  { sources, layers, }
}

///|
fn parse_source(id : String, json : Json) -> VectorSource? raise StyleError {
  let path = "sources.\{id}"
  guard json is Object(s) else { raise Invalid(path~, "not an object") }
  guard s.get("type") is Some(String("vector")) else { return None }
  guard s.get("tiles") is Some(Array(urls)) else {
    raise Unsupported(path~, "only sources with `tiles` are supported")
  }
  let tiles = []
  for u in urls {
    guard u is String(url) else {
      raise Invalid(path="\{path}.tiles", "not a string")
    }
    tiles.push(url)
  }
  Some({
    id,
    tiles,
    min_zoom: number_or(s, "minzoom", path, 0.0).to_int(),
    max_zoom: number_or(s, "maxzoom", path, 22.0).to_int(),
  })
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
fn parse_layer(path : String, json : Json) -> StyleLayer? raise StyleError {
  guard json is Object(l) else { raise Invalid(path~, "not an object") }
  let kind = match string_or(l, "type", path, "") {
    "background" => Background
    "fill" => Fill
    "line" => Line
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
