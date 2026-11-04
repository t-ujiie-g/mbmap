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
/// How the lines of a label line up (`text-justify`); `Auto` follows the anchor.
pub(all) enum TextJustify {
  Auto
  Left
  Center
  Right
} derive(Debug, Eq)

///|
/// Where labels go (`symbol-placement`): on points, along lines at intervals,
/// or at the middle of each line.
pub(all) enum SymbolPlacement {
  Point
  Line
  LineCenter
} derive(Debug, Eq)

///|
/// A symbol layer's text layout: `field` is `text-field` as parts to join; sizes in CSS pixels,
/// `offset`, `max_width`, `line_height` and `letter_spacing` in ems, `rotate` in degrees; `vertical`
/// the first `text-writing-mode`, `sort_key` the `symbol-sort-key`, `font` the `text-font` (None for
/// the map's font). `variable` holds the anchors to try in order with their offsets in ems
/// (`text-variable-anchor-offset`); such labels are shaped centered, `offset` 0. Along lines:
/// `spacing` (px), `max_angle` (degrees), `keep_upright`. `text-overlap` `always` is
/// `allow_overlap`, `cooperative` its own flag.
pub struct TextLayout {
  field : Array[Expr]
  size : Expr
  placement : SymbolPlacement
  spacing : Double
  max_angle : Double
  keep_upright : Bool
  anchor : TextAnchor
  offset : (Double, Double)
  justify : TextJustify
  variable : Array[(TextAnchor, Double, Double)]
  max_width : Double
  line_height : Double
  padding : Double
  allow_overlap : Bool
  ignore_placement : Bool
  vertical : Bool
  sort_key : Expr?
  font : Expr?
  letter_spacing : Expr
  transform : Expr
  rotate : Expr
  cooperative : Bool
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
  let placement = match string_or(layout, "symbol-placement", path, "point") {
    "point" => SymbolPlacement::Point
    "line" => Line
    "line-center" => LineCenter
    p =>
      raise Invalid(path="\{path}.symbol-placement", "unknown placement \{p}")
  }
  // Along lines text lies on the map as MapLibre's `auto` alignments make it.
  if placement != Point {
    for
      key in [
        "text-rotation-alignment", "text-pitch-alignment", "text-offset", "text-radial-offset",
        "text-variable-anchor", "text-variable-anchor-offset",
      ] {
      match (key, layout.get(key)) {
        (_, None) => ()
        (
          "text-rotation-alignment"
          | "text-pitch-alignment",
          Some(String("map" | "auto")),
        ) => ()
        _ => raise Unsupported(path="\{path}.\{key}", "along lines")
      }
    }
  }
  let anchor = match layout.get("text-anchor") {
    None => TextAnchor::Center
    Some(j) => anchor_of(j, "\{path}.text-anchor")
  }
  let offset = match layout.get("text-offset") {
    None => (0.0, 0.0)
    Some(Array([Number(x, ..), Number(y, ..)])) => (x, y)
    Some(Array([String(_), ..])) =>
      raise Unsupported(path="\{path}.text-offset", "expressions")
    Some(_) => raise Invalid(path="\{path}.text-offset", "not two numbers")
  }
  // MapLibre takes `text-radial-offset` over `text-offset` when both are given.
  let radial = match layout.get("text-radial-offset") {
    None => None
    Some(_) => Some(number_or(layout, "text-radial-offset", path, 0.0))
  }
  let variable = variable_anchors(layout, path, offset, radial)
  let offset = match (variable, radial) {
    ([_, ..], _) => (0.0, 0.0)
    ([], Some(r)) => variable_offset(anchor, r, 0.0, radial=true)
    ([], None) => offset
  }
  let justify = string_or(layout, "text-justify", path, "center")
  guard justify_names.search(justify) is Some(j) else {
    raise Invalid(path="\{path}.text-justify", "unknown justification")
  }
  let (allow_overlap, cooperative) = overlap_of(layout, "text", path)
  let layout_expr = (key : String, expected : Expected, default : Json) => {
    compile(
      layout.get(key).unwrap_or(default),
      expected~,
      path="\{path}.\{key}",
    )
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
    placement,
    spacing: @cmp.maximum(1.0, number_or(layout, "symbol-spacing", path, 250.0)),
    max_angle: number_or(layout, "text-max-angle", path, 45.0),
    keep_upright: bool_or(layout, "text-keep-upright", path, true),
    anchor: if variable.is_empty() {
      anchor
    } else {
      Center
    },
    offset,
    justify: justify_values[j],
    variable,
    max_width: number_or(layout, "text-max-width", path, 10.0),
    line_height: number_or(layout, "text-line-height", path, 1.2),
    padding: number_or(layout, "text-padding", path, 2.0),
    allow_overlap,
    cooperative,
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
    font: match layout.get("text-font") {
      None => None
      // A list of names, unless it is an expression (MapLibre's `isExpression`).
      Some(Array([String(op), ..] as items)) if !(op
        is ("get" | "global-state" | "var")) &&
        items.iter().all(j => j is String(_)) =>
        Some(
          Lit(
            List(
              items.map(j => if j is String(s) { Value::Str(s) } else { Null }),
            ),
          ),
        )
      Some(j) =>
        Some(
          compile(j, expected=ArrayOf(StringType, -1), path="\{path}.text-font"),
        )
    },
    letter_spacing: layout_expr(
      "text-letter-spacing",
      NumberType,
      Json::number(0.0),
    ),
    transform: layout_expr("text-transform", StringType, Json::string("none")),
    rotate: layout_expr("text-rotate", NumberType, Json::number(0.0)),
  }
}

