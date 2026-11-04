///|
#external
type Js

///|
extern "js" fn js_kind(v : Js) -> Int32 =
  #|(v) => v === undefined ? 0 : v === null ? 1 : typeof v === "boolean" ? 2 : typeof v === "number" ? 3 : typeof v === "string" ? 4 : 5

///|
extern "js" fn js_key(o : Js, k : String) -> Js = "(o, k) => Object.hasOwn(o, k) ? o[k] : undefined"

///|
extern "js" fn js_bool(v : Js) -> Bool = "(v) => v"

///|
extern "js" fn js_double(v : Js) -> Double = "(v) => v"

///|
extern "js" fn js_string(v : Js) -> String = "(v) => v"

///|
extern "js" fn js_length(v : Js) -> Int32 = "(v) => v.length"

///|
extern "js" fn js_at(v : Js, i : Int32) -> Js = "(v, i) => v[i]"

///|
extern "js" fn js_of_double(x : Double) -> Js = "(x) => x"

///|
extern "js" fn js_of_string(s : String) -> Js = "(s) => s"

///|
extern "js" fn js_of_bool(b : Bool) -> Js = "(b) => b"

///|
extern "js" fn js_null() -> Js = "() => null"

///|
extern "js" fn js_array() -> Js = "() => []"

///|
extern "js" fn js_push(a : Js, v : Js) -> Unit = "(a, v) => { a.push(v) }"

///|
extern "js" fn js_color(r : Double, g : Double, b : Double, a : Double) -> Js =
  #|(r, g, b, a) => ({ color: [r, g, b, a] })

///|
extern "js" fn js_failed() -> Js = "() => ({ error: true })"

///|
extern "js" fn js_number_text(x : Double) -> String = "String"

///|
extern "js" fn js_text_number(s : String) -> Double = "Number"

///|
/// A feature `{ type, properties, id }` as the golden test passes it, read as
/// the main thread reads group properties (`map/paint.mbt`), with the hooks of
/// the display worker: the host's `Math`, `String` and `Number`.
priv struct JsFeature {
  obj : Js
}

///|
fn style_value(v : Js) -> @style.Value? {
  match js_kind(v) {
    0 => None
    1 => Some(Null)
    2 => Some(Bool(js_bool(v)))
    3 => Some(Num(js_double(v)))
    4 => Some(Str(js_string(v)))
    _ => Some(Null)
  }
}

///|
let js_trig : @core.Trig = @core.Trig::moonbit()

///|
impl @style.FeatureContext for JsFeature with fn property(self, key) {
  style_value(js_key(js_key(self.obj, "properties"), key))
}

///|
impl @style.FeatureContext for JsFeature with fn geometry_type(self) {
  match js_double(js_key(self.obj, "type")) {
    1.0 => "Point"
    2.0 => "LineString"
    3.0 => "Polygon"
    _ => "Unknown"
  }
}

///|
impl @style.FeatureContext for JsFeature with fn id(self) {
  style_value(js_key(self.obj, "id")).unwrap_or(Null)
}

///|
impl @style.FeatureContext for JsFeature with fn trig(_) {
  js_trig
}

///|
impl @style.FeatureContext for JsFeature with fn number_text(_, x) {
  js_number_text(x)
}

///|
impl @style.FeatureContext for JsFeature with fn text_number(_, s) {
  js_text_number(s)
}

///|
fn result_js(v : @style.Value) -> Js {
  match v {
    Null => js_null()
    Bool(b) => js_of_bool(b)
    Num(x) => js_of_double(x)
    Str(s) => js_of_string(s)
    Color(c) => js_color(c.r, c.g, c.b, c.a)
    List(xs) => {
      let a = js_array()
      for x in xs {
        js_push(a, result_js(x))
      }
      a
    }
    Formatted(sections) => {
      let a = js_array()
      for s in sections {
        let row = js_array()
        js_push(row, js_of_string(s.text))
        js_push(row, s.scale.map(js_of_double).unwrap_or(js_null()))
        js_push(row, s.font.map(js_of_string).unwrap_or(js_null()))
        js_push(
          row,
          s.color.map(c => js_color(c.r, c.g, c.b, c.a)).unwrap_or(js_null()),
        )
        js_push(row, s.align.map(js_of_string).unwrap_or(js_null()))
        js_push(a, row)
      }
      js_wrap("formatted", a)
    }
    Collator(case, diacritic, locale) => {
      let a = js_array()
      js_push(a, js_of_bool(case))
      js_push(a, js_of_bool(diacritic))
      js_push(a, locale.map(js_of_string).unwrap_or(js_null()))
      js_wrap("collator", a)
    }
    Failed => js_failed()
  }
}

///|
extern "js" fn js_wrap(key : String, v : Js) -> Js = "(k, v) => ({ [k]: v })"

///|
/// `expression` (JSON text) compiled for `expected` and evaluated at `zoom` for each
/// feature (`global-state` from `state`, JSON text): an array of results (`{ color }`,
/// `{ error }`, `{ formatted }`, `{ collator }` or plain values), or the compile error.
#export_name("expr_eval")
pub fn expr_eval(
  expression : String,
  expected : String,
  zoom : Double,
  features : Js,
  state : String,
) -> Js {
  let expected : @style.Expected = match expected {
    "number" => NumberType
    "string" => StringType
    "boolean" => BoolType
    "color" => ColorType
    _ => AnyType
  }
  let json = @json.parse(expression) catch {
    e => return js_of_string("not JSON: \{e}")
  }
  let state = @json.parse(state) catch { _ => Json::null() }
  let state = match state {
    Object(o) => o
    _ => Map([])
  }
  let e = @style.with_global_state(state, () => @style.compile(json, expected~)) catch {
    e => return js_of_string(e.message())
  }
  let out = js_array()
  for i in 0..<js_length(features) {
    js_push(
      out,
      result_js(e.eval(zoom, JsFeature::{ obj: js_at(features, i), })),
    )
  }
  out
}

///|
/// `s` read by `@style.parse_color`: `{ color }` (straight RGBA) or null.
#export_name("color_parse")
pub fn color_parse(s : String) -> Js {
  match @style.parse_color(s) {
    Some(c) => js_color(c.r, c.g, c.b, c.a)
    None => js_null()
  }
}
