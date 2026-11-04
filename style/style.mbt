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
  ColorRelief
  Custom
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
/// One drawable layer with its type's paint (CSS pixels); `text` a symbol's layout
/// (`icon`, `icon_paint` with `icon-image`); `filter_id` shared by identically written
/// filters (-1 for none); a fill's `antialias` draws its outline, `outline_color` (or its
/// color); `radius` a circle's or heatmap's; `blur` a symbol's `text-halo-blur`; the rest
/// are the Style Spec's of the same names (`translate_viewport`: `*-translate-anchor` viewport).
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
  icon : IconLayout?
  icon_paint : IconPaint?
  hillshade : HillshadePaint?
  relief : ColorReliefPaint?
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
  pattern : Expr?
  gap_width : Expr
  offset : Expr
  blur : Expr
  translate : (Double, Double)
  translate_viewport : Bool
  scale_with_map : Bool
  pitch_with_map : Bool
  sort_key : Expr?
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
  warnings : Array[StyleError]
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
/// Parses a style. Strict, anything unsupported raises; otherwise it is left out
/// (a property defaults, an undrawable layer or source is dropped) and listed in
/// `warnings`. Invalid values raise either way.
pub fn Style::parse(
  text : StringView,
  strict~ : Bool = true,
) -> Style raise StyleError {
  let json = @json.parse(text, max_nesting_depth=64) catch {
    e => raise Invalid(path="", "not JSON: \{e}")
  }
  Style::from_json(json, strict~)
}

///|
/// `Style::parse` for an already parsed document; `global-state` takes the
/// defaults of its `state`.
pub fn Style::from_json(
  json : Json,
  strict~ : Bool = true,
) -> Style raise StyleError {
  with_global_state(state_defaults(json), () => style_of(json, strict))
}

