///|
/// A feature with properties only.
struct Props {
  props : Map[String, @style.Value]
}

///|
impl @style.FeatureContext for Props with fn property(self, key) {
  self.props.get(key)
}

///|
impl @style.FeatureContext for Props with fn geometry_type(_) {
  "Point"
}

///|
fn layer(json : String) -> @style.StyleLayer raise {
  @style.Style::from_json(
    @json.parse(
      "{\"version\": 8, \"sources\": {\"s\": {\"type\": \"geojson\", \"data\": {\"type\": \"FeatureCollection\", \"features\": []}}}, \"layers\": [" +
      json +
      "]}",
    ),
  ).layers[0]
}

///|
test "vertex_paint takes the data-driven paint of fills, lines and circles in slot order" {
  let c = layer(
    "{\"id\": \"c\", \"type\": \"circle\", \"source\": \"s\", \"paint\": {\"circle-radius\": [\"get\", \"r\"], \"circle-color\": [\"match\", [\"get\", \"k\"], \"a\", \"#f00\", \"#00f\"], \"circle-opacity\": [\"interpolate\", [\"linear\"], [\"zoom\"], 10, 0.5, 14, 1]}}",
  )
  let vp = c.vertex_paint()
  assert_eq(vp.map(p => (p.slot, p.color, p.stops.length(), p.count())), [
    (@style.SLOT_COLOR, true, 0, 1),
    (@style.SLOT_SIZE, false, 0, 1),
  ])
  assert_eq(@style.vertex_paint_words(vp), 2)
  assert_eq(vp[0].position(14), (0, 0.0))
  // Constant or zoom-only paint, feature state, other kinds: nothing per vertex.
  assert_eq(
    layer(
      "{\"id\": \"f\", \"type\": \"fill\", \"source\": \"s\", \"paint\": {\"fill-color\": \"#fff\"}}",
    )
    .vertex_paint()
    .length(),
    0,
  )
  assert_eq(
    layer(
      "{\"id\": \"f\", \"type\": \"fill\", \"source\": \"s\", \"paint\": {\"fill-color\": [\"case\", [\"boolean\", [\"feature-state\", \"on\"], false], \"#f00\", [\"get\", \"c\"]]}}",
    )
    .vertex_paint()
    .length(),
    0,
  )
  assert_eq(
    layer(
      "{\"id\": \"e\", \"type\": \"fill-extrusion\", \"source\": \"s\", \"paint\": {\"fill-extrusion-color\": [\"get\", \"c\"]}}",
    )
    .vertex_paint()
    .length(),
    0,
  )
}

///|
test "a zoom curve with data-driven outputs keeps each stop's output" {
  let l = layer(
    "{\"id\": \"l\", \"type\": \"line\", \"source\": \"s\", \"paint\": {\"line-width\": [\"interpolate\", [\"exponential\", 2], [\"zoom\"], 14, [\"get\", \"w\"], 16, 4, 18, 8]}}",
  )
  let vp = l.vertex_paint()
  assert_eq(vp.length(), 1)
  let w = vp[0]
  assert_eq(
    (w.slot, w.stops, w.count(), w.base),
    (@style.SLOT_SIZE, [14.0, 16.0, 18.0], 3, 2.0),
  )
  assert_eq(w.position(10), (0, 0.0))
  assert_eq(w.position(14), (0, 0.0))
  assert_eq(w.position(15), (0, 1.0 / 3.0))
  assert_eq(w.position(16), (1, 0.0))
  assert_eq(w.position(18), (1, 1.0))
  assert_eq(w.position(22), (1, 1.0))
}

///|
test "a zoom step keeps its first value and each stop's, without blending" {
  let l = layer(
    "{\"id\": \"l\", \"type\": \"line\", \"source\": \"s\", \"paint\": {\"line-color\": [\"step\", [\"zoom\"], [\"get\", \"c\"], 15, \"#000\"]}}",
  )
  let c = l.vertex_paint()[0]
  assert_eq((c.step, c.count()), (true, 2))
  assert_eq(c.position(14), (0, 0.0))
  assert_eq(c.position(15), (0, 1.0))
  assert_eq(c.position(20), (0, 1.0))
}

///|
test "encode writes each output as a word, defaults for missing values" {
  let c = layer(
    "{\"id\": \"c\", \"type\": \"circle\", \"source\": \"s\", \"paint\": {\"circle-radius\": [\"get\", \"r\"], \"circle-color\": [\"match\", [\"get\", \"c\"], \"a\", \"#ff8000\", \"rgba(0, 0, 255, 0.5)\"]}}",
  )
  let vp = c.vertex_paint()
  let out = FixedArray::make(@style.vertex_paint_words(vp), 0)
  let ctx = { props: Map([("r", Num(2.5)), ("c", Str("a"))]), }
  let at = vp[0].encode(14, ctx, out, 0)
  assert_eq(at, 1)
  assert_eq(out[0], 0xff0080ff)
  vp[0].encode(14, { props: Map([]), }, out, 0) |> ignore
  assert_eq(out[0], 0x80ff0000)
  assert_eq(vp[1].encode(14, ctx, out, at), 2)
  assert_eq(out[1], Float::from_double(2.5).reinterpret_as_int())
  // A missing radius takes the default, 5.
  let missing = FixedArray::make(1, 0)
  vp[1].encode(14, { props: Map([]), }, missing, 0) |> ignore
  assert_eq(missing[0], Float::from_double(5.0).reinterpret_as_int())
}
