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
    state: js_null(),
  })
  assert_eq((p.r, p.b, p.a, p.width), (1.0, 0.0, 0.5, 6.0))
  let q = paint_of(layer, 10.0, JsProps::none())
  assert_eq((q.r, q.b, q.a, q.width), (0.0, 1.0, 1.0, 1.0))
}

///|
test "JsProps reports absent keys as None and other types as Null" {
  let props : JsProps = {
    obj: js_object("{\"b\": true, \"s\": \"x\", \"n\": null}"),
    state: js_object("{\"hover\": true}"),
  }
  assert_eq(@style.FeatureContext::state(props, "hover"), Some(Bool(true)))
  assert_eq(@style.FeatureContext::state(props, "b"), None)
  assert_eq(@style.FeatureContext::property(props, "missing"), None)
  assert_eq(@style.FeatureContext::property(props, "b"), Some(Bool(true)))
  assert_eq(@style.FeatureContext::property(props, "s"), Some(Str("x")))
  assert_eq(@style.FeatureContext::property(props, "n"), Some(Null))
  assert_eq(@style.FeatureContext::geometry_type(props), "Unknown")
  assert_eq(@style.FeatureContext::property(JsProps::none(), "b"), None)
}

///|
test "JsProps reads the id key and converts with the browser's String and Number" {
  let props : JsProps = { obj: js_object("{\"$id\": 7}"), state: js_null(), }
  assert_eq(@style.FeatureContext::id(props), Num(7.0))
  assert_eq(@style.FeatureContext::id(JsProps::none()), Null)
  assert_eq(
    @style.FeatureContext::number_text(props, 0.1 + 0.2),
    "0.30000000000000004",
  )
  assert_eq(@style.FeatureContext::text_number(props, " 0x10 "), 16.0)
  assert_eq(@style.FeatureContext::trig(props).pow(2.0, 10.0), 1024.0)
  // NaN paint is the property's default, as MapLibre takes it.
  assert_eq(number_or(Num(0.0 / 0.0), 3.0), 3.0)
}

///|
test "paint_of evaluates circle radius and stroke; other kinds leave them empty" {
  let style = @style.Style::parse(
    (
      #|{"layers": [{"id": "c", "type": "circle", "paint": {
      #|  "circle-radius": ["match", ["get", "k"], 1, 8, 3],
      #|  "circle-stroke-width": 2, "circle-stroke-color": "#0000ff", "circle-stroke-opacity": 0.5}},
      #| {"id": "f", "type": "fill"}]}
    ),
  )
  let c = paint_of(style.layers[0], 14.0, {
    obj: js_object("{\"k\": 1}"),
    state: js_null(),
  })
  assert_eq((c.radius, c.stroke_width), (8.0, 2.0))
  assert_eq(
    (c.stroke[0], c.stroke[1], c.stroke[2], c.stroke[3]),
    (0.0, 0.0, 1.0, 0.5),
  )
  assert_eq(paint_of(style.layers[0], 14.0, JsProps::none()).radius, 3.0)
  let f = paint_of(style.layers[1], 14.0, JsProps::none())
  assert_eq((f.radius, f.stroke_width, f.stroke[3]), (0.0, 0.0, 0.0))
}
