///|
/// A data-driven group's properties (a JS object from the worker, or null) and a
/// feature's state (from `set_feature_state`, or null): the main thread's only
/// context type, so `Expr::eval` is compiled into the bundle once.
priv struct JsProps {
  obj : JsValue
  state : JsValue
  progress : Double
  density : Double
  elevation : Double
}

///|
fn JsProps::none() -> JsProps {
  {
    obj: js_null(),
    state: js_null(),
    progress: @double.not_a_number,
    density: @double.not_a_number,
    elevation: @double.not_a_number,
  }
}

///|
/// A JS object's value at `key` as an expression value; None if absent.
fn js_value(obj : JsValue, key : String) -> @style.Value? {
  match prop_kind(obj, key) {
    0 => None
    2 => Some(Bool(prop_bool(obj, key)))
    3 => Some(Num(get_double(obj, key)))
    4 => Some(Str(get_string(obj, key)))
    _ => Some(Null)
  }
}

///|
impl @style.FeatureContext for JsProps with fn property(self, key) {
  js_value(self.obj, key)
}

///|
impl @style.FeatureContext for JsProps with fn state(self, key) {
  js_value(self.state, key)
}

///|
impl @style.FeatureContext for JsProps with fn id(self) {
  js_value(self.obj, @style.FEATURE_ID_KEY).unwrap_or(Null)
}

///|
/// `@math` is the browser's `Math` in the js backend.
let js_trig : @core.Trig = @core.Trig::moonbit()

///|
/// Where along a line a gradient is evaluated (NaN elsewhere).
impl @style.FeatureContext for JsProps with fn line_progress(self) {
  self.progress
}

///|
/// The density a heatmap's color ramp is evaluated at (NaN elsewhere).
impl @style.FeatureContext for JsProps with fn heatmap_density(self) {
  self.density
}

///|
/// The elevation a color relief's ramp is evaluated at (NaN elsewhere).
impl @style.FeatureContext for JsProps with fn elevation(self) {
  self.elevation
}

///|
impl @style.FeatureContext for JsProps with fn trig(_) {
  js_trig
}

///|
impl @style.FeatureContext for JsProps with fn number_text(_, x) {
  js_number_text(x)
}

///|
impl @style.FeatureContext for JsProps with fn text_number(_, s) {
  js_text_number(s)
}

///|
extern "js" fn js_number_text(x : Double) -> String = "String"

///|
extern "js" fn js_text_number(s : String) -> Double = "Number"

///|
impl @style.FeatureContext for JsProps with fn geometry_type(self) {
  match prop_kind(self.obj, @core.GEOMETRY_TYPE_KEY) {
    4 => get_string(self.obj, @core.GEOMETRY_TYPE_KEY)
    _ => "Unknown"
  }
}

///|
/// A layer's paint for one draw, colors straight RGBA (`r`..`a` with the opacity in; `color` and `opacity`
/// apart, as the shaders' slots take them): `width` a line's, `radius` a circle's or heatmap's, `weight` a
/// heatmap's, the stroke a circle's (else 0, transparent); `pattern` a fill's or background's image.
priv struct Paint {
  r : Double
  g : Double
  b : Double
  a : Double
  color : @style.Color
  opacity : Double
  stroke_color : @style.Color
  stroke_opacity : Double
  width : Double
  radius : Double
  weight : Double
  stroke : FixedArray[Double]
  stroke_width : Double
  halo : FixedArray[Double]
  halo_width : Double
  pattern : String?
  gap_width : Double
  offset : Double
  blur : Double
}

///|
fn number_or(v : @style.Value, default : Double) -> Double {
  match v {
    Num(n) if n == n => n
    _ => default
  }
}

///|
fn color_of(e : @style.Expr, zoom : Double, ctx : JsProps) -> @style.Color {
  match e.eval(zoom, ctx) {
    Color(c) => c
    _ => { r: 0.0, g: 0.0, b: 0.0, a: 1.0, }
  }
}

///|
/// `c` as straight RGBA, as the renderer takes colors.
fn rgba_of(c : @style.Color) -> FixedArray[Double] {
  [c.r, c.g, c.b, c.a]
}

///|
/// The paint's color with its opacity applied, as straight RGBA.
fn Paint::rgba(self : Paint) -> FixedArray[Double] {
  [self.r, self.g, self.b, self.a]
}

