// Geotransforms and the angle helpers of GDAL 3.13.3's alg/viewshed/util.cpp
// (MIT License, (c) 2024 info@hobu.co) and gcore's GDALInvGeoTransform. See NOTICE.

///|
const PI : Double = 3.141592653589793

///|
/// GDAL's `INVALID_ISECT`: no intersection.
const INVALID_ISECT : Int32 = 2147483647

///|
const INT_MIN : Int32 = -2147483648

///|
/// C++'s `static_cast<int>` of a double as x86-64 does it (`cvttsd2si`): NaN
/// and values out of range give `INT_MIN`.
fn cint(x : Double) -> Int32 {
  if x > -2147483649.0 && x < 2147483648.0 {
    x.to_int()
  } else {
    INT_MIN
  }
}

///|
/// C's `round`: halves away from zero.
fn c_round(x : Double) -> Double {
  let t = x.trunc()
  let d = x - t
  if d >= 0.5 {
    t + 1.0
  } else if d <= -0.5 {
    t - 1.0
  } else {
    t
  }
}

///|
/// `std::clamp(v, lo, hi)`.
fn clamp_int(v : Int32, lo : Int32, hi : Int32) -> Int32 {
  if v < lo {
    lo
  } else if hi < v {
    hi
  } else {
    v
  }
}

///|
/// GDAL's `ARE_REAL_EQUAL` (two ulps).
fn are_real_equal(a : Double, b : Double) -> Bool {
  a == b || (a - b).abs() < 2.220446049250313e-16 * (a + b).abs() * 2.0
}

///|
/// GDALInvGeoTransform: None when the transform cannot be inverted.
fn invert_geotransform(gt : FixedArray[Double]) -> FixedArray[Double]? {
  if gt[2] == 0.0 && gt[4] == 0.0 && gt[1] != 0.0 && gt[5] != 0.0 {
    return Some([
      -gt[0] / gt[1],
      1.0 / gt[1],
      0.0,
      -gt[3] / gt[5],
      0.0,
      1.0 / gt[5],
    ])
  }
  let det = gt[1] * gt[5] - gt[2] * gt[4]
  let a = gt[1].abs()
  let b = gt[2].abs()
  let c = gt[4].abs()
  let d = gt[5].abs()
  let m1 = if a < b { b } else { a }
  let m2 = if c < d { d } else { c }
  let magnitude = if m1 < m2 { m2 } else { m1 }
  if det.abs() <= 1.0e-10 * magnitude * magnitude {
    return None
  }
  let inv_det = 1.0 / det
  Some([
    (gt[2] * gt[3] - gt[0] * gt[5]) * inv_det,
    gt[5] * inv_det,
    -gt[2] * inv_det,
    (-gt[1] * gt[3] + gt[0] * gt[4]) * inv_det,
    -gt[4] * inv_det,
    gt[1] * inv_det,
  ])
}

///|
/// `normalizeAngle`: clockwise degrees from north to counterclockwise radians
/// from east.
fn normalize_angle(degrees : Double) -> Double {
  let mut a = 90.0 - degrees
  if a < 0.0 {
    a += 360.0
  }
  a * (PI / 180.0)
}

///|
/// `horizontalIntersect`: X where the ray from (nx, ny) along `angle` meets
/// row `y`, or NaN.
fn horizontal_intersect(
  trig : @core.Trig,
  angle : Double,
  nx : Int32,
  ny : Int32,
  y : Int32,
) -> Double {
  if ny == y {
    nx.to_double()
  } else if ny > y {
    if are_real_equal(angle, PI / 2.0) {
      nx.to_double()
    } else if angle > 0.0 && angle < PI {
      nx.to_double() + (ny - y).to_double() / (trig.tan)(angle)
    } else {
      @double.not_a_number
    }
  } else if are_real_equal(angle, 3.0 * PI / 2.0) {
    nx.to_double()
  } else if angle > PI {
    nx.to_double() - (y - ny).to_double() / (trig.tan)(angle)
  } else {
    @double.not_a_number
  }
}

///|
/// `hIntersect` on a row: the rounded X, or `INVALID_ISECT`.
fn h_intersect_row(
  trig : @core.Trig,
  angle : Double,
  nx : Int32,
  ny : Int32,
  y : Int32,
) -> Int32 {
  let x = horizontal_intersect(trig, angle, nx, ny, y)
  if x.is_nan() {
    INVALID_ISECT
  } else {
    cint(c_round(x))
  }
}

