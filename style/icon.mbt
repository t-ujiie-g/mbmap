///|
/// How an icon stretches around its label's text (`icon-text-fit`).
pub(all) enum IconTextFit {
  NoFit
  Width
  Height
  Both
} derive(Debug, Eq)

///|
/// A symbol layer's icon layout (`layout` as written: equal ones make the same tiles): `image`
/// as parts of a name, `rotate` in degrees, `offset` in px at size 1, paddings top, right, bottom,
/// left (px), alignments resolved from `auto`; overlap modes as `TextLayout`'s.
pub struct IconLayout {
  layout : Json
  image : Array[Expr]
  size : Expr
  rotate : Expr
  anchor : TextAnchor
  offset : (Double, Double)
  padding : (Double, Double, Double, Double)
  allow_overlap : Bool
  ignore_placement : Bool
  optional : Bool
  text_optional : Bool
  rotate_with_map : Bool
  pitch_with_map : Bool
  keep_upright : Bool
  text_fit : IconTextFit
  text_fit_padding : (Double, Double, Double, Double)
  cooperative : Bool
}

///|
/// A symbol layer's icon paint: `color`, `halo_color`, `halo_width` and
/// `halo_blur` color SDF icons only; `translate` (CSS px) and `translate_viewport`
/// are `icon-translate` and its anchor.
pub struct IconPaint {
  color : Expr
  opacity : Expr
  halo_color : Expr
  halo_width : Expr
  halo_blur : Expr
  translate : (Double, Double)
  translate_viewport : Bool
}

///|
/// MapLibre's `Padding`: one number for all sides, or 1 to 4 numbers in CSS
/// order (top, right, bottom, left).
fn padding_of(
  obj : Map[String, Json],
  key : String,
  path : String,
  default : Double,
) -> (Double, Double, Double, Double) raise StyleError {
  let v = match obj.get(key) {
    None => [default]
    Some(Number(n, ..)) => [n]
    Some(Array([String(_), ..])) =>
      raise Unsupported(path="\{path}.\{key}", "expressions")
    Some(Array(a)) =>
      a.map(j => if j is Number(n, ..) { n } else { @double.not_a_number })
    Some(_) => []
  }
  let n = v.length()
  guard n >= 1 && n <= 4 && v.iter().all(x => x == x) else {
    raise Invalid(path="\{path}.\{key}", "not a padding")
  }
  (
    v[0],
    v[@cmp.minimum(1, n - 1)],
    v[if n >= 3 { 2 } else { 0 }],
    v[if n == 4 { 3 } else if n >= 2 { 1 } else { 0 }],
  )
}

///|
/// The icon layout keys that are booleans, in `IconLayout`'s order.
let icon_flags : Array[String] = [
  "icon-ignore-placement", "icon-optional", "text-optional", "icon-keep-upright",
]