///|
fn style_of(json : Json, strict : Bool) -> Style raise StyleError {
  guard json is Object(root) else { raise Invalid(path="", "not an object") }
  let issues = { strict, warnings: [], }
  let sources = []
  let dropped = []
  if root.get("sources") is Some(Object(map)) {
    for id, s in map {
      let before = issues.warnings.length()
      match leniently(s, "sources.\{id}", issues, s => parse_source(id, s)) {
        Some(source) => sources.push(source)
        None => if issues.warnings.length() > before { dropped.push(id) }
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
    let path = "layers[\{i}]"
    if l is Object(o) &&
      o.get("source") is Some(String(source)) &&
      dropped.contains(source) {
      issues.report(Unsupported(path~, "its source \{source} is not drawn"))
      continue
    }
    if leniently(l, path, issues, l => parse_layer(path, l, filter_id))
      is Some(layer) {
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
    light: parse_light(root.get("light")) catch {
      Unsupported(_) as e => {
        issues.report(e)
        parse_light(None)
      }
      e => raise e
    },
    warnings: issues.warnings,
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
    "color-relief" => ColorRelief
    "custom" => Custom
    "" => raise Invalid(path="\{path}.type", "missing")
    t => raise Unsupported(path="\{path}.type", "layer type \{t}")
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
    ColorRelief => "color-relief"
    Custom => "custom"
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
  let (translate, translate_viewport) = match kind {
    Fill | Line | Circle | FillExtrusion | Symbol =>
      parse_translate(paint, "\{prefix}-translate", ppath)
    _ => ((0.0, 0.0), false)
  }
  let text = if kind is Symbol { Some(parse_text(layout, lpath)) } else { None }
  let (icon, icon_paint) = match text {
    Some(t) =>
      match parse_icon(layout, paint, lpath, ppath, t.placement) {
        Some((l, p)) => (Some(l), Some(p))
        None => (None, None)
      }
    None => (None, None)
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
    text,
    icon,
    icon_paint,
    hillshade: if kind is Hillshade {
      Some(parse_hillshade(paint, ppath))
    } else {
      None
    },
    relief: None,
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
    pattern: match (kind, paint.get("\{prefix}-pattern")) {
      (Fill | Background | Line | FillExtrusion, Some(p)) =>
        Some(compile(p, expected=StringType, path="\{ppath}.\{prefix}-pattern"))
      _ => None
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
    gap_width: if kind is Line {
      paint_expr(paint, "line-gap-width", ppath, NumberType, Json::number(0.0))
    } else {
      Lit(Num(0.0))
    },
    offset: if kind is Line {
      paint_expr(paint, "line-offset", ppath, NumberType, Json::number(0.0))
    } else {
      Lit(Num(0.0))
    },
    blur: match kind {
      Symbol =>
        paint_expr(
          paint,
          "text-halo-blur",
          ppath,
          NumberType,
          Json::number(0.0),
        )
      Line | Circle => {
        let key = "\{prefix}-blur"
        let e = paint_expr(paint, key, ppath, NumberType, Json::number(0.0))
        if data_driven(e) || e.reads_state() {
          raise Unsupported(path="\{ppath}.\{key}", "data expressions")
        }
        e
      }
      _ => Lit(Num(0.0))
    },
    translate,
    translate_viewport,
    scale_with_map: kind is Circle &&
    alignment(paint, "circle-pitch-scale", ppath) == "map",
    sort_key: match (kind, layout.get("\{prefix}-sort-key")) {
      (Fill | Line | Circle, Some(j)) => {
        let path = "\{lpath}.\{prefix}-sort-key"
        let e = compile(j, expected=NumberType, path~)
        if e.reads_state() {
          raise Invalid(
            path~,
            "feature-state is only allowed in paint properties",
          )
        }
        Some(e)
      }
      _ => None
    },
    pitch_with_map: kind is Circle &&
    alignment(paint, "circle-pitch-alignment", ppath, default="viewport") ==
    "map",
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
    layer.gap_width,
    layer.offset,
    layer.blur,
  ]
  for e in [layer.filter, layer.dasharray, layer.outline_color, layer.sort_key] {
    if e is Some(e) {
      others.push(e)
    }
  }
  if layer.icon_paint is Some(p) {
    others.push_iter(p.exprs().iter())
  }
  if layer.heatmap is Some(h) {
    others.push(h.weight)
    others.push(h.intensity)
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
  // And `elevation` in `color-relief-color` only (`others[0]`).
  let elevation_free = if kind is ColorRelief { others[1:] } else { others[:] }
  if elevation_free.iter().any(e => e.reads_elevation()) ||
    layer.gradient.map_or(false, e => e.reads_elevation()) {
    raise Invalid(path~, "elevation is only allowed in color-relief-color")
  }
  if layer.feature_dashes() is Some(_) && layer.paints_by_group() {
    raise Unsupported(
      path="\{ppath}.line-dasharray",
      "data-driven dashes in layers drawn by groups",
    )
  }
  // The main thread evaluates paint drawn by groups without the geometry.
  if kind is (Symbol | FillExtrusion) || layer.paints_by_group() {
    for key, j in paint {
      if !(key is ("fill-extrusion-base" | "fill-extrusion-height")) &&
        reads_geometry_json(j, 0) {
        raise Unsupported(
          path="\{ppath}.\{key}",
          "within and distance in paint drawn by groups",
        )
      }
    }
  }
  if kind is ColorRelief {
    return Some({
      ..layer,
      relief: Some(parse_color_relief(layer.color, paint, ppath)),
    })
  }
  Some(layer)
}

///|
/// Whether the expression `json` uses `within` or `distance` (`depth` bounds
/// the walk as compiling does).
fn reads_geometry_json(json : Json, depth : Int32) -> Bool {
  match json {
    Array([String("within" | "distance"), ..]) => true
    Array(items) if depth <= MAX_EXPR_DEPTH =>
      items.iter().any(j => reads_geometry_json(j, depth + 1))
    _ => false
  }
}

///|
/// `line-dasharray`: an array of numbers, or an expression giving one (MapLibre's
/// cross-faded property; feature-state is not supported).
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
  if e.reads_state() {
    raise Unsupported(path~, "feature-state in dashes")
  }
  Some(e)
}

///|
/// `key` (a constant pair of CSS px) and its `-anchor` (whether `viewport`).
fn parse_translate(
  paint : Map[String, Json],
  key : String,
  path : String,
) -> ((Double, Double), Bool) raise StyleError {
  let t = match paint.get(key) {
    None => (0.0, 0.0)
    Some(Array([Number(x, ..), Number(y, ..)])) => (x, y)
    Some(Array([String(_), ..])) =>
      raise Unsupported(path="\{path}.\{key}", "expressions")
    Some(_) => raise Invalid(path="\{path}.\{key}", "not [x, y]")
  }
  (t, alignment(paint, "\{key}-anchor", path) == "viewport")
}

///|
/// An alignment property: `map` or `viewport`.
fn alignment(
  paint : Map[String, Json],
  key : String,
  path : String,
  default~ : String = "map",
) -> String raise StyleError {
  match string_or(paint, key, path, default) {
    "map" | "viewport" as a => a
    a => raise Invalid(path="\{path}.\{key}", "unknown alignment \{a}")
  }
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
