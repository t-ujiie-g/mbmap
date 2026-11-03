///|
/// A context at heatmap density `d`.
struct Dense {
  d : Double
}

///|
impl @style.FeatureContext for Dense with fn property(_, _) {
  None
}

///|
impl @style.FeatureContext for Dense with fn geometry_type(_) {
  "Point"
}

///|
impl @style.FeatureContext for Dense with fn heatmap_density(self) {
  self.d
}

///|
fn heatmap_style(paint : String) -> @style.Style raise @style.StyleError {
  @style.Style::parse(
    "{\"layers\": [{\"id\": \"h\", \"type\": \"heatmap\", \"source\": \"s\", \"paint\": \{paint}}]}",
  )
}

///|
fn at10(e : @style.Expr) -> @style.Value {
  e.eval(10.0, @style.NoFeature::{ })
}

///|
test "heatmap layers take MapLibre's defaults" {
  let l = heatmap_style("{}").layers[0]
  assert_true(l.kind is Heatmap)
  let h = l.heatmap.unwrap()
  assert_eq(at10(l.radius), Num(30.0))
  assert_eq(at10(h.weight), Num(1.0))
  assert_eq(at10(h.intensity), Num(1.0))
  assert_eq(at10(l.opacity), Num(1.0))
  assert_eq(
    h.color.eval(0.0, { d: 0.0, }),
    Color({ r: 0.0, g: 0.0, b: 1.0, a: 0.0, }),
  )
  assert_eq(
    h.color.eval(0.0, { d: 0.5, }),
    Color({ r: 0.0, g: 1.0, b: 0.0, a: 1.0, }),
  )
  assert_eq(
    h.color.eval(0.0, { d: 1.0, }),
    Color({ r: 1.0, g: 0.0, b: 0.0, a: 1.0, }),
  )
  assert_eq(h.color.eval(0.0, @style.NoFeature::{ }), Failed)
  assert_true(heatmap_style("{}").layers[0].heatmap is Some(_))
  let circle = @style.Style::parse(
    "{\"layers\": [{\"id\": \"c\", \"type\": \"circle\", \"source\": \"s\"}]}",
  )
  assert_true(circle.layers[0].heatmap is None)
}

///|
test "heatmap paint is read from its own properties" {
  let l = heatmap_style(
      "{\"heatmap-radius\": 12, \"heatmap-weight\": [\"get\", \"w\"], \"heatmap-intensity\": [\"interpolate\", [\"linear\"], [\"zoom\"], 0, 1, 20, 3], \"heatmap-opacity\": 0.5, \"heatmap-color\": [\"step\", [\"heatmap-density\"], \"#000000\", 0.5, \"#ffffff\"]}",
    ).layers[0]
  let h = l.heatmap.unwrap()
  assert_eq(at10(l.radius), Num(12.0))
  assert_eq(at10(h.intensity), Num(2.0))
  assert_eq(at10(l.opacity), Num(0.5))
  assert_eq(
    h.color.eval(0.0, { d: 0.7, }),
    Color({ r: 1.0, g: 1.0, b: 1.0, a: 1.0, }),
  )
}

///|
test "heatmap-density only in heatmap-color, which reads nothing else" {
  for
    bad in [
      "{\"heatmap-radius\": [\"heatmap-density\"]}", "{\"heatmap-weight\": [\"heatmap-density\"]}",
      "{\"heatmap-color\": [\"interpolate\", [\"linear\"], [\"zoom\"], 0, \"#000000\", 1, \"#ffffff\"]}",
      "{\"heatmap-color\": [\"to-color\", [\"get\", \"c\"]]}", "{\"heatmap-intensity\": [\"get\", \"i\"]}",
    ] {
    try heatmap_style(bad) catch {
      Invalid(path~, _) => assert_true(path.has_prefix("layers[0]"))
      Unsupported(_, ..) => fail("unexpected Unsupported for \{bad}")
    } noraise {
      _ => fail("expected Invalid for \{bad}")
    }
  }
  try
    @style.Style::parse(
      "{\"layers\": [{\"id\": \"c\", \"type\": \"circle\", \"paint\": {\"circle-radius\": [\"heatmap-density\"]}}]}",
    )
  catch {
    Invalid(path~, _) => assert_eq(path, "layers[0]")
    Unsupported(_, ..) => fail("unexpected Unsupported")
  } noraise {
    _ => fail("expected Invalid")
  }
  try heatmap_style("{\"heatmap-weight\": [\"feature-state\", \"w\"]}") catch {
    Unsupported(path~, _) => assert_eq(path, "layers[0].paint")
    Invalid(_, ..) => fail("unexpected Invalid")
  } noraise {
    _ => fail("expected Unsupported")
  }
}

///|
test "data-driven or state heatmap-intensity is Invalid at its own path" {
  for
    bad in [
      "{\"heatmap-intensity\": [\"get\", \"i\"]}", "{\"heatmap-intensity\": [\"feature-state\", \"i\"]}",
    ] {
    try heatmap_style(bad) catch {
      Invalid(path~, _) => assert_eq(path, "layers[0].paint.heatmap-intensity")
      Unsupported(path~, _) => fail("unexpected Unsupported at \{path}")
    } noraise {
      _ => fail("expected Invalid for \{bad}")
    }
  }
}

///|
test "a heatmap's data-driven weight and radius go per vertex" {
  let l = heatmap_style(
      "{\"heatmap-weight\": [\"get\", \"w\"], \"heatmap-radius\": [\"interpolate\", [\"linear\"], [\"zoom\"], 10, [\"get\", \"r\"], 14, 40]}",
    ).layers[0]
  let vp = l.vertex_paint()
  assert_eq(vp.map(p => (p.slot, p.count(), p.default)), [
    (@style.SLOT_WEIGHT, 1, 1.0),
    (@style.SLOT_SIZE, 2, 30.0),
  ])
  assert_true(
    heatmap_style("{\"heatmap-radius\": 9}").layers[0].vertex_paint().is_empty(),
  )
}