///|
/// `hIntersect` on a window: X on its top or bottom edge, clamped to it.
fn h_intersect_window(
  trig : @core.Trig,
  angle : Double,
  nx : Int32,
  ny : Int32,
  win : Window,
) -> Int32 {
  if are_real_equal(angle, PI) {
    return win.x_start
  }
  if are_real_equal(angle, 0.0) {
    return win.x_stop
  }
  let mut x = horizontal_intersect(trig, angle, nx, ny, win.y_start)
  if x.is_nan() {
    x = horizontal_intersect(trig, angle, nx, ny, win.y_stop)
  }
  clamp_int(cint(c_round(x)), win.x_start, win.x_stop)
}

///|
/// `verticalIntersect`: Y where the ray from (nx, ny) along `angle` meets
/// column `x`, or NaN.
fn vertical_intersect(
  trig : @core.Trig,
  angle : Double,
  nx : Int32,
  ny : Int32,
  x : Int32,
) -> Double {
  if nx == x {
    ny.to_double()
  } else if nx < x {
    if are_real_equal(angle, 0.0) {
      ny.to_double()
    } else if angle < PI / 2.0 || angle > PI * 3.0 / 2.0 {
      ny.to_double() + (nx - x).to_double() * (trig.tan)(angle)
    } else {
      @double.not_a_number
    }
  } else if are_real_equal(angle, PI) {
    ny.to_double()
  } else if angle > PI / 2.0 && angle < PI * 3.0 / 2.0 {
    ny.to_double() - (x - nx).to_double() * (trig.tan)(angle)
  } else {
    @double.not_a_number
  }
}

///|
/// `vIntersect` on a window: Y on its left or right edge, clamped to it.
fn v_intersect_window(
  trig : @core.Trig,
  angle : Double,
  nx : Int32,
  ny : Int32,
  win : Window,
) -> Int32 {
  if are_real_equal(angle, PI / 2.0) {
    return win.y_start
  }
  if are_real_equal(angle, 3.0 * PI / 2.0) {
    return win.y_stop
  }
  let mut y = vertical_intersect(trig, angle, nx, ny, win.x_start)
  if y.is_nan() {
    y = vertical_intersect(trig, angle, nx, ny, win.x_stop)
  }
  clamp_int(cint(c_round(y)), win.y_start, win.y_stop)
}

///|
/// `rayBetween`: whether `test` lies clockwise from `start` to `end`.
fn ray_between(start : Double, end : Double, angle : Double) -> Bool {
  let s = end
  let e = start
  if s < e {
    angle >= s && angle <= e
  } else if s > e {
    angle >= s || angle <= e
  } else {
    false
  }
}

///|
/// A window of cells [x_start, x_stop) x [y_start, y_stop).
priv struct Window {
  mut x_start : Int32
  mut x_stop : Int32
  mut y_start : Int32
  mut y_stop : Int32
}

///|
/// `shrinkWindowForAngles`: the part of `win` the slice between the two angles
/// from (nx, ny) can reach.
fn shrink_window_for_angles(
  trig : @core.Trig,
  win : Window,
  nx : Int32,
  ny : Int32,
  start : Double,
  end : Double,
) -> Unit {
  if start == end {
    return
  }
  let w = { ..win, }
  let start_x = h_intersect_window(trig, start, nx, ny, w)
  let stop_x = h_intersect_window(trig, end, nx, ny, w)
  if !ray_between(start, end, 0.0) {
    let xmax = max_int(max_int(nx, start_x), stop_x)
    win.x_stop = min_int(win.x_stop, xmax + 1)
  }
  if !ray_between(start, end, PI) {
    let xmin = min_int(min_int(nx, start_x), stop_x)
    win.x_start = max_int(win.x_start, xmin)
  }
  let start_y = v_intersect_window(trig, start, nx, ny, w)
  let stop_y = v_intersect_window(trig, end, nx, ny, w)
  if !ray_between(start, end, PI / 2.0) {
    let ymin = min_int(min_int(ny, start_y), stop_y)
    win.y_start = max_int(win.y_start, ymin)
  }
  if !ray_between(start, end, 3.0 * PI / 2.0) {
    let ymax = max_int(max_int(ny, start_y), stop_y)
    win.y_stop = min_int(win.y_stop, ymax + 1)
  }
}

///|
fn max_int(a : Int32, b : Int32) -> Int32 {
  if a < b {
    b
  } else {
    a
  }
}

///|
fn min_int(a : Int32, b : Int32) -> Int32 {
  if b < a {
    b
  } else {
    a
  }
}
