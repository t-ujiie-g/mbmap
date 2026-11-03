///|
/// Where a label's text box sits against its anchor (`text-anchor`).
pub(all) enum TextAnchor {
  Center
  Left
  Right
  Top
  Bottom
  TopLeft
  TopRight
  BottomLeft
  BottomRight
} derive(Debug, Eq)

///|
/// A symbol layer's text layout: `field` is `text-field` as parts to join; sizes
/// in CSS pixels, `offset`, `max_width` and `line_height` in ems; `vertical` the
/// first `text-writing-mode`, `sort_key` the `symbol-sort-key`.
pub struct TextLayout {
  field : Array[Expr]
  size : Expr
  anchor : TextAnchor
  offset : (Double, Double)
  max_width : Double
  line_height : Double
  padding : Double
  allow_overlap : Bool
  ignore_placement : Bool
  vertical : Bool
  sort_key : Expr?
} derive(Eq)

///|
/// `text-field` as parts: a string with `{key}` tokens, `get`, `concat` and
/// `to-string` are split up; any other expression is one part.
fn text_parts(json : Json, path : String) -> Array[Expr] raise StyleError {
  match json {
    String(s) => token_parts(s)
    Array([String("concat"), .. rest]) => {
      let out = []
      for i, j in rest {
        out.append(text_parts(j, "\{path}[\{i + 1}]"))
      }
      out
    }
    Array([String("to-string"), j]) => text_parts(j, "\{path}[1]")
    Array([String("format"), ..]) =>
      raise Unsupported(path~, "expression format")
    _ => [compile(json, path~)]
  }
}

///|
/// MapLibre's legacy token strings: `{key}` reads a property.
fn token_parts(s : String) -> Array[Expr] {
  let out = []
  let mut rest = s.clamped_view(start=0, end=s.length())
  while rest.find("{") is Some(open) {
    guard rest[open:].find("}") is Some(len) else { break }
    if open > 0 {
      out.push(Lit(Str(rest[:open].to_owned())))
    }
    out.push(Get(rest[open + 1:open + len].to_owned()))
    rest = rest[open + len + 1:]
  }
  if rest.length() > 0 {
    out.push(Lit(Str(rest.to_owned())))
  }
  out
}

///|
fn bool_or(
  obj : Map[String, Json],
  key : String,
  path : String,
  default : Bool,
) -> Bool raise StyleError {
  match obj.get(key) {
    None => default
    Some(True) => true
    Some(False) => false
    Some(Array(_)) => raise Unsupported(path="\{path}.\{key}", "expressions")
    Some(_) => raise Invalid(path="\{path}.\{key}", "not a boolean")
  }
}

///|
fn parse_text(
  layout : Map[String, Json],
  path : String,
) -> TextLayout raise StyleError {
  let placement = string_or(layout, "symbol-placement", path, "point")
  if placement != "point" {
    raise Unsupported(path="\{path}.symbol-placement", placement)
  }
  if layout.get("icon-image") is Some(_) {
    raise Unsupported(path="\{path}.icon-image", "icons")
  }
  let anchor = match string_or(layout, "text-anchor", path, "center") {
    "center" => TextAnchor::Center
    "left" => Left
    "right" => Right
    "top" => Top
    "bottom" => Bottom
    "top-left" => TopLeft
    "top-right" => TopRight
    "bottom-left" => BottomLeft
    "bottom-right" => BottomRight
    a => raise Invalid(path="\{path}.text-anchor", "unknown anchor \{a}")
  }
  let offset = match layout.get("text-offset") {
    None => (0.0, 0.0)
    Some(Array([Number(x, ..), Number(y, ..)])) => (x, y)
    Some(Array([String(_), ..])) =>
      raise Unsupported(path="\{path}.text-offset", "expressions")
    Some(_) => raise Invalid(path="\{path}.text-offset", "not two numbers")
  }
  {
    field: match layout.get("text-field") {
      None => []
      Some(j) => text_parts(j, "\{path}.text-field")
    },
    size: compile(
      layout.get("text-size").unwrap_or(Json::number(16.0)),
      expected=NumberType,
      path="\{path}.text-size",
    ),
    anchor,
    offset,
    max_width: number_or(layout, "text-max-width", path, 10.0),
    line_height: number_or(layout, "text-line-height", path, 1.2),
    padding: number_or(layout, "text-padding", path, 2.0),
    allow_overlap: bool_or(layout, "text-allow-overlap", path, false),
    ignore_placement: bool_or(layout, "text-ignore-placement", path, false),
    vertical: match layout.get("text-writing-mode") {
      None | Some(Array([])) => false
      Some(Array([String("vertical"), ..])) => true
      Some(Array([String("horizontal"), ..])) => false
      Some(_) =>
        raise Invalid(
          path="\{path}.text-writing-mode",
          "not a list of horizontal and vertical",
        )
    },
    sort_key: match layout.get("symbol-sort-key") {
      None => None
      Some(j) =>
        Some(compile(j, expected=NumberType, path="\{path}.symbol-sort-key"))
    },
  }
}
