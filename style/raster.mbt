///|
/// A raster layer's paint: `opacity`, `hue_rotate` (degrees), `brightness_min`,
/// `brightness_max`, `saturation` and `contrast` (-1 to 1), and `nearest` for
/// `resampling` or `raster-resampling` `nearest`.
#derive(Eq)
pub struct RasterPaint {
  opacity : Expr
  hue_rotate : Expr
  brightness_min : Expr
  brightness_max : Expr
  saturation : Expr
  contrast : Expr
  nearest : Bool
}

///|
fn parse_raster(
  paint : Map[String, Json],
  path : String,
) -> RasterPaint raise StyleError {
  let number = (key : String, default : Double) => {
    paint_expr(paint, key, path, NumberType, Json::number(default))
  }
  let nearest = resampling_nearest(paint, path)
  {
    opacity: number("raster-opacity", 1.0),
    hue_rotate: number("raster-hue-rotate", 0.0),
    brightness_min: number("raster-brightness-min", 0.0),
    brightness_max: number("raster-brightness-max", 1.0),
    saturation: number("raster-saturation", 0.0),
    contrast: number("raster-contrast", 0.0),
    nearest: match string_or(paint, "raster-resampling", path, "linear") {
      "linear" => nearest
      "nearest" => true
      r =>
        raise Invalid(
          path="\{path}.raster-resampling",
          "unknown resampling \{r}",
        )
    },
  }
}
