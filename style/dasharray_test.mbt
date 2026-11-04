///|
fn dash_layer(paint : String) -> @style.StyleLayer raise @style.StyleError {
  @style.Style::parse(
    "{\"layers\": [{\"id\": \"a\", \"type\": \"line\", \"paint\": \{paint}}]}",
  ).layers[0]
}

///|
test "line-dasharray takes plain arrays and zoom expressions" {
  assert_true(dash_layer("{}").dasharray is None)
  let at = (l : @style.StyleLayer, z : Double) => {
    l.dasharray.unwrap().eval(z, @style.NoFeature::{ })
  }
  let plain = dash_layer("{\"line-dasharray\": [2, 1.5]}")
  assert_eq(at(plain, 10), List([Num(2.0), Num(1.5)]))
  let stepped = dash_layer(
    "{\"line-dasharray\": [\"step\", [\"zoom\"], [\"literal\", [1, 1]], 14, [\"literal\", [3, 1]]]}",
  )
  assert_eq(at(stepped, 13), List([Num(1.0), Num(1.0)]))
  assert_eq(at(stepped, 14), List([Num(3.0), Num(1.0)]))
  // Only lines have dashes.
  assert_true(
    @style.Style::parse(
      "{\"layers\": [{\"id\": \"a\", \"type\": \"fill\", \"paint\": {\"line-dasharray\": [1, 1]}}]}",
    ).layers[0].dasharray
    is None,
  )
}

///|
test "data-driven dashes go by feature, except with feature state or drawn by groups" {
  let by_feature = dash_layer(
    "{\"line-dasharray\": [\"case\", [\"has\", \"k\"], [\"literal\", [1, 1]], [\"literal\", [2, 1]]]}",
  )
  assert_true(by_feature.feature_dashes() is Some(_))
  assert_true(
    dash_layer("{\"line-dasharray\": [2, 1]}").feature_dashes() is None,
  )
  for
    bad in [
      "{\"line-dasharray\": [\"case\", [\"==\", [\"feature-state\", \"h\"], true], [\"literal\", [1, 1]], [\"literal\", [2, 1]]]}",
      "{\"line-dasharray\": [\"case\", [\"has\", \"k\"], [\"literal\", [1, 1]], [\"literal\", [2, 1]]], \"line-opacity\": [\"feature-state\", \"o\"]}",
    ] {
    try dash_layer(bad) catch {
      Unsupported(path~, _) => assert_eq(path, "layers[0].paint.line-dasharray")
      Invalid(_, ..) => fail("unexpected Invalid")
    } noraise {
      _ => fail("expected Unsupported")
    }
  }
}
