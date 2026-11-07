///|
extern "js" fn features_of(json : String) -> FixedArray[Properties] =
  #|(s) => JSON.parse(s)

///|
extern "js" fn values_text(v : ExpressionValues) -> String =
  #|(v) => JSON.stringify(v)

///|
test "evaluate_expression gives each feature's value, colors and format as text" {
  let fs = features_of(
    "[{\"a\": 2, \"$id\": 7, \"$type\": \"Point\"}, {\"a\": \"x\"}, {}]",
  )
  let ev = (e : String) => values_text(evaluate_expression(e, fs, 3.0))
  assert_eq(ev("[\"*\", [\"get\", \"a\"], [\"zoom\"]]"), "[6,null,null]")
  assert_eq(
    ev("[\"concat\", [\"id\"], [\"geometry-type\"]]"),
    "[\"7Point\",\"Unknown\",\"Unknown\"]",
  )
  assert_eq(
    ev("[\"to-color\", \"rgba(10, 20, 30, 0.5)\"]"),
    "[\"rgba(10,20,30,0.5)\",\"rgba(10,20,30,0.5)\",\"rgba(10,20,30,0.5)\"]",
  )
  assert_eq(
    ev("[\"literal\", [1, \"b\", true]]"),
    "[[1,\"b\",true],[1,\"b\",true],[1,\"b\",true]]",
  )
  assert_eq(ev("[\"format\", \"a\", {}, \"b\", {}]"), "[\"ab\",\"ab\",\"ab\"]")
  assert_eq(ev("[\"collator\", {}]"), "[null,null,null]")
}

///|
test "evaluate_expression gives the message of an expression that does not compile" {
  assert_eq(
    values_text(evaluate_expression("[\"nope\"]", features_of("[]"), 0.0)),
    "\"unsupported: expression nope\"",
  )
}
