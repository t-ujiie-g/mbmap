///|
/// A feature with a state, for evaluating `feature-state`.
struct Stated {
  state : Map[String, @style.Value]
}

///|
impl @style.FeatureContext for Stated with fn property(_, _) {
  None
}

///|
impl @style.FeatureContext for Stated with fn geometry_type(_) {
  "Point"
}

///|
impl @style.FeatureContext for Stated with fn state(self, key) {
  self.state.get(key)
}

///|
test "feature-state reads the context's state; other contexts have none" {
  let e = @style.compile(
    @json.parse(
      "[\"case\", [\"boolean\", [\"feature-state\", \"on\"], false], 1, 2]",
    ),
  )
  assert_eq(e.eval(0.0, { state: Map([("on", Bool(true))]), }), Num(1.0))
  assert_eq(e.eval(0.0, { state: Map([]), }), Num(2.0))
  assert_eq(e.eval(0.0, @style.NoFeature::{ }), Num(2.0))
  assert_true(e.reads_state())
  assert_eq(e.feature_inputs(), ([], false))
}

///|
test "boolean, number and string give their first argument of that type" {
  let ctx = { state: Map([("n", Num(3.0)), ("s", Str("x"))]), }
  let eval = (text : String) => @style.compile(@json.parse(text)).eval(0.0, ctx)
  assert_eq(
    eval("[\"number\", [\"feature-state\", \"s\"], [\"feature-state\", \"n\"]]"),
    Num(3.0),
  )
  assert_eq(eval("[\"string\", [\"feature-state\", \"s\"]]"), Str("x"))
  assert_eq(eval("[\"boolean\", [\"feature-state\", \"n\"]]"), Failed)
  assert_false(@style.compile(@json.parse("[\"number\", 1]")).reads_state())
  let bare = @json.parse("[\"boolean\"]")
  try @style.compile(bare) catch {
    e => assert_eq(e.message(), "boolean needs a value")
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "feature-state is refused in filters and marks layers that read it" {
  let layer = (paint : String, filter : String) => {
    @style.Style::parse(
      "{\"sources\": {\"s\": {\"type\": \"geojson\", \"data\": \"x\"}}, \"layers\": [{\"id\": \"a\", \"type\": \"fill\", \"source\": \"s\"\{filter}, \"paint\": \{paint}}]}",
    ).layers[0]
  }
  let stated = layer(
    "{\"fill-color\": [\"case\", [\"boolean\", [\"feature-state\", \"on\"], false], \"#f00\", \"#00f\"]}",
    "",
  )
  let plain = layer("{\"fill-color\": \"#00f\"}", "")
  assert_true(stated.reads_state())
  assert_false(plain.reads_state())
  assert_false(stated.same_tiles(plain))
  try
    layer("{}", ", \"filter\": [\"==\", [\"feature-state\", \"on\"], true]")
  catch {
    e =>
      assert_eq(
        e.message(),
        "layers[0].filter: feature-state is only allowed in paint properties",
      )
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "promoteId names a property for all source layers or one per layer" {
  let source = (promote : String) => {
    @style.Style::parse(
      "{\"sources\": {\"v\": {\"type\": \"vector\", \"tiles\": [\"https://x/{z}/{x}/{y}.pbf\"]\{promote}}}, \"layers\": []}",
    ).sources[0].promote_id
  }
  assert_eq(source(""), FeatureId)
  assert_eq(source(", \"promoteId\": \"k\"").property("any"), Some("k"))
  let by_layer = source(", \"promoteId\": {\"road\": \"rid\"}")
  assert_eq(
    (by_layer.property("road"), by_layer.property("water")),
    (Some("rid"), None),
  )
  assert_false(
    @style.Style::parse(
      "{\"sources\": {\"v\": {\"type\": \"vector\", \"tiles\": [\"https://x/{z}/{x}/{y}.pbf\"], \"promoteId\": \"k\"}}, \"layers\": []}",
    ).sources[0].same(
      @style.Style::parse(
        "{\"sources\": {\"v\": {\"type\": \"vector\", \"tiles\": [\"https://x/{z}/{x}/{y}.pbf\"]}}, \"layers\": []}",
      ).sources[0],
    ),
  )
  try source(", \"promoteId\": 3") catch {
    e =>
      assert_eq(e.message(), "sources.v.promoteId: not a string or an object")
  } noraise {
    _ => fail("expected an error")
  }
}
