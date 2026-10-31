///|
/// The properties shared by one group of a data-driven layer (a JS object
/// from the worker), as expressions see them; `$type` holds the geometry type.
/// The main thread evaluates every paint through this one context type, so
/// the evaluator is compiled once (a JS null object stands for no feature).
priv struct JsProps {
  obj : JsValue
}

///|
fn JsProps::none() -> JsProps {
  { obj: js_null(), }
}

///|
impl @style.FeatureContext for JsProps with fn property(self, key) {
  match prop_kind(self.obj, key) {
    0 => None
    2 => Some(Bool(prop_bool(self.obj, key)))
    3 => Some(Num(get_double(self.obj, key)))
    4 => Some(Str(get_string(self.obj, key)))
    _ => Some(Null)
  }
}

///|
impl @style.FeatureContext for JsProps with fn geometry_type(self) {
  match prop_kind(self.obj, "$type") {
    4 => get_string(self.obj, "$type")
    _ => "Unknown"
  }
}

///|
/// A layer's paint values for one draw: color is straight RGBA.
priv struct Paint {
  r : Double
  g : Double
  b : Double
  a : Double
  width : Double
}

///|
fn number_or(v : @style.Value, default : Double) -> Double {
  match v {
    Num(n) => n
    _ => default
  }
}

///|
fn paint_of(layer : @style.StyleLayer, zoom : Double, ctx : JsProps) -> Paint {
  let c = match layer.color.eval(zoom, ctx) {
    Color(c) => c
    _ => { r: 0.0, g: 0.0, b: 0.0, a: 1.0, }
  }
  let opacity = number_or(layer.opacity.eval(zoom, ctx), 1.0)
  {
    r: c.r,
    g: c.g,
    b: c.b,
    a: c.a * opacity,
    width: number_or(layer.width.eval(zoom, ctx), 1.0),
  }
}
