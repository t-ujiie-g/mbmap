// Ports d3-contour 4.0.3's contours.js, area.js and contains.js (ISC License,
// Copyright 2012-2026 Mike Bostock). See NOTICE.

///|
/// Most grid cells `contours` and `contour_density` walk (AGENTS.md §8.2).
pub const MAX_CONTOUR_CELLS : Int64 = 16_777_216

///|
/// Most thresholds `contours` and `contour_density` take.
pub const MAX_THRESHOLDS : Int32 = 4096

///|
/// Most grid cells times thresholds one call walks.
pub const MAX_CONTOUR_WORK : Int64 = 134_217_728

///|
/// Most marching-squares segments one call stitches over all its thresholds.
pub const MAX_CONTOUR_SEGMENTS : Int64 = 4_000_000

///|
/// Most hole-in-polygon edge tests one call spends (d3's nesting is quadratic
/// in rings).
pub const MAX_CONTOUR_NESTING_TESTS : Int64 = 100_000_000

///|
/// The segments and nesting tests a call has spent so far, and the most it may.
priv struct Budget {
  mut segments : Int64
  mut tests : Int64
  max_segments : Int64
  max_tests : Int64
}

///|
fn Budget::new(
  max_segments~ : Int64 = MAX_CONTOUR_SEGMENTS,
  max_tests~ : Int64 = MAX_CONTOUR_NESTING_TESTS,
) -> Budget {
  { segments: 0L, tests: 0L, max_segments, max_tests, }
}

///|
/// One of d3's contours: its threshold `value` and the MultiPolygon's
/// `coordinates` (polygons of rings of x, y points, each ring closed by its
/// first point repeated).
pub struct Contour {
  value : Double
  coordinates : Array[Array[Array[(Double, Double)]]]
}

///|
/// d3-contour's marching-squares cases: the segments of each cell state, in
/// half units.
let cases : FixedArray[FixedArray[Double]] = [
  [],
  [1.0, 1.5, 0.5, 1.0],
  [1.5, 1.0, 1.0, 1.5],
  [1.5, 1.0, 0.5, 1.0],
  [1.0, 0.5, 1.5, 1.0],
  [1.0, 1.5, 0.5, 1.0, 1.0, 0.5, 1.5, 1.0],
  [1.0, 0.5, 1.0, 1.5],
  [1.0, 0.5, 0.5, 1.0],
  [0.5, 1.0, 1.0, 0.5],
  [1.0, 1.5, 1.0, 0.5],
  [0.5, 1.0, 1.0, 0.5, 1.5, 1.0, 1.0, 1.5],
  [1.5, 1.0, 1.0, 0.5],
  [0.5, 1.0, 1.5, 1.0],
  [1.0, 1.5, 1.5, 1.0],
  [0.5, 1.0, 1.0, 1.5],
  [],
]

///|
/// A ring under construction: `front` holds prepended points in reverse.
priv struct Ring {
  front : Array[(Double, Double)]
  back : Array[(Double, Double)]
}

///|
fn Ring::length(self : Ring) -> Int32 {
  self.front.length() + self.back.length()
}

///|
fn Ring::to_array(self : Ring) -> Array[(Double, Double)] {
  let out = Array(capacity=self.length())
  for i = self.front.length() - 1; i >= 0; i = i - 1 {
    out.push(self.front[i])
  }
  for p in self.back {
    out.push(p)
  }
  out
}

///|
/// `a.concat(b)`, reusing whichever ring is cheaper to extend: d3 drops both
/// fragments afterwards.
fn concat(a : Ring, b : Ring) -> Ring {
  if a.length() <= b.length() {
    for i = a.back.length() - 1; i >= 0; i = i - 1 {
      b.front.push(a.back[i])
    }
    for p in a.front {
      b.front.push(p)
    }
    b
  } else {
    for i = b.front.length() - 1; i >= 0; i = i - 1 {
      a.back.push(b.front[i])
    }
    for p in b.back {
      a.back.push(p)
    }
    a
  }
}