///|
/// A symbol layer's icon, None without `icon-image`. Alignments are `map`,
/// `viewport` or `auto`, which follows the placement (rotation) and the
/// rotation alignment (pitch), as MapLibre resolves them.
fn parse_icon(
  layout : Map[String, Json],
  paint : Map[String, Json],
  path : String,
  ppath : String,
  placement : SymbolPlacement,
) -> (IconLayout, IconPaint)? raise StyleError {
  guard layout.get("icon-image") is Some(image) else { return None }
  let ipath = "\{path}.icon-image"
  let image = match image {
    Array([String("image"), j]) => j
    j => j
  }
  let exprs = []
  for k in ["icon-size", "icon-rotate"] {
    let d = Json::number(if k == "icon-size" { 1.0 } else { 0.0 })
    exprs.push(
      compile(
        layout.get(k).unwrap_or(d),
        expected=NumberType,
        path="\{path}.\{k}",
      ),
    )
  }
  let parts = text_parts(image, ipath)
  if [..exprs, ..parts].iter().any(e => e.reads_state()) {
    raise Invalid(path~, "feature-state is only allowed in paint properties")
  }
  let (allow_overlap, cooperative) = overlap_of(layout, "icon", path)
  let (translate, translate_viewport) = parse_translate(
    paint, "icon-translate", ppath,
  )
  let flags = []
  for k in icon_flags {
    flags.push(bool_or(layout, k, path, false))
  }
  let aligned = [placement != Point]
  for k in ["icon-rotation-alignment", "icon-pitch-alignment"] {
    aligned.push(
      match string_or(layout, k, path, "auto") {
        "map" => true
        "viewport" => false
        "auto" => aligned[aligned.length() - 1]
        a => raise Invalid(path="\{path}.\{k}", "unknown alignment \{a}")
      },
    )
  }
  let fit = string_or(layout, "icon-text-fit", path, "none")
  guard fit_names.search(fit) is Some(fit) else {
    raise Invalid(path="\{path}.icon-text-fit", "unknown fit")
  }
  let anchor = match layout.get("icon-anchor") {
    None => TextAnchor::Center
    Some(j) => anchor_of(j, "\{path}.icon-anchor")
  }
  let offset = match layout.get("icon-offset") {
    None => (0.0, 0.0)
    Some(Array([Number(x, ..), Number(y, ..)])) => (x, y)
    Some(Array([String(_), ..])) =>
      raise Unsupported(path="\{path}.icon-offset", "expressions")
    Some(_) => raise Invalid(path="\{path}.icon-offset", "not two numbers")
  }
  // Along lines MapLibre adds `icon-offset` twice; icons turned to the line lie on it.
  let along = if placement is Point {
    ""
  } else if offset != (0.0, 0.0) {
    "icon-offset"
  } else if fit != 0 {
    "icon-text-fit"
  } else if aligned[1] && !aligned[2] {
    "icon-pitch-alignment"
  } else {
    ""
  }
  if along != "" {
    raise Unsupported(path="\{path}.\{along}", "along lines")
  }
  let paints = []
  for d in icon_paint_defaults {
    let (key, json, t) = d
    paints.push(paint_expr(paint, key, ppath, t, json))
  }
  Some(
    (
      {
        layout: Json::object(layout),
        image: parts,
        size: exprs[0],
        rotate: exprs[1],
        anchor,
        offset,
        padding: padding_of(layout, "icon-padding", path, 2.0),
        allow_overlap,
        cooperative,
        ignore_placement: flags[0],
        optional: flags[1],
        text_optional: flags[2],
        keep_upright: flags[3],
        rotate_with_map: aligned[1],
        pitch_with_map: aligned[2],
        text_fit: fit_values[fit],
        text_fit_padding: padding_of(layout, "icon-text-fit-padding", path, 0.0),
      },
      {
        color: paints[0],
        opacity: paints[1],
        halo_color: paints[2],
        halo_width: paints[3],
        halo_blur: paints[4],
        translate,
        translate_viewport,
      },
    ),
  )
}

///|
let fit_names : Array[String] = ["none", "width", "height", "both"]

///|
let fit_values : Array[IconTextFit] = [NoFit, Width, Height, Both]

///|
/// The icon paint keys with their defaults, in `IconPaint`'s order.
let icon_paint_defaults : Array[(String, Json, Expected)] = [
  ("icon-color", Json::string("#000000"), ColorType),
  ("icon-opacity", Json::number(1.0), NumberType),
  ("icon-halo-color", Json::string("rgba(0, 0, 0, 0)"), ColorType),
  ("icon-halo-width", Json::number(0.0), NumberType),
  ("icon-halo-blur", Json::number(0.0), NumberType),
]

///|
/// The icon paint's expressions: color, opacity, halo color, width and blur.
pub fn IconPaint::exprs(self : IconPaint) -> Array[Expr] {
  [self.color, self.opacity, self.halo_color, self.halo_width, self.halo_blur]
}
