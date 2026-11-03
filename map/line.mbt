///|
/// Line mesh `m`'s color ramp for gradient `e` (MapLibre's `renderColorRamp`,
/// made again when the expression changes); None without line progress or past
/// `MAX_RAMP_PIXELS`.
fn Map::gradient_of(
  self : Map,
  m : LayerMesh,
  e : @style.Expr,
) -> @render_webgl2.Gradient? {
  guard m.clips is Some(clips) else { return None }
  if m.gradient is Some((was, g)) {
    if was == e {
      return Some(g)
    }
    self.renderer.release_gradient(g)
    m.gradient = None
  }
  let n = clips.length() - 1
  let step = match e {
    Step(_, _, _) => true
    Assert(_, [Step(_, _, _)]) | Coerce(_, [Step(_, _, _)]) => true
    _ => false
  }
  let width = @render_webgl2.ramp_width(
    step~,
    length=clips[n],
    max_size=MAX_RAMP_WIDTH,
  )
  if n / 2 > MAX_RAMP_WIDTH || width * (n / 2) > MAX_RAMP_PIXELS {
    return None
  }
  let rows = Array::makei(n, i => clips[i])
  let pixels = @render_webgl2.color_ramp(rows, width, p => {
    match e.eval(0.0, { ..JsProps::none(), progress: p, }) {
      Color(c) => (c.r, c.g, c.b, c.a)
      _ => (0.0, 0.0, 0.0, 0.0)
    }
  })
  let g = self.renderer.upload_gradient(pixels, width, n / 2, nearest=step)
  m.gradient = Some((e, g))
  Some(g)
}

///|
/// Widest color ramp: a size every WebGL2 implementation takes (its minimum
/// `MAX_TEXTURE_SIZE` is 2048).
const MAX_RAMP_WIDTH : Int32 = 2048

///|
/// Most pixels (each one an evaluation) a tile's ramp may have, and at most
/// `MAX_RAMP_WIDTH` rows; past them the lines are drawn with `line-color`.
const MAX_RAMP_PIXELS : Int32 = 1 << 20

///|
/// A dash pattern: a list of numbers of at least 0.
fn pattern_of(e : @style.Expr, zoom : Double) -> Array[Double]? {
  guard e.eval(zoom, JsProps::none()) is List(items) else { return None }
  let d = []
  for v in items {
    guard v is Num(n) && n >= 0.0 else { return None }
    d.push(n)
  }
  Some(d)
}

///|
/// The atlas entry of pattern `e` at the integer zoom below `zoom` and the
/// length its edges are smoothed over (as MapLibre at rest: the shorter of it and
/// the pattern a zoom away); None draws the line solid.
fn Map::dash_of(
  self : Map,
  e : @style.Expr,
  zoom : Double,
  round : Bool,
) -> (@render_webgl2.DashEntry, Double)? {
  let z = @cmp.maximum(0.0, zoom.floor())
  guard pattern_of(e, z) is Some(d) &&
    self.renderer.dash(d, round) is Some(entry) else {
    return None
  }
  let from = if zoom > z { z - 1.0 } else { z + 1.0 }
  let gamma = match pattern_of(e, from) {
    Some(f) => @cmp.minimum(entry.width, f.fold(init=0.0, (a, b) => a + b))
    None => entry.width
  }
  Some((entry, gamma))
}

///|
/// MapLibre's `line-floorwidth` (the width at the integer zoom), or -1 and how
/// far to mix the per-vertex width slot (held within the current zoom's stops).
fn Map::floor_width(
  self : Map,
  index : Int32,
  layer : @style.StyleLayer,
  m : LayerMesh,
  zoom : Double,
) -> (Double, Double) {
  let floor_zoom = @cmp.maximum(0.0, zoom.floor())
  if m.vertex_paint is Some(_) {
    for vp in self.vertex_paint[index] {
      if vp.slot == @style.SLOT_SIZE {
        let (i, _) = vp.position(zoom)
        let (k, t) = vp.position(floor_zoom)
        let t = if vp.count() == 1 || k < i {
          0.0
        } else if k > i {
          1.0
        } else {
          t
        }
        return (-1.0, t)
      }
    }
  }
  let props = match m.props {
    Some(p) => p
    None => JsProps::none()
  }
  (number_or(layer.width.eval(floor_zoom, props), 1.0), 0.0)
}
