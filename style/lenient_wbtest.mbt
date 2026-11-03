///|
test "removable finds the property an issue lies in" {
  assert_eq(
    removable("layers[0].paint.line-color[2][1]", "layers[0]"),
    Some(("paint", "line-color")),
  )
  assert_eq(
    removable("sources.s.clusterProperties", "sources.s"),
    Some(("", "clusterProperties")),
  )
  assert_eq(removable("layers[0].filter[1]", "layers[0]"), None)
  assert_eq(removable("layers[0]", "layers[0]"), None)
  assert_eq(removable("layers[0].paint", "layers[0]"), None)
}

///|
test "without_key leaves the input alone" {
  let json : Json = { "paint": { "a": 1, "b": 2 }, "id": "x" }
  assert_eq(without_key(json, "paint", "a"), { "paint": { "b": 2 }, "id": "x" })
  assert_eq(without_key(json, "", "id"), { "paint": { "a": 1, "b": 2 } })
  assert_eq(json, { "paint": { "a": 1, "b": 2 }, "id": "x" })
}
