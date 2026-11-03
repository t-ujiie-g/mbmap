///|
test "a GeoJSON source's lineMetrics must be a boolean" {
  let src = (v : String) => {
    "{\"sources\": {\"g\": {\"type\": \"geojson\", \"data\": {\"type\": \"FeatureCollection\", \"features\": []}, \"lineMetrics\": \{v}}}, \"layers\": []}"
  }
  assert_true(@style.Style::parse(src("true")).sources.length() == 1)
  try @style.Style::parse(src("1")) catch {
    Invalid(path~, _) => assert_eq(path, "sources.g.lineMetrics")
    Unsupported(_, ..) => fail("unexpected Unsupported")
  } noraise {
    _ => fail("expected Invalid")
  }
}

///|
/// A context at a point `p` of the way along a line.
struct Along {
  p : Double
}

///|
impl @style.FeatureContext for Along with fn property(_, _) {
  None
}

///|
impl @style.FeatureContext for Along with fn geometry_type(_) {
  "LineString"
}

///|
impl @style.FeatureContext for Along with fn line_progress(self) {
  self.p
}

///|
fn gradient_style(paint : String) -> @style.Style raise @style.StyleError {
  @style.Style::parse(
    "{\"layers\": [{\"id\": \"a\", \"type\": \"line\", \"paint\": \{paint}}]}",
  )
}

///|
test "line-gradient reads line-progress, and only it may" {
  let l = gradient_style(
      "{\"line-gradient\": [\"interpolate\", [\"linear\"], [\"line-progress\"], 0, \"#000000\", 1, \"#ffffff\"]}",
    ).layers[0]
  let g = l.gradient.unwrap()
  assert_eq(g.eval(14, { p: 0.5, }), Color({ r: 0.5, g: 0.5, b: 0.5, a: 1.0, }))
  assert_eq(g.eval(14, @style.NoFeature::{ }), Failed)
  assert_true(gradient_style("{}").layers[0].gradient is None)
  for
    bad in [
      "{\"line-width\": [\"line-progress\"]}", "{\"line-gradient\": [\"get\", \"c\"]}",
    ] {
    try gradient_style(bad) catch {
      Invalid(path~, _) => assert_true(path.has_prefix("layers[0]"))
      Unsupported(_, ..) => fail("unexpected Unsupported")
    } noraise {
      _ => fail("expected Invalid for \{bad}")
    }
  }
}
