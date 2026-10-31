///|
extern "js" fn js_object(json : String) -> JsValue =
  #|(s) => JSON.parse(s)

///|
let road_style : String =
  #|{"layers": [{"id": "road", "type": "line", "paint": {
  #|  "line-color": ["match", ["get", "rdCtg"], 0, "#ff0000", "#0000ff"],
  #|  "line-opacity": ["case", ["==", ["geometry-type"], "Polygon"], 0.5, 1],
  #|  "line-width": ["interpolate", ["linear"], ["zoom"], 10, 1, 20, 11]}}]}

///|
test "paint_of evaluates a group's properties and the zoom" {
  let layer = @style.Style::parse(road_style).layers[0]
  let p = paint_of(layer, 15.0, {
    obj: js_object("{\"rdCtg\": 0, \"$type\": \"Polygon\"}"),
  })
  assert_eq((p.r, p.b, p.a, p.width), (1.0, 0.0, 0.5, 6.0))
  let q = paint_of(layer, 10.0, JsProps::none())
  assert_eq((q.r, q.b, q.a, q.width), (0.0, 1.0, 1.0, 1.0))
}

///|
test "JsProps reports absent keys as None and other types as Null" {
  let props : JsProps = {
    obj: js_object("{\"b\": true, \"s\": \"x\", \"n\": null}"),
  }
  assert_eq(@style.FeatureContext::property(props, "missing"), None)
  assert_eq(@style.FeatureContext::property(props, "b"), Some(Bool(true)))
  assert_eq(@style.FeatureContext::property(props, "s"), Some(Str("x")))
  assert_eq(@style.FeatureContext::property(props, "n"), Some(Null))
  assert_eq(@style.FeatureContext::geometry_type(props), "Unknown")
  assert_eq(@style.FeatureContext::property(JsProps::none(), "b"), None)
}
