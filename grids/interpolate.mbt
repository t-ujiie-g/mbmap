// Ports @turf/interpolate 7.4.0 with @turf/bbox and @turf/centroid (MIT
// License, Copyright (c) 2017 TurfJS) without the `mask` option. See NOTICE.

///|
/// The most grid rows times points `interpolate` weighs; past it the result is
/// `None`.
pub const MAX_INTERPOLATE_PAIRS : Int32 = 100_000_000

///|
/// Turf's `bbox` of the points: NaN coordinates never win a comparison, and
/// no points give infinities.
fn bbox(
  xs : Array[Double],
  ys : Array[Double],
) -> (Double, Double, Double, Double) {
  let mut x0 = @double.infinity
  let mut y0 = @double.infinity
  let mut x1 = @double.neg_infinity
  let mut y1 = @double.neg_infinity
  for i in 0..<xs.length() {
    if x0 > xs[i] {
      x0 = xs[i]
    }
    if y0 > ys[i] {
      y0 = ys[i]
    }
    if x1 < xs[i] {
      x1 = xs[i]
    }
    if y1 < ys[i] {
      y1 = ys[i]
    }
  }
  (x0, y0, x1, y1)
}

///|
/// Where row `f` is weighed: a point itself, else Turf's `centroid` (the mean
/// of the ring's points but the closing one, summed from 0 in order).
fn grid_point(t : @geom.Table, f : Int32) -> (Double, Double) {
  let (i0, i1) = t.points(t.rings(t.parts(f).0).0)
  if t.kinds[f] is Point {
    return (t.coords[i0 * 2], t.coords[i0 * 2 + 1])
  }
  let n = i1 - i0 - 1
  let mut sx = 0.0
  let mut sy = 0.0
  for i in i0..<(i0 + n) {
    sx += t.coords[i * 2]
    sy += t.coords[i * 2 + 1]
  }
  (sx / n.to_double(), sy / n.to_double())
}

///|
/// The number JavaScript arithmetic makes of a property: `null` is 0 and
/// booleans 0 or 1; `None` for a missing value (Turf throws) or a string
/// (which Turf coerces with `Number()` or concatenates).
fn z_value(p : @geom.Prop?) -> Double? {
  match p {
    Some(Num(v)) => Some(v)
    Some(Bool(v)) => Some(if v { 1.0 } else { 0.0 })
    Some(Null) => Some(0.0)
    Some(Str(_)) | None => None
  }
}

///|
/// Turf's `interpolate` (km; `grid` 0 point, 1 square, 2 hex, 3 triangle) of
/// the Point rows' `property`: grid rows carrying only `property`. None where
/// Turf throws (a value missing or a string) or past the caps.
pub fn interpolate(
  t : @geom.Table,
  cell_side : Double,
  grid : Int32,
  property : String,
  weight : Double,
  trig~ : Trig = Trig::moonbit(),
) -> @geom.Table? {
  let column = t.column(property)
  let xs = []
  let ys = []
  let zs = []
  for f in 0..<t.length() {
    guard t.kinds[f] is Point else { continue }
    let value = match column {
      Some(c) => c.values[f]
      None => None
    }
    guard z_value(value) is Some(z) else { return None }
    let i = t.points(t.rings(t.parts(f).0).0).0
    xs.push(t.coords[i * 2])
    ys.push(t.coords[i * 2 + 1])
    zs.push(z)
  }
  let (x0, y0, x1, y1) = bbox(xs, ys)
  let cells = match grid {
    0 => point_grid(x0, y0, x1, y1, cell_side, trig~)
    1 => square_grid(x0, y0, x1, y1, cell_side, trig~)
    2 => hex_grid(x0, y0, x1, y1, cell_side, trig~)
    3 => triangle_grid(x0, y0, x1, y1, cell_side, trig~)
    _ => None
  }
  guard cells is Some(cells) else { return None }
  guard cells.length().to_int64() * xs.length().to_int64() <=
    MAX_INTERPOLATE_PAIRS.to_int64() else {
    return None
  }
  let b = @geom.TableBuilder::new()
  for f in 0..<cells.length() {
    let (gx, gy) = grid_point(cells, f)
    let mut zw = 0.0
    let mut sw = 0.0
    for i in 0..<xs.length() {
      let d = distance(trig, gx, gy, xs[i], ys[i])
      if d == 0.0 {
        zw = zs[i]
      }
      let w = 1.0 / trig.pow(d, weight)
      sw += w
      zw += w * zs[i]
    }
    let (i0, i1) = cells.points(cells.rings(cells.parts(f).0).0)
    for i in i0..<i1 {
      b.point(cells.coords[i * 2], cells.coords[i * 2 + 1])
    }
    b.end_ring()
    b.end_part()
    b.prop(property, Num(zw / sw))
    b.end_feature(cells.kinds[f])
  }
  Some(b.finish())
}
