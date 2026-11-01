///|
/// How a `raster-dem` source packs elevations into RGB. `Custom` holds
/// MapLibre's `redFactor`, `greenFactor`, `blueFactor` and `baseShift`. `Gsi`
/// (an mbmap extension, `"encoding": "gsi"`) is GSI's: 0.01 m steps from the
/// 24-bit value, negative past 2^23, and no data at 2^23.
pub(all) enum DemEncoding {
  Mapbox
  Terrarium
  Gsi
  Custom(Double, Double, Double, Double)
} derive(Debug, Eq)

///|
/// A hillshade layer's paint (MapLibre's `standard` method): the light's
/// direction in degrees and whether it turns with the map (`viewport`).
pub struct HillshadePaint {
  direction : Expr
  viewport : Bool
  exaggeration : Expr
  shadow : Expr
  highlight : Expr
  accent : Expr
}

///|
fn parse_encoding(
  s : Map[String, Json],
  path : String,
) -> DemEncoding raise StyleError {
  match string_or(s, "encoding", path, "mapbox") {
    "mapbox" => Mapbox
    "terrarium" => Terrarium
    "gsi" => Gsi
    "custom" =>
      Custom(
        number_or(s, "redFactor", path, 1.0),
        number_or(s, "greenFactor", path, 1.0),
        number_or(s, "blueFactor", path, 1.0),
        number_or(s, "baseShift", path, 0.0),
      )
    e => raise Invalid(path="\{path}.encoding", "unknown encoding \{e}")
  }
}

///|
fn parse_hillshade(
  paint : Map[String, Json],
  path : String,
) -> HillshadePaint raise StyleError {
  let algorithm = string_or(paint, "hillshade-method", path, "standard")
  if algorithm != "standard" {
    raise Unsupported(path="\{path}.hillshade-method", algorithm)
  }
  {
    direction: paint_expr(
      paint,
      "hillshade-illumination-direction",
      path,
      NumberType,
      Json::number(335.0),
    ),
    viewport: match
      string_or(paint, "hillshade-illumination-anchor", path, "viewport") {
      "viewport" => true
      "map" => false
      a =>
        raise Invalid(
          path="\{path}.hillshade-illumination-anchor",
          "unknown anchor \{a}",
        )
    },
    exaggeration: paint_expr(
      paint,
      "hillshade-exaggeration",
      path,
      NumberType,
      Json::number(0.5),
    ),
    shadow: paint_expr(
      paint,
      "hillshade-shadow-color",
      path,
      ColorType,
      Json::string("#000000"),
    ),
    highlight: paint_expr(
      paint,
      "hillshade-highlight-color",
      path,
      ColorType,
      Json::string("#ffffff"),
    ),
    accent: paint_expr(
      paint,
      "hillshade-accent-color",
      path,
      ColorType,
      Json::string("#000000"),
    ),
  }
}
