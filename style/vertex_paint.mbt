///|
/// A data-driven paint property given per vertex (docs/FORMATS.md, "Vertex paint"):
/// `outputs` at the `stops` of its top-level zoom curve (or the whole expression),
/// each stored per vertex, a color as packed RGBA, a number as a 32-bit float.
pub struct VertexPaint {
  slot : Int32
  color : Bool
  stops : Array[Double]
  step : Bool
  base : Double
  outputs : Array[Expr]
  default : Double
}

///|
/// The paint slots per vertex, in order, of fills (color, opacity), lines
/// (and width) and circles (and radius, stroke color, opacity and width); a
/// slot's index is its attribute in the shaders.
pub const SLOT_COLOR : Int32 = 0

///|
pub const SLOT_OPACITY : Int32 = 1

///|
pub const SLOT_SIZE : Int32 = 2

///|
pub const SLOT_STROKE_COLOR : Int32 = 3

///|
pub const SLOT_STROKE_OPACITY : Int32 = 4

///|
pub const SLOT_STROKE_WIDTH : Int32 = 5

///|
/// The paint expressions of a layer by slot, with their defaults (as
/// MapLibre's), or empty for kinds drawn otherwise.
fn StyleLayer::slots(self : StyleLayer) -> Array[(Int32, Expr, Bool, Double)] {
  let color = (SLOT_COLOR, self.color, true, 0.0)
  let opacity = (SLOT_OPACITY, self.opacity, false, 1.0)
  match self.kind {
    Fill =>
      match self.outline_color {
        Some(e) => [color, opacity, (SLOT_STROKE_COLOR, e, true, 0.0)]
        None => [color, opacity]
      }
    Line => [color, opacity, (SLOT_SIZE, self.width, false, 1.0)]
    Circle =>
      [
        color,
        opacity,
        (SLOT_SIZE, self.radius, false, 5.0),
        (SLOT_STROKE_COLOR, self.stroke_color, true, 0.0),
        (SLOT_STROKE_OPACITY, self.stroke_opacity, false, 1.0),
        (SLOT_STROKE_WIDTH, self.stroke_width, false, 0.0),
      ]
    _ => []
  }
}

///|
/// Whether `e` reads feature data (properties or the geometry type).
fn data_driven(e : Expr) -> Bool {
  let (keys, geometry) = e.feature_inputs()
  keys.length() > 0 || geometry
}

///|
/// The data-driven paint of a fill, line or circle layer that does not read
/// feature state, given per vertex; empty when there is none (or the layer is
/// drawn otherwise), so every value is the same for all its features.
pub fn StyleLayer::vertex_paint(self : StyleLayer) -> Array[VertexPaint] {
  if self.reads_state() {
    return []
  }
  let out = []
  for s in self.slots() {
    let (slot, e, color, default) = s
    guard data_driven(e) else { continue }
    let vp : VertexPaint = match e {
      Interpolate(Exponential(base), Rgb, Zoom, stops) =>
        {
          slot,
          color,
          stops: stops.map(s => s.0),
          step: false,
          base,
          outputs: stops.map(s => s.1),
          default,
        }
      Step(Zoom, first, stops) =>
        {
          slot,
          color,
          stops: stops.map(s => s.0),
          step: true,
          base: 1.0,
          outputs: [first, ..stops.map(s => s.1)],
          default,
        }
      _ =>
        {
          slot,
          color,
          stops: [],
          step: false,
          base: 1.0,
          outputs: [e],
          default,
        }
    }
    out.push(vp)
  }
  out
}

///|
/// The expressions `vertex_paint` computes into a layer's tiles, by slot.
fn StyleLayer::baked_paint(self : StyleLayer) -> Array[(Int32, Expr)] {
  if self.reads_state() {
    return []
  }
  self.slots().filter(s => data_driven(s.1)).map(s => (s.0, s.1))
}

///|
/// Values stored per vertex: one per output.
pub fn VertexPaint::count(self : VertexPaint) -> Int32 {
  self.outputs.length()
}

///|
/// The 32-bit words `paint` takes per vertex.
pub fn vertex_paint_words(paint : Array[VertexPaint]) -> Int32 {
  paint.fold(init=0, (n, p) => n + p.count())
}

///|
/// Where `zoom` falls on the curve: the stored value it starts from and how far
/// (0 to 1, as the expression interpolates) toward the next; a step stays at 0,
/// the last value is reached at 1, a single value is (0, 0).
pub fn VertexPaint::position(
  self : VertexPaint,
  zoom : Double,
  pow~ : (Double, Double) -> Double = @math.pow,
) -> (Int32, Double) {
  let n = self.stops.length()
  let last = self.count() - 2
  if last < 0 {
    return (0, 0.0)
  }
  let (i, t) = if n == 0 {
    (0, 0.0)
  } else if self.step {
    (self.stops.fold(init=0, (k, z) => if zoom >= z { k + 1 } else { k }), 0.0)
  } else if zoom <= self.stops[0] {
    (0, 0.0)
  } else if zoom >= self.stops[n - 1] {
    (n - 1, 0.0)
  } else {
    let mut i = 0
    while self.stops[i + 1] <= zoom {
      i += 1
    }
    (i, factor(pow, self.base, zoom, self.stops[i], self.stops[i + 1]))
  }
  if i > last {
    (last, 1.0)
  } else {
    (i, t)
  }
}

///|
/// Writes the property's words for feature `ctx` to `out` from `at`: its
/// outputs evaluated at `zoom` (missing values become the default). Returns
/// where it stopped.
pub fn[C : FeatureContext] VertexPaint::encode(
  self : VertexPaint,
  zoom : Double,
  ctx : C,
  out : FixedArray[Int32],
  at : Int32,
) -> Int32 {
  for i, e in self.outputs {
    out[at + i] = encode_value(e.eval(zoom, ctx), self.color, self.default)
  }
  at + self.count()
}

///|
/// A value as one word: a color as RGBA bytes (red lowest; black when not a
/// color), a number as a 32-bit float (`default` when not a number).
fn encode_value(v : Value, color : Bool, default : Double) -> Int32 {
  if color {
    let c = match v {
      Color(c) => c
      _ => { r: 0.0, g: 0.0, b: 0.0, a: 1.0, }
    }
    let byte = (x : Double) => {
      (@cmp.maximum(0.0, @cmp.minimum(1.0, x)) * 255.0).round().to_int()
    }
    byte(c.r) | (byte(c.g) << 8) | (byte(c.b) << 16) | (byte(c.a) << 24)
  } else {
    let n = match v {
      Num(n) if n == n => n
      _ => default
    }
    Float::from_double(n).reinterpret_as_int()
  }
}
