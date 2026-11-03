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
  Symbol
  Hillshade
  FillExtrusion
  Raster
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
/// One drawable layer with its type's paint (sizes in CSS pixels); `text` is a
/// symbol layer's layout. `filter_id` is shared by layers whose filters are
/// written identically (-1 without one), so they compare without walking `Expr`s.
/// A fill's `antialias` draws its outline, `outline_color` (or its color).
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
  halo_color : Expr
  halo_width : Expr
  text : TextLayout?
  hillshade : HillshadePaint?
  extrusion : ExtrusionPaint?
  raster : RasterPaint?
  join : Join
  cap : Cap
  miter_limit : Double
  round_limit : Double
  antialias : Bool
  outline_color : Expr?
}

///|
/// The drawable part of a MapLibre style: vector and GeoJSON sources, and
/// the background, fill, line, circle and symbol layers in drawing order.
/// Other source and layer types are skipped.
pub struct Style {
  sources : Array[Source]
  layers : Array[StyleLayer]
  terrain : Terrain?
  sky : Sky?
  light : Light
}

///|
/// The style's `terrain`: the `raster-dem` source the ground is raised from
/// and how much heights are exaggerated.
pub struct Terrain {
  source : String
  exaggeration : Double
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
  let terrain = match root.get("terrain") {
    None | Some(Null) => None
    Some(Object(t)) => {
      let source = string_or(t, "source", "terrain", "")
      guard sources.iter().any(s => s.id == source && s.kind is RasterDem) else {
        raise Invalid(
          path="terrain.source",
          "not a raster-dem source: \{source}",
        )
      }
      let exaggeration = number_or(t, "exaggeration", "terrain", 1.0)
      if exaggeration < 0.0 {
        raise Invalid(path="terrain.exaggeration", "negative")
      }
      Some({ source, exaggeration, })
    }
    Some(_) => raise Invalid(path="terrain", "not an object")
  }
  {
    sources,
    layers,
    terrain,
    sky: parse_sky(root.get("sky")),
    light: parse_light(root.get("light")),
  }
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
    "symbol" => Symbol
    "hillshade" => Hillshade
    "fill-extrusion" => FillExtrusion
    "raster" => Raster
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
    Symbol => "text"
    Hillshade => "hillshade"
    FillExtrusion => "fill-extrusion"
    Raster => "raster"
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
      Some(f) => {
        let e = compile(f, expected=BoolType, path="\{path}.filter")
        if e.reads_state() {
          raise Invalid(
            path="\{path}.filter",
            "feature-state is only allowed in paint properties",
          )
        }
        Some(e)
      }
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
    halo_color: paint_expr(
      paint,
      "text-halo-color",
      ppath,
      ColorType,
      Json::string("rgba(0, 0, 0, 0)"),
    ),
    halo_width: paint_expr(
      paint,
      "text-halo-width",
      ppath,
      NumberType,
      Json::number(0.0),
    ),
    text: if kind is Symbol {
      Some(parse_text(layout, lpath))
    } else {
      None
    },
    hillshade: if kind is Hillshade {
      Some(parse_hillshade(paint, ppath))
    } else {
      None
    },
    extrusion: if kind is FillExtrusion {
      Some(parse_extrusion(paint, ppath))
    } else {
      None
    },
    raster: if kind is Raster {
      Some(parse_raster(paint, ppath))
    } else {
      None
    },
    join,
    cap,
    miter_limit: number_or(layout, "line-miter-limit", lpath, 2.0),
    round_limit: number_or(layout, "line-round-limit", lpath, 1.05),
    antialias: kind is Fill && bool_or(paint, "fill-antialias", ppath, true),
    outline_color: match paint.get("fill-outline-color") {
      Some(c) if kind is Fill =>
        Some(compile(c, expected=ColorType, path="\{ppath}.fill-outline-color"))
      _ => None
    },
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
