///|
/// A fill-extrusion layer's paint besides its color and opacity: the heights in
/// meters of the top (`height`) and bottom (`base`), and whether walls darken
/// towards the ground (`vertical_gradient`).
#derive(Eq)
pub struct ExtrusionPaint {
  height : Expr
  base : Expr
  vertical_gradient : Bool
}

///|
fn parse_extrusion(
  paint : Map[String, Json],
  path : String,
) -> ExtrusionPaint raise StyleError {
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

///|
/// The style's `lights` (an mbmap extension, Mapbox's names): `ambient` and `directional`
/// colors and intensities, `direction` [azimuthal from north, polar from up] in degrees
/// on the map. A missing light is black.
pub struct Lights {
  ambient_color : Expr
  ambient_intensity : Expr
  sun_color : Expr
  sun_intensity : Expr
  direction : (Double, Double)
}

///|
fn parse_lights(json : Json?) -> Lights? raise StyleError {
  let list = match json {
    None | Some(Null) => return None
    Some(Array(list)) => list
    Some(_) => raise Invalid(path="lights", "not an array")
  }
  let black = Lit(Value::Null)
  let mut lights = {
    ambient_color: black,
    ambient_intensity: Lit(Num(0.0)),
    sun_color: black,
    sun_intensity: Lit(Num(0.0)),
    direction: (210.0, 30.0),
  }
  for i, light in list {
    let path = "lights[\{i}]"
    guard light is Object(l) else { raise Invalid(path~, "not an object") }
    let p = match l.get("properties") {
      None => Map([])
      Some(Object(p)) => p
      Some(_) => raise Invalid(path="\{path}.properties", "not an object")
    }
    let at = "\{path}.properties"
    let color = paint_expr(p, "color", at, ColorType, Json::string("#ffffff"))
    match l.get("type") {
      Some(String("ambient")) =>
        lights = {
          ..lights,
          ambient_color: color,
          ambient_intensity: paint_expr(
            p,
            "intensity",
            at,
            NumberType,
            Json::number(0.8),
          ),
        }
      Some(String("directional")) => {
        let direction = match p.get("direction") {
          None => (210.0, 30.0)
          Some(Array([Number(a, ..), Number(b, ..)])) => (a, b)
          Some(_) =>
            raise Unsupported(
              path="\{at}.direction",
              "only [azimuthal, polar] numbers",
            )
        }
        lights = {
          ..lights,
          sun_color: color,
          sun_intensity: paint_expr(
            p,
            "intensity",
            at,
            NumberType,
            Json::number(0.8),
          ),
          direction,
        }
      }
      _ =>
        raise Unsupported(
          path="\{path}.type",
          "only ambient and directional lights",
        )
    }
  }
  Some(lights)
}