///|
fn paint_of(layer : @style.StyleLayer, zoom : Double, ctx : JsProps) -> Paint {
  let c = color_of(layer.color, zoom, ctx)
  let opacity = number_or(layer.opacity.eval(zoom, ctx), 1.0)
  let circle = layer.kind is Circle
  let heatmap = layer.kind is Heatmap
  let symbol = layer.kind is Symbol
  // A fill's stroke is its outline: its own color, or its fill color.
  let stroke_color = match (layer.kind, layer.outline_color) {
    (Fill, Some(e)) => color_of(e, zoom, ctx)
    (Fill, None) => c
    _ => color_of(layer.stroke_color, zoom, ctx)
  }
  let stroke_opacity = number_or(layer.stroke_opacity.eval(zoom, ctx), 1.0)
  let stroke : FixedArray[Double] = if circle {
    let s = stroke_color
    [s.r, s.g, s.b, s.a * stroke_opacity]
  } else {
    [0.0, 0.0, 0.0, 0.0]
  }
  {
    r: c.r,
    g: c.g,
    b: c.b,
    a: c.a * opacity,
    color: c,
    opacity,
    stroke_color,
    stroke_opacity,
    width: number_or(layer.width.eval(zoom, ctx), 1.0),
    radius: if circle {
      number_or(layer.radius.eval(zoom, ctx), 5.0)
    } else if heatmap {
      number_or(layer.radius.eval(zoom, ctx), 30.0)
    } else {
      0.0
    },
    weight: match layer.heatmap {
      Some(h) => number_or(h.weight.eval(zoom, ctx), 1.0)
      None => 1.0
    },
    stroke,
    stroke_width: if circle {
      number_or(layer.stroke_width.eval(zoom, ctx), 0.0)
    } else {
      0.0
    },
    halo: if symbol {
      let h = color_of(layer.halo_color, zoom, ctx)
      [h.r, h.g, h.b, h.a * opacity]
    } else {
      [0.0, 0.0, 0.0, 0.0]
    },
    halo_width: if symbol {
      number_or(layer.halo_width.eval(zoom, ctx), 0.0)
    } else {
      0.0
    },
    gap_width: number_or(layer.gap_width.eval(zoom, ctx), 0.0),
    offset: number_or(layer.offset.eval(zoom, ctx), 0.0),
    blur: number_or(layer.blur.eval(zoom, ctx), 0.0),
    pattern: match layer.pattern {
      Some(e) =>
        match e.eval(@cmp.maximum(0.0, zoom.floor()), ctx) {
          Str(name) => Some(name)
          _ => None
        }
      None => None
    },
  }
}

///|
/// A feature's properties, a plain JS object.
#external
pub type Properties

///|
/// What `Map::paint_at` gives: a JS object, or null.
#external
pub type PaintValues

///|
extern "js" fn properties_value(p : Properties) -> JsValue = "(p) => p"

///|
extern "js" fn no_paint() -> PaintValues = "() => null"

///|
extern "js" fn paint_object(
  rgba : FixedArray[Double],
  width : Double,
  radius : Double,
  stroke : FixedArray[Double],
  stroke_width : Double,
  halo : FixedArray[Double],
  halo_width : Double,
) -> PaintValues =
  #|(color, width, radius, stroke, strokeWidth, halo, haloWidth) => ({ color, width, radius, stroke, strokeWidth, halo, haloWidth })

///|
/// Layer `id`'s paint at the current zoom for a feature with properties
/// `props`, as drawn: `{ color, width, radius, stroke, strokeWidth, halo,
/// haloWidth }` (straight RGBA, opacity applied); null for an unknown layer.
pub fn Map::paint_at(
  self : Map,
  id : String,
  props : Properties,
) -> PaintValues {
  guard self.style.layers.search_by(l => l.id == id) is Some(i) else {
    return no_paint()
  }
  let p = paint_of(self.style.layers[i], self.transform.camera.zoom, {
    ..JsProps::none(),
    obj: properties_value(props),
  })
  paint_object(
    p.rgba(),
    p.width,
    p.radius,
    p.stroke,
    p.stroke_width,
    p.halo,
    p.halo_width,
  )
}
