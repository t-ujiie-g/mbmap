///|
test "state_defaults takes each state key's default, null without one" {
  let state = state_defaults(
    @json.parse(
      "{\"state\": {\"min\": {\"default\": 3}, \"none\": {}, \"bad\": 1}}",
    ),
  )
  assert_eq(state.get("min"), Some(Json::number(3.0)))
  assert_eq(state.get("none"), Some(Json::null()))
  assert_eq(state.get("bad"), Some(Json::null()))
  assert_eq(state_defaults(@json.parse("[]")).length(), 0)
}