///|
/// `*-overlap` and `*-allow-overlap` of `prefix` (`text` or `icon`) as MapLibre's
/// `getOverlapMode` takes them: whether symbols always overlap, and whether they
/// overlap all but those that never do (`cooperative`).
fn overlap_of(
  layout : Map[String, Json],
  prefix : String,
  path : String,
) -> (Bool, Bool) raise StyleError {
  match string_or(layout, "\{prefix}-overlap", path, "") {
    "" => (bool_or(layout, "\{prefix}-allow-overlap", path, false), false)
    "never" => (false, false)
    "always" => (true, false)
    "cooperative" => (false, true)
    m => raise Invalid(path="\{path}.\{prefix}-overlap", "unknown overlap \{m}")
  }
}

///|
/// MapLibre's weights by the words of a font's name (`GlyphManager._fontWeight`),
/// the last one found winning.
let font_weights : Array[(String, String)] = [
  ("thin", "100"),
  ("hairline", "100"),
  ("extra light", "200"),
  ("ultra light", "200"),
  ("light", "300"),
  ("normal", "400"),
  ("regular", "400"),
  ("medium", "500"),
  ("semibold", "600"),
  ("demibold", "600"),
  ("bold", "700"),
  ("extra bold", "800"),
  ("ultra bold", "800"),
  ("black", "900"),
  ("heavy", "900"),
  ("extra black", "950"),
  ("ultra black", "950"),
]

///|
/// Whether `word` stands in `s` between word boundaries (JavaScript's `\b`).
fn has_word(s : String, word : String) -> Bool {
  let n = word.length()
  for i in 0..<=(s.length() - n) {
    if s.unsafe_substring(start=i, end=i + n) == word &&
      (i == 0 || !word_char(s[i - 1].unsafe_to_char())) &&
      (i + n == s.length() || !word_char(s[i + n].unsafe_to_char())) {
      return true
    }
  }
  false
}

///|
/// MapLibre's local font for a `text-font` stack joined by commas (`GlyphManager._createTinySDF`):
/// the CSS families (a name without word characters quoted as by `CSS.escape`), and the weight
/// ("" for none) and style sniffed from the first name.
pub fn font_face(stack : String) -> (String, String, String) {
  let family = StringBuilder()
  let mut first = ""
  for name in stack.split(",") {
    let name = name.to_owned()
    if family.is_empty() {
      first = name.to_lower()
    } else {
      family.write_char(',')
    }
    if name.iter().any(c => word_char(c) || c == '-') {
      family.write_string(name)
      continue
    }
    family.write_char('\'')
    for c in name {
      let code = c.to_int()
      if code == 0 {
        family.write_char('\u{FFFD}')
      } else if code < 32 || code == 127 {
        family.write_string("\\\{code.to_string(radix=16)} ")
      } else if code < 128 {
        family.write_char('\\')
        family.write_char(c)
      } else {
        family.write_char(c)
      }
    }
    family.write_char('\'')
  }
  let mut weight = ""
  for w in font_weights {
    if has_word(first, w.0) {
      weight = w.1
    }
  }
  let style = if first.contains("italic") {
    "italic"
  } else if first.contains("oblique") {
    "oblique"
  } else {
    "normal"
  }
  (family.to_string(), weight, style)
}
