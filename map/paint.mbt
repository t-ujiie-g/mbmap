///|
/// The properties a data-driven layer's group shares (a JS object from the
/// worker; null for no feature). The only context type on the main thread, so
/// `Expr::eval` is compiled into the bundle once.
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
  match prop_kind(self.obj, @core.GEOMETRY_TYPE_KEY) {
    4 => get_string(self.obj, @core.GEOMETRY_TYPE_KEY)
    _ => "Unknown"
  }
}

///|
/// A layer's paint values for one draw: colors are straight RGBA; `width` is
/// the line width, `radius` and the stroke values those of circles (0 and
/// transparent for other kinds).
priv struct Paint {
  r : Double
  g : Double
  b : Double
  a : Double
  width : Double
  radius : Double
  stroke : FixedArray[Double]
  stroke_width : Double
  halo : FixedArray[Double]
  halo_width : Double
}

///|
fn number_or(v : @style.Value, default : Double) -> Double {
  match v {
    Num(n) => n
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
fn paint_of(layer : @style.StyleLayer, zoom : Double, ctx : JsProps) -> Paint {
  let c = color_of(layer.color, zoom, ctx)
  let opacity = number_or(layer.opacity.eval(zoom, ctx), 1.0)
  let circle = layer.kind is Circle
  let symbol = layer.kind is Symbol
  let stroke : FixedArray[Double] = if circle {
    let s = color_of(layer.stroke_color, zoom, ctx)
    let o = number_or(layer.stroke_opacity.eval(zoom, ctx), 1.0)
    [s.r, s.g, s.b, s.a * o]
  } else {
    [0.0, 0.0, 0.0, 0.0]
  }
  {
    r: c.r,
    g: c.g,
    b: c.b,
    a: c.a * opacity,
    width: number_or(layer.width.eval(zoom, ctx), 1.0),
    radius: if circle {
      number_or(layer.radius.eval(zoom, ctx), 5.0)
    } else {
      0.0
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
  }
}
