// Ported from d3-delaunay 6.0.6: ISC License, Copyright 2018-2021 Observable,
// Inc., 2021 Mapbox. See NOTICE.

///|
/// d3-delaunay's `Delaunay`: delaunator's triangulation with collinear input
/// jittered, an incoming half-edge per point, and placeholder triangles for
/// one or two distinct points (index -1 where a point is missing).
priv struct Delaunay {
  points : FixedArray[Double]
  triangles : FixedArray[Int32]
  halfedges : FixedArray[Int32]
  hull : FixedArray[Int32]
  inedges : FixedArray[Int32]
  hull_index : FixedArray[Int32]
}

///|
/// Whether every triangle has a null area, as d3-delaunay's `collinear`.
fn collinear(d : Delaunator) -> Bool {
  let t = d.triangles
  let c = d.coords
  for i = 0; i < t.length(); i = i + 3 {
    let a = 2 * t[i]
    let b = 2 * t[i + 1]
    let cc = 2 * t[i + 2]
    let cross = (c[cc] - c[a]) * (c[b + 1] - c[a + 1]) -
      (c[b] - c[a]) * (c[cc + 1] - c[a + 1])
    if cross > 1.0e-10 {
      return false
    }
  }
  true
}

///|
/// Triangulates `points` (x, y pairs, all finite; jittered in place when
/// collinear, as d3-delaunay does).
fn Delaunay::new(points : FixedArray[Double], trig : @core.Trig) -> Delaunay {
  let n = points.length() / 2
  let mut d = Delaunator::new(points)
  if d.hull.length() > 2 && collinear(d) {
    // The first and last points of a stable sort by x, then y.
    let mut e = 0
    let mut f = 0
    for i in 1..<n {
      if lex_less(points, i, e) {
        e = i
      }
      if !lex_less(points, i, f) {
        f = i
      }
    }
    let r = 1.0e-8 *
      @core.js_hypot(
        points[2 * f + 1] - points[2 * e + 1],
        points[2 * f] - points[2 * e],
      )
    for i in 0..<n {
      let x = points[2 * i]
      let y = points[2 * i + 1]
      points[2 * i] = x + trig.sin(x + y) * r
      points[2 * i + 1] = y + trig.cos(x - y) * r
    }
    d = Delaunator::new(points)
  }
  let mut halfedges = d.halfedges
  let hull = d.hull
  let mut triangles = d.triangles
  let inedges = FixedArray::make(n, -1)
  let hull_index = FixedArray::make(n, -1)
  for e in 0..<halfedges.length() {
    let p = triangles[if e % 3 == 2 { e - 2 } else { e + 1 }]
    if halfedges[e] == -1 || inedges[p] == -1 {
      inedges[p] = e
    }
  }
  for i, h in hull {
    hull_index[h] = i
  }
  if hull.length() <= 2 && hull.length() > 0 {
    triangles = FixedArray::make(3, -1)
    halfedges = FixedArray::make(3, -1)
    triangles[0] = hull[0]
    inedges[hull[0]] = 1
    if hull.length() == 2 {
      inedges[hull[1]] = 0
      triangles[1] = hull[1]
      triangles[2] = hull[1]
    }
  }
  { points, triangles, halfedges, hull, inedges, hull_index, }
}

///|
/// Whether point `i` sorts before point `j` by x, then y (`-0` equal to `0`).
fn lex_less(p : FixedArray[Double], i : Int32, j : Int32) -> Bool {
  let dx = p[2 * i] - p[2 * j]
  if dx != 0.0 {
    dx < 0.0
  } else {
    p[2 * i + 1] - p[2 * j + 1] < 0.0
  }
}

///|
/// Coordinate `k` of the points, NaN out of range as JavaScript's `undefined`
/// reads in arithmetic (the placeholder triangles' -1).
fn Delaunay::coord(self : Delaunay, k : Int32) -> Double {
  if k >= 0 && k < self.points.length() {
    self.points[k]
  } else {
    @double.not_a_number
  }
}

///|
/// d3-delaunay's `_step`: the point next to `i` nearest to `x, y`, or `i`.
fn Delaunay::step(self : Delaunay, i : Int32, x : Double, y : Double) -> Int32 {
  let n = self.points.length() >> 1
  if self.points.length() < 2 {
    return -1
  }
  if self.inedges[i] == -1 {
    return (i + 1) % n
  }
  let mut c = i
  let mut dc = sq(x - self.coord(i * 2)) + sq(y - self.coord(i * 2 + 1))
  let e0 = self.inedges[i]
  let mut e = e0
  for _ in 0..<=self.halfedges.length() {
    let t = self.triangles[e]
    let dt = sq(x - self.coord(t * 2)) + sq(y - self.coord(t * 2 + 1))
    if dt < dc {
      dc = dt
      c = t
    }
    e = if e % 3 == 2 { e - 2 } else { e + 1 }
    if self.triangles[e] != i {
      break
    }
    e = self.halfedges[e]
    if e == -1 {
      let h = self.hull.length()
      if h == 0 {
        break
      }
      let e = self.hull[(self.hull_index[i] + 1) % h]
      if e != t &&
        sq(x - self.coord(e * 2)) + sq(y - self.coord(e * 2 + 1)) < dc {
        return e
      }
      break
    }
    if e == e0 {
      break
    }
  }
  c
}

///|
/// `Math.pow(v, 2)`, which fdlibm's pow (V8's) computes as `v * v`.
fn sq(v : Double) -> Double {
  v * v
}

///|
/// d3-delaunay's `trianglePolygons` as x, y pairs per triangle (three points).
fn Delaunay::triangle_points(
  self : Delaunay,
  i : Int32,
) -> (Double, Double, Double, Double, Double, Double) {
  let t0 = self.triangles[i * 3] * 2
  let t1 = self.triangles[i * 3 + 1] * 2
  let t2 = self.triangles[i * 3 + 2] * 2
  (
    self.coord(t0),
    self.coord(t0 + 1),
    self.coord(t1),
    self.coord(t1 + 1),
    self.coord(t2),
    self.coord(t2 + 1),
  )
}
