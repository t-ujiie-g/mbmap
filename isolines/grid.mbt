// Ports @turf/isolines and @turf/isobands 7.4.0 with their lib/grid-to-matrix
// and @turf/bbox (MIT License, Copyright (c) 2017 TurfJS). See NOTICE.

///|
using @core {type Trig}

///|
/// Most Point rows `isolines` and `isobands` take (AGENTS.md §8.2).
pub const MAX_GRID_POINTS : Int32 = 4_194_304

///|
/// Most breaks `isolines` and `isobands` take.
pub const MAX_BREAKS : Int32 = 4096

///|
/// Most grid cells times breaks one call walks.
pub const MAX_CELL_BREAKS : Int64 = 67_108_864

///|
/// Most marching-squares segments one call makes over all its breaks.
pub const MAX_SEGMENTS : Int32 = 4_000_000

///|
/// Largest magnitude of a grid value or a finite break: beyond it Turf's
/// interpolation can overflow into NaN coordinates.
pub const MAX_ABS_VALUE : Double = 1.0e300

///|
/// Turf's matrix of a point grid: `rows` rows of `cols` values from the lowest
/// latitude up (`flip: true`), and the grid's bounding box.
priv struct Grid {
  rows : Int32
  cols : Int32
  z : FixedArray[Double]
  min_x : Double
  min_y : Double
  max_x : Double
  max_y : Double
}

///|
fn Grid::at(self : Grid, y : Int32, x : Int32) -> Double {
  self.z[y * self.cols + x]
}

///|
/// A grid value as `gridToMatrix` reads it (falsy ones as 0); None for
/// non-numbers Turf keeps (true, a non-empty string) and past `MAX_ABS_VALUE`.
fn grid_value(p : @geom.Prop??) -> Double? {
  match p {
    None | Some(None) | Some(Some(Null | Bool(false) | Str(""))) => Some(0.0)
    Some(Some(Num(v))) =>
      if v.is_nan() || v == 0.0 {
        Some(0.0)
      } else if v.abs() <= MAX_ABS_VALUE {
        Some(v)
      } else {
        None
      }
    Some(Some(Bool(true) | Str(_))) => None
  }
}

///|
/// Turf's `gridToMatrix(grid, { zProperty, flip: true })` and `bbox(grid)`,
/// None where Turf throws or for non-finite coordinates.
fn grid_of(t : @geom.Table, z_property : String) -> Grid? {
  let n = t.length()
  if n > MAX_GRID_POINTS {
    return None
  }
  let column = t.column(z_property)
  let xs = FixedArray::make(n, 0.0)
  let ys = FixedArray::make(n, 0.0)
  let zs = FixedArray::make(n, 0.0)
  let mut min_x = @double.infinity
  let mut min_y = @double.infinity
  let mut max_x = @double.neg_infinity
  let mut max_y = @double.neg_infinity
  for f in 0..<n {
    guard t.kinds[f] is Point else { return None }
    let c = t.points(t.rings(t.parts(f).0).0).0
    let x = t.coords[c * 2]
    let y = t.coords[c * 2 + 1]
    if !x.is_finite() || !y.is_finite() {
      return None
    }
    xs[f] = x
    ys[f] = y
    let z = column.map(c => c.values[f])
    guard grid_value(z) is Some(v) else { return None }
    zs[f] = v
    if min_x > x {
      min_x = x
    }
    if min_y > y {
      min_y = y
    }
    if max_x < x {
      max_x = x
    }
    if max_y < y {
      max_y = y
    }
  }
  guard n > 0 else { return None }
  let order = lat_lng_order(xs, ys)
  let mut cols = 0
  while cols < n && ys[order[cols]] == ys[order[0]] {
    cols += 1
  }
  guard n % cols == 0 && n / cols >= 2 && cols >= 2 else { return None }
  let rows = n / cols
  let z = FixedArray::make(n, 0.0)
  for r in 0..<rows {
    let lat = ys[order[r * cols]]
    for c in 0..<cols {
      let i = order[r * cols + c]
      guard ys[i] == lat else { return None }
      z[r * cols + c] = zs[i]
    }
    if r * cols + cols < n && ys[order[r * cols + cols]] == lat {
      return None
    }
  }
  Some({ rows, cols, z, min_x, min_y, max_x, max_y, })
}

///|
/// Point indices by latitude, then longitude, then index (finite coordinates).
/// Grids in row or column order (Turf's `pointGrid`) are checked in one pass
/// instead of sorted; the order is total, so a sorted candidate is the sort.
fn lat_lng_order(
  xs : FixedArray[Double],
  ys : FixedArray[Double],
) -> FixedArray[Int32] {
  fn before(a : Int32, b : Int32) -> Bool {
    ys[a] < ys[b] ||
    (ys[a] == ys[b] && (xs[a] < xs[b] || (xs[a] == xs[b] && a < b)))
  }

  fn sorted(order : FixedArray[Int32]) -> Bool {
    for k in 1..<order.length() {
      if !before(order[k - 1], order[k]) {
        return false
      }
    }
    true
  }

  let n = xs.length()
  let order = FixedArray::makei(n, i => i)
  if sorted(order) {
    return order
  }
  let mut rows = 1
  while rows < n && xs[rows] == xs[0] {
    rows += 1
  }
  if n % rows == 0 {
    let cols = n / rows
    for r in 0..<rows {
      for c in 0..<cols {
        order[r * cols + c] = c * rows + r
      }
    }
    if sorted(order) {
      return order
    }
  }
  let all = Array::makei(n, i => i)
  all.sort_by((a, b) => if a == b { 0 } else if before(a, b) { -1 } else { 1 })
  FixedArray::makei(n, k => all[k])
}

///|
/// Whether `breaks` are within `MAX_BREAKS`, and finite ones within
/// `MAX_ABS_VALUE` (NaN and infinite breaks meet no cell, as in Turf).
fn breaks_ok(breaks : Array[Double]) -> Bool {
  breaks.length() <= MAX_BREAKS &&
  breaks.iter().all(b => b.is_inf() || !(b.abs() > MAX_ABS_VALUE))
}

///|
/// Turf's rescaling of matrix positions to the grid's bounding box.
fn Grid::scale(self : Grid) -> (Double, Double) {
  (
    (self.max_x - self.min_x) / (self.cols - 1).to_double(),
    (self.max_y - self.min_y) / (self.rows - 1).to_double(),
  )
}
