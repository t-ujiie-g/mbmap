///|
/// A fill-extrusion layer's paint besides its color and opacity: the heights in
/// meters of the top (`height`) and bottom (`base`), and whether walls darken
/// towards the ground (`vertical_gradient`).
pub struct ExtrusionPaint {
  height : Expr
  base : Expr
  vertical_gradient : Bool
} derive(Eq)

///|
fn parse_extrusion(
  paint : Map[String, Json],
  path : String,
) -> ExtrusionPaint raise StyleError {
  match paint.get("fill-extrusion-translate") {
    None | Some(Array([Number(0.0, ..), Number(0.0, ..)])) => ()
    Some(_) =>
      raise Unsupported(path="\{path}.fill-extrusion-translate", "translate")
  }
  {
    height: paint_expr(
      paint,
      "fill-extrusion-height",
      path,
      NumberType,
      Json::number(0.0),
    ),
    base: paint_expr(
      paint,
      "fill-extrusion-base",
      path,
      NumberType,
      Json::number(0.0),
    ),
    vertical_gradient: match paint.get("fill-extrusion-vertical-gradient") {
      None | Some(True) => true
      Some(False) => false
      Some(_) =>
        raise Invalid(
          path="\{path}.fill-extrusion-vertical-gradient",
          "not a boolean",
        )
    },
  }
}

///|
/// The style's `light` (Style Spec defaults for what it leaves out): whether it
/// turns with the map (`viewport`), its color, intensity and `position` (radial
/// distance, azimuth and polar angle in degrees).
pub struct Light {
  viewport : Bool
  color : Expr
  intensity : Expr
  position : (Double, Double, Double)
}

///|
fn parse_light(json : Json?) -> Light raise StyleError {
  let l = match json {
    None | Some(Null) => Map([])
    Some(Object(l)) => l
    Some(_) => raise Invalid(path="light", "not an object")
  }
  let viewport = match string_or(l, "anchor", "light", "viewport") {
    "viewport" => true
    "map" => false
    a => raise Invalid(path="light.anchor", "unknown anchor \{a}")
  }
  let position = match l.get("position") {
    None => (1.15, 210.0, 30.0)
    Some(Array([Number(r, ..), Number(a, ..), Number(p, ..)])) => (r, a, p)
    Some(Array([String(_), ..])) =>
      raise Unsupported(path="light.position", "expressions")
    Some(_) => raise Invalid(path="light.position", "not [r, azimuth, polar]")
  }
  {
    viewport,
    color: paint_expr(l, "color", "light", ColorType, Json::string("#ffffff")),
    intensity: paint_expr(
      l,
      "intensity",
      "light",
      NumberType,
      Json::number(0.5),
    ),
    position,
  }
}
