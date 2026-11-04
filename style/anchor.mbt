///|
/// Anchor names in `TextAnchor`'s order.
let anchor_names : Array[String] = [
  "center", "left", "right", "top", "bottom", "top-left", "top-right", "bottom-left",
  "bottom-right",
]

///|
let anchor_values : FixedArray[TextAnchor] = [
  Center,
  Left,
  Right,
  Top,
  Bottom,
  TopLeft,
  TopRight,
  BottomLeft,
  BottomRight,
]

///|
let justify_names : Array[String] = ["auto", "left", "center", "right"]

///|
let justify_values : FixedArray[TextJustify] = [Auto, Left, Center, Right]

///|
fn anchor_of(j : Json, path : String) -> TextAnchor raise StyleError {
  match j {
    String(s) if anchor_names.search(s) is Some(i) => anchor_values[i]
    Array(_) => raise Unsupported(path~, "expressions")
    _ => raise Invalid(path~, "not an anchor")
  }
}

///|
/// The anchor's code in a symbol entry (docs/FORMATS.md "Labels"): its place
/// in `TextAnchor`'s order.
pub fn TextAnchor::code(self : TextAnchor) -> Int32 {
  match self {
    Center => 0
    Left => 1
    Right => 2
    Top => 3
    Bottom => 4
    TopLeft => 5
    TopRight => 6
    BottomLeft => 7
    BottomRight => 8
  }
}

///|
/// The anchor of `code` (`TextAnchor::code`); `Center` for an unknown code.
pub fn TextAnchor::from_code(code : Int32) -> TextAnchor {
  anchor_values.get(code).unwrap_or(Center)
}

///|
/// MapLibre's alignment of a label against its anchor: the shares of its width
/// and height left of and above it.
pub fn TextAnchor::align(self : TextAnchor) -> (Double, Double) {
  match self {
    Center => (0.5, 0.5)
    Left => (0.0, 0.5)
    Right => (1.0, 0.5)
    Top => (0.5, 0.0)
    Bottom => (0.5, 1.0)
    TopLeft => (0.0, 0.0)
    TopRight => (1.0, 0.0)
    BottomLeft => (0.0, 1.0)
    BottomRight => (1.0, 1.0)
  }
}

///|
/// MapLibre's `baselineOffset` in ems (7 of `ONE_EM` 24): vertical offsets
/// count from the baseline rather than the em box's edge.
const BASELINE_OFFSET : Double = 0.2916666666666667

///|
/// MapLibre's `evaluateVariableOffset` in ems: a label at `a` moved `x` ems
/// away (`text-radial-offset`, with `radial`) or by `text-offset` (x, y) away.
fn variable_offset(
  a : TextAnchor,
  x : Double,
  y : Double,
  radial~ : Bool,
) -> (Double, Double) {
  let (h, v) = a.align()
  let (dx, dy) = if radial {
    let r = @cmp.maximum(x, 0.0)
    let d = if h != 0.5 && v != 0.5 { r / 2.0.sqrt() } else { r }
    (d, d)
  } else {
    (x.abs(), y.abs())
  }
  let oy = if v == 0.5 { 0.0 } else { (1.0 - 2.0 * v) * (dy - BASELINE_OFFSET) }
  ((1.0 - 2.0 * h) * dx, oy)
}

///|
/// `names`' anchors with offsets from `text-radial-offset` (if given) or
/// `text-offset`, as MapLibre's `getTextVariableAnchorOffset`.
fn anchors_of(
  names : Array[Json],
  path : String,
  offset : (Double, Double),
  radial : Double?,
) -> Array[(TextAnchor, Double, Double)] raise StyleError {
  names.map(j => {
    let a = anchor_of(j, path)
    let (x, y) = match radial {
      Some(r) => variable_offset(a, r, 0.0, radial=true)
      None => variable_offset(a, offset.0, offset.1, radial=false)
    }
    (a, x, y)
  })
}

///|
/// `text-variable-anchor-offset`, or `text-variable-anchor` with offsets from
/// `text-radial-offset` (if given) or `text-offset`: the anchors below the first
/// zoom stop and from each stop on (a `step` over zoom); empty without either.
fn variable_anchors(
  layout : Map[String, Json],
  path : String,
  offset : (Double, Double),
  radial : Double?,
) -> (
  Array[(TextAnchor, Double, Double)],
  Array[(Double, Array[(TextAnchor, Double, Double)])],
) raise StyleError {
  let p = "\{path}.text-variable-anchor-offset"
  match layout.get("text-variable-anchor-offset") {
    None => ()
    // A literal starts with an anchor name, an expression with its operator.
    Some(Array([String(first), ..] as list)) if anchor_names.contains(first) => {
      let out = []
      for i = 0; i < list.length(); i = i + 2 {
        guard list.get(i + 1) is Some(Array([Number(x, ..), Number(y, ..)])) else {
          raise Invalid(path=p, "not anchors and offsets")
        }
        let a = anchor_of(list[i], p)
        out.push((a, x, y + (2.0 * a.align().1 - 1.0) * BASELINE_OFFSET))
      }
      return (out, [])
    }
    Some(_) => raise Unsupported(path=p, "expressions")
  }
  let p = "\{path}.text-variable-anchor"
  let literal = (j : Json) => {
    match j {
      Array([String("literal"), Array(names)]) if names.length() > 0 =>
        anchors_of(names, p, offset, radial)
      _ => raise Unsupported(path=p, "expressions")
    }
  }
  match layout.get("text-variable-anchor") {
    None => ([], [])
    Some(Array([String("step"), Array([String("zoom")]), first, .. stops])) => {
      guard stops.length() % 2 == 0 else {
        raise Invalid(path=p, "not a step over zoom")
      }
      let out = []
      for i = 0; i < stops.length(); i = i + 2 {
        let last = match out.last() {
          Some((z, _)) => z
          None => -@double.infinity
        }
        guard stops[i] is Number(z, ..) && z > last else {
          raise Invalid(path=p, "stops not in ascending order")
        }
        out.push((z, literal(stops[i + 1])))
      }
      (literal(first), out)
    }
    // A literal starts with an anchor name, an expression with its operator.
    Some(Array([String(first), ..])) if !anchor_names.contains(first) =>
      raise Unsupported(path=p, "expressions")
    Some(Array(names)) => (anchors_of(names, p, offset, radial), [])
    Some(_) => raise Invalid(path=p, "not a list of anchors")
  }
}