///|
priv struct Fragment {
  mut start : Int64
  mut end : Int64
  ring : Ring
}

///|
/// `values[i]` as d3 reads it: NaN (invalid, as `undefined`) outside the array.
fn read(values : FixedArray[Double], i : Int32) -> Double {
  if i >= 0 && i < values.length() {
    values[i]
  } else {
    @double.not_a_number
  }
}

///|
/// d3's `above`: whether a value is at least `value` (invalid ones never are).
fn above(values : FixedArray[Double], i : Int32, value : Double) -> Int32 {
  if read(values, i) >= value {
    1
  } else {
    0
  }
}

///|
/// d3's `isorings`: marching squares stitched into rings, each passed to
/// `callback` once closed; false once `budget` runs out of segments.
fn isorings(
  values : FixedArray[Double],
  dx : Int32,
  dy : Int32,
  value : Double,
  budget : Budget,
  callback : (Array[(Double, Double)]) -> Unit,
) -> Bool {
  let by_start : Map[Int64, Fragment] = Map([])
  let by_end : Map[Int64, Fragment] = Map([])
  let mut x = -1
  let mut y = -1
  fn index(px : Double, py : Double) -> Int64 {
    (px * 2.0 + py * (dx + 1).to_double() * 4.0).to_int64()
  }

  fn stitch(c : Int32) {
    let line = cases[c]
    budget.segments += (line.length() / 4).to_int64()
    for l = 0; l < line.length(); l = l + 4 {
      let start = (line[l] + x.to_double(), line[l + 1] + y.to_double())
      let end = (line[l + 2] + x.to_double(), line[l + 3] + y.to_double())
      let start_index = index(start.0, start.1)
      let end_index = index(end.0, end.1)
      if by_end.get(start_index) is Some(f) {
        if by_start.get(end_index) is Some(g) {
          by_end.remove(f.end)
          by_start.remove(g.start)
          if physical_equal(f, g) {
            f.ring.back.push(end)
            callback(f.ring.to_array())
          } else {
            let joined = {
              start: f.start,
              end: g.end,
              ring: concat(f.ring, g.ring),
            }
            by_start[f.start] = joined
            by_end[g.end] = joined
          }
        } else {
          by_end.remove(f.end)
          f.ring.back.push(end)
          f.end = end_index
          by_end[end_index] = f
        }
      } else if by_start.get(end_index) is Some(f) {
        if by_end.get(start_index) is Some(g) {
          by_start.remove(f.start)
          by_end.remove(g.end)
          if physical_equal(f, g) {
            f.ring.back.push(end)
            callback(f.ring.to_array())
          } else {
            let joined = {
              start: g.start,
              end: f.end,
              ring: concat(g.ring, f.ring),
            }
            by_start[g.start] = joined
            by_end[f.end] = joined
          }
        } else {
          by_start.remove(f.start)
          f.ring.front.push(start)
          f.start = start_index
          by_start[start_index] = f
        }
      } else {
        let f = {
          start: start_index,
          end: end_index,
          ring: { front: [], back: [start, end], },
        }
        by_start[start_index] = f
        by_end[end_index] = f
      }
    }
  }

  // The first row (y = -1, t2 = t3 = 0).
  let mut t1 = above(values, 0, value)
  stitch(t1 << 1)
  x += 1
  while x < dx - 1 {
    let t0 = t1
    t1 = above(values, x + 1, value)
    stitch(t0 | (t1 << 1))
    x += 1
  }
  stitch(t1)
  y += 1
  while y < dy - 1 {
    if budget.segments > budget.max_segments {
      return false
    }
    x = -1
    t1 = above(values, y * dx + dx, value)
    let mut t2 = above(values, y * dx, value)
    stitch((t1 << 1) | (t2 << 2))
    x += 1
    while x < dx - 1 {
      let t0 = t1
      t1 = above(values, y * dx + dx + x + 1, value)
      let t3 = t2
      t2 = above(values, y * dx + x + 1, value)
      stitch(t0 | (t1 << 1) | (t2 << 2) | (t3 << 3))
      x += 1
    }
    stitch(t1 | (t2 << 3))
    y += 1
  }
  // The last row (y = dy - 1, t0 = t1 = 0).
  x = -1
  let mut t2 = above(values, y * dx, value)
  stitch(t2 << 2)
  x += 1
  while x < dx - 1 {
    let t3 = t2
    t2 = above(values, y * dx + x + 1, value)
    stitch((t2 << 2) | (t3 << 3))
    x += 1
  }
  stitch(t2 << 3)
  budget.segments <= budget.max_segments
}

