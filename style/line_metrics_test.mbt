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
