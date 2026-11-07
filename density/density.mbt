// Ports d3-contour 4.0.3's density.js (ISC License, Copyright 2012-2026 Mike
// Bostock). See NOTICE.

///|
/// JavaScript's `Math.LN2`.
const LN2 : Double = 0.6931471805599453

///|
/// `2^e` for an integer `e` within ±64, exactly (as `Math.pow(2, e)`).
fn pow2(e : Int32) -> Double {
  let mut p = 1.0
  let f = if e < 0 { 0.5 } else { 2.0 }
  for _ in 0..<e.abs() {
    p *= f
  }
  p
}

///|
/// d3-contour's `contourDensity().x(..).y(..).weight(..).size([width, height])
/// .cellSize(cell_size).bandwidth(bandwidth).thresholds(thresholds)(data)`
/// over points `xs`, `ys` with `weights` (1 each without): the points are
/// splatted into a Float32 grid of cells `cell_size` wide (rounded down to a
/// power of two, padded by three blur radii), blurred, and contoured at
/// d3-array's `ticks` of `thresholds` uniform values from `Number.MIN_VALUE` to
/// the densest cell; coordinates in the points' units, `value` in points (or
/// weight) per square unit. Points with a NaN coordinate or a zero or NaN
/// weight count for nothing, as in d3. None where d3 throws (a negative size or
/// bandwidth, a cell size under 1) and for `xs`, `ys` and `weights` of unequal
/// lengths, more than `MAX_THRESHOLDS` thresholds, a padded grid past
/// `MAX_CONTOUR_CELLS` or `MAX_CONTOUR_WORK`, or past `MAX_TICKS`.
pub fn contour_density(
  xs : FixedArray[Double],
  ys : FixedArray[Double],
  weights : FixedArray[Double]?,
  width : Int32,
  height : Int32,
  cell_size : Int32,
  bandwidth : Double,
  thresholds : Int32,
  trig~ : Trig = Trig::moonbit(),
) -> Array[Contour]? {
  let count = xs.length()
  guard ys.length() == count &&
    weights.map_or(true, w => w.length() == count) &&
    width >= 0 &&
    height >= 0 &&
    cell_size >= 1 &&
    bandwidth >= 0.0 &&
    thresholds <= MAX_THRESHOLDS else {
    return None
  }
  let k = (trig.ln(cell_size.to_double()) / LN2).floor().to_int()
  let r = ((4.0 * bandwidth * bandwidth + 1.0).sqrt() - 1.0) / 2.0
  let o = r * 3.0
  let padded_x = width.to_double() + o * 2.0
  let padded_y = height.to_double() + o * 2.0
  guard padded_x < 2147483648.0 && padded_y < 2147483648.0 else { return None }
  let n = padded_x.to_int() >> k
  let m = padded_y.to_int() >> k
  guard work_ok(n, m, 1) else { return None }
  // d3's `grid`.
  let values = FixedArray::make(n * m, Float::from_double(0.0))
  let pow2k = pow2(-k)
  fn add(i : Double, v : Double) {
    if i >= 0.0 && i < (n * m).to_double() {
      let j = i.to_int()
      values[j] = Float::from_double(values[j].to_double() + v)
    }
  }

  for i in 0..<count {
    let xi = (xs[i] + o) * pow2k
    let yi = (ys[i] + o) * pow2k
    let wi = match weights {
      Some(w) => w[i]
      None => 1.0
    }
    if wi != 0.0 &&
      !wi.is_nan() &&
      xi >= 0.0 &&
      xi < n.to_double() &&
      yi >= 0.0 &&
      yi < m.to_double() {
      let x0 = xi.floor()
      let y0 = yi.floor()
      let xt = xi - x0 - 0.5
      let yt = yi - y0 - 0.5
      let nd = n.to_double()
      add(x0 + y0 * nd, (1.0 - xt) * (1.0 - yt) * wi)
      add(x0 + 1.0 + y0 * nd, xt * (1.0 - yt) * wi)
      add(x0 + 1.0 + (y0 + 1.0) * nd, xt * yt * wi)
      add(x0 + (y0 + 1.0) * nd, (1.0 - xt) * yt * wi)
    }
  }
  blur2(values, n, m, r * pow2k)
  let pow4k = pow2(2 * k)
  guard ticks(5.0e-324, max_of(values) / pow4k, thresholds.to_double(), trig)
    is Some(tz) else {
    return None
  }
  guard work_ok(n, m, tz.length()) &&
    sorted(tz.map(d => d * pow4k)) is Some(levels) else {
    return None
  }
  let grid = FixedArray::makei(n * m, i => values[i].to_double())
  let scale = pow2(k)
  Some(
    levels.mapi((i, level) => {
      let coordinates = contour(grid, n, m, level, true)
      for polygon in coordinates {
        for ring in polygon {
          for j, p in ring {
            ring[j] = (p.0 * scale - o, p.1 * scale - o)
          }
        }
      }
      { value: tz[i], coordinates, }
    }),
  )
}
