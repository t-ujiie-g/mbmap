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
  Heatmap
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
/// One drawable layer with its type's paint (CSS pixels); `text` a symbol's layout;
/// `filter_id` shared by identically written filters (-1 for none); a fill's
/// `antialias` draws its outline, `outline_color` (or its color); `radius` a
/// circle's or heatmap's.
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
  heatmap : HeatmapPaint?
  join : Join
  cap : Cap
  miter_limit : Double
  round_limit : Double
  antialias : Bool
  outline_color : Expr?
  dasharray : Expr?
  gradient : Expr?
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
    "heatmap" => Heatmap
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
    Heatmap => "heatmap"
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
  let layer : StyleLayer = {
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
      // A heatmap's color is its ramp (`HeatmapPaint::color`).
      if kind is Heatmap {
        Map([])
      } else {
        paint
      },
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
    radius: if kind is Heatmap {
      paint_expr(paint, "heatmap-radius", ppath, NumberType, Json::number(30.0))
    } else {
      paint_expr(paint, "circle-radius", ppath, NumberType, Json::number(5.0))
    },
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
    heatmap: if kind is Heatmap {
      Some(parse_heatmap(paint, ppath))
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
    dasharray: if kind is Line {
      parse_dasharray(paint, ppath)
    } else {
      None
    },
    gradient: match paint.get("line-gradient") {
      Some(g) if kind is Line => {
        let path = "\{ppath}.line-gradient"
        let e = compile(g, expected=ColorType, path~)
        if data_driven(e) || e.reads_state() {
          raise Invalid(path~, "data expressions not supported")
        }
        Some(e)
      }
      _ => None
    },
  }
  // MapLibre allows `line-progress` in `line-gradient` only.
  let others = [
    layer.color,
    layer.opacity,
    layer.width,
    layer.radius,
    layer.stroke_width,
    layer.stroke_color,
    layer.stroke_opacity,
    layer.halo_color,
    layer.halo_width,
  ]
  for e in [layer.filter, layer.dasharray, layer.outline_color] {
    if e is Some(e) {
      others.push(e)
    }
  }
  if layer.heatmap is Some(h) {
    others.push(h.weight)
    others.push(h.intensity)
    if layer.radius.reads_state() || h.weight.reads_state() {
      raise Unsupported(path=ppath, "feature-state in heatmap paint")
    }
  }
  // And `heatmap-density` in `heatmap-color` only.
  if others.iter().any(e => e.reads_heatmap_density()) ||
    layer.gradient.map_or(false, e => e.reads_heatmap_density()) {
    raise Invalid(path~, "heatmap-density is only allowed in heatmap-color")
  }
  if layer.heatmap is Some(h) {
    others.push(h.color)
  }
  if others.iter().any(e => e.reads_line_progress()) {
    raise Invalid(path~, "line-progress is only allowed in line-gradient")
  }
  Some(layer)
}

///|
/// `line-dasharray`: an array of numbers, or an expression of zoom giving one
/// (MapLibre's cross-faded property; data-driven dashes are not supported).
fn parse_dasharray(
  paint : Map[String, Json],
  path : String,
) -> Expr? raise StyleError {
  let path = "\{path}.line-dasharray"
  let json = match paint.get("line-dasharray") {
    None => return None
    Some(Array(items) as a) if items.length() == 0 || items[0] is Number(_) =>
      Json::array([Json::string("literal"), a])
    Some(j) => j
  }
  let e = compile(json, path~)
  if data_driven(e) || e.reads_state() {
    raise Unsupported(path~, "data-driven dashes")
  }
  Some(e)
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
