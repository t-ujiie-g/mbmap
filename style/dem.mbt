///|
/// How a `raster-dem` source packs elevations into RGB. `Custom` holds MapLibre's
/// factors and `baseShift`; `Gsi` (an mbmap extension) is GSI's: 0.01 m steps of
/// the 24-bit value, negative past 2^23, no data at 2^23.
pub(all) enum DemEncoding {
  Mapbox
  Terrarium
  Gsi
  Custom(Double, Double, Double, Double)
} derive(Debug, Eq)

///|
/// How a hillshade layer shades slopes (`hillshade-method`).
pub(all) enum HillshadeMethod {
  Standard
  Combined
  Igor
  Multidirectional
  Basic
}

///|
/// Most lights a hillshade layer may have (`hillshade-highlight-color` entries).
pub const MAX_HILLSHADE_LIGHTS : Int32 = 8

///|
/// A hillshade layer's paint: per light (as many as `highlight` lists; shorter
/// lists repeat their last value) its `direction` and `altitude` in degrees and
/// colors; `viewport` turns the light with the map; `nearest` samples nearest.
pub struct HillshadePaint {
  shading : HillshadeMethod
  direction : Array[Expr]
  altitude : Array[Expr]
  viewport : Bool
  exaggeration : Expr
  shadow : Array[Expr]
  highlight : Array[Expr]
  accent : Expr
  nearest : Bool
}

///|
/// A color relief layer's elevation `stops`: the inputs of its
/// `color-relief-color` when that is an `interpolate` (MapLibre colors nothing
/// otherwise), where its colors are taken and blended linearly between.
pub struct ColorReliefPaint {
  stops : Array[Double]
  nearest : Bool
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
/// `resampling` (hillshade, color relief and raster layers).
fn resampling_nearest(
  paint : Map[String, Json],
  path : String,
) -> Bool raise StyleError {
  match string_or(paint, "resampling", path, "linear") {
    "linear" => false
    "nearest" => true
    r => raise Invalid(path="\{path}.resampling", "unknown resampling \{r}")
  }
}

///|
/// A `numberArray` or `colorArray` property: one value or expression, or a
/// list of values (an array that is not an expression, told apart as MapLibre
/// does: all numbers, or all strings starting with a color).
fn light_values(
  paint : Map[String, Json],
  key : String,
  path : String,
  expected : Expected,
  default : Json,
) -> Array[Expr] raise StyleError {
  let path = "\{path}.\{key}"
  let json = paint.get(key).unwrap_or(default)
  let list = match json {
    Array(items) if items.iter().all(j => j is Number(_)) => Some(items)
    Array([String(first), ..] as items) if parse_color(first) is Some(_) &&
      items.iter().all(j => j is String(_)) => Some(items)
    _ => None
  }
  match list {
    Some([]) => raise Invalid(path~, "empty")
    Some(items) => {
      let out = []
      for i, j in items {
        out.push(compile(j, expected~, path="\{path}[\{i}]"))
      }
      out
    }
    None => [compile(json, expected~, path~)]
  }
}

///|
fn parse_hillshade(
  paint : Map[String, Json],
  path : String,
) -> HillshadePaint raise StyleError {
  let shading = match string_or(paint, "hillshade-method", path, "standard") {
    "standard" => Standard
    "combined" => Combined
    "igor" => Igor
    "multidirectional" => Multidirectional
    "basic" => Basic
    m => raise Invalid(path="\{path}.hillshade-method", "unknown method \{m}")
  }
  let highlight = light_values(
    paint,
    "hillshade-highlight-color",
    path,
    ColorType,
    Json::string("#FFFFFF"),
  )
  if highlight.length() > MAX_HILLSHADE_LIGHTS {
    raise Unsupported(
      path="\{path}.hillshade-highlight-color",
      "more than \{MAX_HILLSHADE_LIGHTS} lights",
    )
  }
  {
    shading,
    direction: light_values(
      paint,
      "hillshade-illumination-direction",
      path,
      NumberType,
      Json::number(335.0),
    ),
    altitude: light_values(
      paint,
      "hillshade-illumination-altitude",
      path,
      NumberType,
      Json::number(45.0),
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
    shadow: light_values(
      paint,
      "hillshade-shadow-color",
      path,
      ColorType,
      Json::string("#000000"),
    ),
    highlight,
    accent: paint_expr(
      paint,
      "hillshade-accent-color",
      path,
      ColorType,
      Json::string("#000000"),
    ),
    nearest: resampling_nearest(paint, path),
  }
}

///|
/// `color` is the layer's `color-relief-color`, which may read `elevation` only.
fn parse_color_relief(
  color : Expr,
  paint : Map[String, Json],
  path : String,
) -> ColorReliefPaint raise StyleError {
  if data_driven(color) || color.reads_state() || color.any(e => e is Zoom) {
    raise Invalid(
      path="\{path}.color-relief-color",
      "only elevation is allowed",
    )
  }
  {
    stops: match color {
      Interpolate(_, _, _, stops) => stops.map(s => s.0)
      _ => []
    },
    nearest: resampling_nearest(paint, path),
  }
}
