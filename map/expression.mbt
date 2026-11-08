///|
/// The values of expression `text` (JSON) for each of `features` (properties,
/// id at `@style.FEATURE_ID_KEY`, type at `@core.GEOMETRY_TYPE_KEY`) at `zoom`
/// as a JS array (colors by `to-string`, errors null), or the compile error.
pub fn evaluate_expression(
  text : String,
  features : FixedArray[Properties],
  zoom : Double,
) -> ExpressionValues {
  let json = parse_json(text)
  let e = @style.compile(json) catch {
    err => return as_values(string_value(err.message()))
  }
  let out = FixedArray::makei(features.length(), i => {
    js_of_value(
      e.eval(zoom, { ..JsProps::none(), obj: properties_value(features[i]), }),
    )
  })
  as_values(values_array(out))
}

///|
/// What `evaluate_expression` gives: a JS array of values, or a string.
#external
pub type ExpressionValues

///|
extern "js" fn as_values(v : JsValue) -> ExpressionValues = "(v) => v"

///|
fn js_of_value(v : @style.Value) -> JsValue {
  match v {
    Null | Failed | Collator(_, _, _) => js_null()
    Bool(b) => bool_value(b)
    Num(x) => number_value(x)
    Str(s) => string_value(s)
    Color(c) => string_value(color_text(c.r, c.g, c.b, c.a))
    List(xs) =>
      values_array(FixedArray::makei(xs.length(), i => js_of_value(xs[i])))
    Formatted(sections) => string_value(sections.map(s => s.text).join(""))
  }
}

///|
extern "js" fn bool_value(b : Bool) -> JsValue = "(b) => b"

///|
extern "js" fn number_value(x : Double) -> JsValue = "(x) => x"

///|
extern "js" fn string_value(s : String) -> JsValue = "(s) => s"

///|
extern "js" fn values_array(xs : FixedArray[JsValue]) -> JsValue = "(xs) => xs"

///|
/// MapLibre's `Color.toString` of straight RGBA in 0..1: `rgba(r,g,b,a)`,
/// channels rounded as `Math.round` does.
extern "js" fn color_text(
  r : Double,
  g : Double,
  b : Double,
  a : Double,
) -> String =
  #|(r, g, b, a) => `rgba(${Math.round(r * 255)},${Math.round(g * 255)},${Math.round(b * 255)},${a})`