///|
/// d3's `valid`: an invalid value as negative infinity, for smoothing.
fn valid(values : FixedArray[Double], i : Int32) -> Double {
  let v = read(values, i)
  if v.is_nan() {
    @double.neg_infinity
  } else {
    v
  }
}

///|
/// JavaScript's `Math.sign`.
fn sign(x : Double) -> Double {
  if x > 0.0 {
    1.0
  } else if x < 0.0 {
    -1.0
  } else {
    x
  }
}

///|
/// d3's `smooth1`: where between two samples the threshold lies.
fn smooth1(x : Double, v0 : Double, v1 : Double, value : Double) -> Double {
  let a = value - v0
  let b = v1 - v0
  let d = if a.is_finite() || b.is_finite() { a / b } else { sign(a) / sign(b) }
  if d.is_nan() {
    x
  } else {
    x + d - 0.5
  }
}

///|
/// d3's `smoothLinear`: ring points moved along their cell edge by linear
/// interpolation.
fn smooth_ring(
  ring : Array[(Double, Double)],
  values : FixedArray[Double],
  dx : Int32,
  dy : Int32,
  value : Double,
) -> Unit {
  for i, p in ring {
    let (x, y) = p
    let xt = x.to_int()
    let yt = y.to_int()
    let v1 = valid(values, yt * dx + xt)
    let mut nx = x
    let mut ny = y
    if x > 0.0 && x < dx.to_double() && xt.to_double() == x {
      nx = smooth1(x, valid(values, yt * dx + xt - 1), v1, value)
    }
    if y > 0.0 && y < dy.to_double() && yt.to_double() == y {
      ny = smooth1(y, valid(values, (yt - 1) * dx + xt), v1, value)
    }
    ring[i] = (nx, ny)
  }
}

///|
/// d3's `area`: twice the signed area, positive for exterior rings.
fn area(ring : Array[(Double, Double)]) -> Double {
  let n = ring.length()
  let mut a = ring[n - 1].1 * ring[0].0 - ring[n - 1].0 * ring[0].1
  for i in 1..<n {
    a += ring[i - 1].1 * ring[i].0 - ring[i - 1].0 * ring[i].1
  }
  a
}

///|
/// d3's `contains`: the first non-zero `ringContains` of the hole's points.
fn contains(
  ring : Array[(Double, Double)],
  hole : Array[(Double, Double)],
  budget : Budget,
) -> Int32 {
  for p in hole {
    budget.tests += ring.length().to_int64()
    let c = ring_contains(ring, p)
    if c != 0 {
      return c
    }
  }
  0
}

///|
/// d3's `ringContains`: 1 inside, -1 outside, 0 on an edge.
fn ring_contains(
  ring : Array[(Double, Double)],
  point : (Double, Double),
) -> Int32 {
  let (x, y) = point
  let mut inside = -1
  let n = ring.length()
  let mut j = n - 1
  for i in 0..<n {
    let (xi, yi) = ring[i]
    let (xj, yj) = ring[j]
    if segment_contains(ring[i], ring[j], point) {
      return 0
    }
    if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi {
      inside = -inside
    }
    j = i
  }
  inside
}

