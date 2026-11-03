///|
/// A heatmap layer's paint besides its radius (`StyleLayer::radius`) and
/// opacity: each point's `weight`, the layer's `intensity` (zoom only) and the
/// `color` ramp over `["heatmap-density"]`.
pub struct HeatmapPaint {
  weight : Expr
  intensity : Expr
  color : Expr
}

///|
/// The Style Spec's default `heatmap-color`, its named colors in hex.
fn default_heatmap_color() -> Json {
  let stops = [
    (0.0, "rgba(0, 0, 255, 0)"),
    (0.1, "#4169e1"),
    (0.3, "#00ffff"),
    (0.5, "#00ff00"),
    (0.7, "#ffff00"),
    (1.0, "#ff0000"),
  ]
  let items = [
    Json::string("interpolate"),
    Json::array([Json::string("linear")]),
    Json::array([Json::string("heatmap-density")]),
  ]
  for s in stops {
    items.push(Json::number(s.0))
    items.push(Json::string(s.1))
  }
  Json::array(items)
}

///|
fn parse_heatmap(
  paint : Map[String, Json],
  path : String,
) -> HeatmapPaint raise StyleError {
  let weight = paint_expr(
    paint,
    "heatmap-weight",
    path,
    NumberType,
    Json::number(1.0),
  )
  let intensity = paint_expr(
    paint,
    "heatmap-intensity",
    path,
    NumberType,
    Json::number(1.0),
  )
  if data_driven(intensity) || intensity.reads_state() {
    raise Invalid(
      path="\{path}.heatmap-intensity",
      "data expressions not supported",
    )
  }
  let color_path = "\{path}.heatmap-color"
  let color = compile(
    paint.get("heatmap-color").unwrap_or(default_heatmap_color()),
    expected=ColorType,
    path=color_path,
  )
  if data_driven(color) || color.reads_state() || color.any(e => e is Zoom) {
    raise Invalid(path=color_path, "only heatmap-density is allowed")
  }
  { weight, intensity, color, }
}