///|
/// d3's `segmentContains`: whether `c` lies on segment `a`-`b`.
fn segment_contains(
  a : (Double, Double),
  b : (Double, Double),
  c : (Double, Double),
) -> Bool {
  let collinear = (b.0 - a.0) * (c.1 - a.1) == (c.0 - a.0) * (b.1 - a.1)
  if !collinear {
    return false
  }
  let (p, q, r) = if a.0 == b.0 { (a.1, c.1, b.1) } else { (a.0, c.0, b.0) }
  (p <= q && q <= r) || (r <= q && q <= p)
}

///|
/// d3's `contour(values, value)`: exterior rings (positive area) as polygons,
/// each other ring a hole of the first polygon not reporting it outside. None
/// once `budget` runs out.
fn contour(
  values : FixedArray[Double],
  dx : Int32,
  dy : Int32,
  value : Double,
  smooth : Bool,
  budget : Budget,
) -> Array[Array[Array[(Double, Double)]]]? {
  let polygons : Array[Array[Array[(Double, Double)]]] = []
  let holes = []
  let complete = isorings(values, dx, dy, value, budget, ring => {
    if smooth {
      smooth_ring(ring, values, dx, dy, value)
    }
    if area(ring) > 0.0 {
      polygons.push([ring])
    } else {
      holes.push(ring)
    }
  })
  guard complete else { return None }
  for hole in holes {
    for polygon in polygons {
      let inside = contains(polygon[0], hole, budget) != -1
      if budget.tests > budget.max_tests {
        return None
      }
      if inside {
        polygon.push(hole)
        break
      }
    }
  }
  Some(polygons)
}

///|
/// `contour` at each of `levels`, or None once one gives None.
fn contour_levels(
  values : FixedArray[Double],
  dx : Int32,
  dy : Int32,
  levels : Array[Double],
  smooth : Bool,
  budget~ : Budget = Budget::new(),
) -> Array[Array[Array[Array[(Double, Double)]]]]? {
  let out = Array(capacity=levels.length())
  for level in levels {
    guard contour(values, dx, dy, level, smooth, budget) is Some(c) else {
      return None
    }
    out.push(c)
  }
  Some(out)
}

///|
/// `thresholds` sorted ascending as d3's `slice().sort(ascending)` does
/// (stable, -0 and 0 equal); None if one is NaN, where d3 throws.
fn sorted(thresholds : Array[Double]) -> Array[Double]? {
  if thresholds.iter().any(t => t.is_nan()) {
    return None
  }
  let order = Array::makei(thresholds.length(), i => i)
  order.sort_by((a, b) => {
    if thresholds[a] < thresholds[b] {
      -1
    } else if thresholds[a] > thresholds[b] {
      1
    } else {
      a - b
    }
  })
  Some(order.map(i => thresholds[i]))
}

///|
/// Whether a `width` x `height` grid may be walked once per threshold.
fn work_ok(width : Int32, height : Int32, thresholds : Int32) -> Bool {
  let cells = width.to_int64() * height.to_int64()
  width >= 0 &&
  height >= 0 &&
  cells <= MAX_CONTOUR_CELLS &&
  thresholds <= MAX_THRESHOLDS &&
  cells * thresholds.to_int64() <= MAX_CONTOUR_WORK
}

///|
/// d3-contour's `contours().size([width, height]).smooth(smooth)
/// .thresholds(thresholds)(values)`, ascending, over `values` row by row (NaN
/// below every threshold). None where d3 throws and past the `MAX_CONTOUR_*` caps.
pub fn contours(
  values : FixedArray[Double],
  width : Int32,
  height : Int32,
  thresholds : Array[Double],
  smooth : Bool,
) -> Array[Contour]? {
  guard work_ok(width, height, thresholds.length()) &&
    sorted(thresholds) is Some(tz) else {
    return None
  }
  guard contour_levels(values, width, height, tz, smooth) is Some(cs) else {
    return None
  }
  Some(tz.mapi((i, value) => { value, coordinates: cs[i], }))
}
