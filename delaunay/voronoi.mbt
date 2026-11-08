// Ported from d3-delaunay 6.0.6: ISC License, Copyright 2018-2021 Observable,
// Inc., 2021 Mapbox. See NOTICE.

///|
/// d3-delaunay's `Voronoi` of a `Delaunay` within finite bounds.
priv struct Voronoi {
  delaunay : Delaunay
  circumcenters : FixedArray[Double]
  vectors : FixedArray[Double]
  xmin : Double
  ymin : Double
  xmax : Double
  ymax : Double
}

///|
fn js_sign(v : Double) -> Double {
  if v > 0.0 {
    1.0
  } else if v < 0.0 {
    -1.0
  } else {
    v
  }
}

///|
/// Whether `v` is truthy in JavaScript (neither 0 nor NaN).
fn truthy(v : Double) -> Bool {
  v != 0.0 && !v.is_nan()
}

///|
fn Voronoi::new(
  delaunay : Delaunay,
  xmin : Double,
  ymin : Double,
  xmax : Double,
  ymax : Double,
) -> Voronoi {
  let points = delaunay.points
  let hull = delaunay.hull
  let triangles = delaunay.triangles
  let circumcenters = FixedArray::make(triangles.length() / 3 * 2, 0.0)
  let mut bx = @double.not_a_number
  let mut by = @double.not_a_number
  let mut barycenter = false
  for i = 0, j = 0; i < triangles.length(); i = i + 3, j = j + 2 {
    let t1 = triangles[i] * 2
    let t2 = triangles[i + 1] * 2
    let t3 = triangles[i + 2] * 2
    let x1 = delaunay.coord(t1)
    let y1 = delaunay.coord(t1 + 1)
    let x2 = delaunay.coord(t2)
    let y2 = delaunay.coord(t2 + 1)
    let x3 = delaunay.coord(t3)
    let y3 = delaunay.coord(t3 + 1)
    let dx = x2 - x1
    let dy = y2 - y1
    let ex = x3 - x1
    let ey = y3 - y1
    let ab = (dx * ey - dy * ex) * 2.0
    let (x, y) = if ab.abs() < 1.0e-9 {
      // A degenerate triangle's circumcenter is at infinity, orthogonal to
      // the half-edge and away from the hull's barycenter.
      if !barycenter {
        barycenter = true
        bx = 0.0
        by = 0.0
        for h in hull {
          bx += points[h * 2]
          by += points[h * 2 + 1]
        }
        bx /= hull.length().to_double()
        by /= hull.length().to_double()
      }
      let a = 1.0e9 * js_sign((bx - x1) * ey - (by - y1) * ex)
      ((x1 + x3) / 2.0 - a * ey, (y1 + y3) / 2.0 + a * ex)
    } else {
      let d = 1.0 / ab
      let bl = dx * dx + dy * dy
      let cl = ex * ex + ey * ey
      (x1 + (ey * bl - dy * cl) * d, y1 + (dx * cl - ex * bl) * d)
    }
    circumcenters[j] = x
    circumcenters[j + 1] = y
  }
  let vectors = FixedArray::make(points.length() / 2 * 4, 0.0)
  if hull.length() > 0 {
    let mut h = hull[hull.length() - 1]
    let mut p1 = h * 4
    let mut x1 = points[2 * h]
    let mut y1 = points[2 * h + 1]
    for i in 0..<hull.length() {
      h = hull[i]
      let p0 = p1
      let x0 = x1
      let y0 = y1
      p1 = h * 4
      x1 = points[2 * h]
      y1 = points[2 * h + 1]
      vectors[p0 + 2] = y0 - y1
      vectors[p1] = y0 - y1
      vectors[p0 + 3] = x1 - x0
      vectors[p1 + 1] = x1 - x0
    }
  }
  { delaunay, circumcenters, vectors, xmin, ymin, xmax, ymax, }
}

///|
/// d3-delaunay's `cellPolygon(i)` as x, y pairs, the first repeated last, or
/// None where it returns null.
fn Voronoi::cell_polygon(self : Voronoi, i : Int32) -> Array[Double]? {
  guard self.clip(i) is Some(points) && points.length() > 0 else { None }
  let mut n = points.length()
  while n > 1 && points[0] == points[n - 2] && points[1] == points[n - 1] {
    n -= 2
  }
  // In place: `clip` gives a new array.
  let mut w = 2
  let mut px = points[0]
  let mut py = points[1]
  for k = 2; k < n; k = k + 2 {
    let x = points[k]
    let y = points[k + 1]
    if x != px || y != py {
      points[w] = x
      points[w + 1] = y
      w += 2
    }
    px = x
    py = y
  }
  points.truncate(w)
  points.push(points[0])
  points.push(points[1])
  Some(points)
}

///|
fn Voronoi::box(self : Voronoi) -> Array[Double] {
  [
    self.xmax,
    self.ymin,
    self.xmax,
    self.ymax,
    self.xmin,
    self.ymax,
    self.xmin,
    self.ymin,
  ]
}

///|
fn Voronoi::contains(self : Voronoi, i : Int32, x : Double, y : Double) -> Bool {
  if x.is_nan() || y.is_nan() {
    return false
  }
  self.delaunay.step(i, x, y) == i
}

///|
/// The circumcenters around point `i` (d3-delaunay's `_cell`), or None for a
/// coincident point.
fn Voronoi::cell(self : Voronoi, i : Int32) -> Array[Double]? {
  let d = self.delaunay
  let e0 = d.inedges[i]
  if e0 == -1 {
    return None
  }
  let points = Array(capacity=16)
  let mut e = e0
  for _ in 0..<=d.halfedges.length() {
    let t = e / 3
    points.push(self.circumcenters[t * 2])
    points.push(self.circumcenters[t * 2 + 1])
    e = if e % 3 == 2 { e - 2 } else { e + 1 }
    if d.triangles[e] != i {
      break
    }
    e = d.halfedges[e]
    if e == e0 || e == -1 {
      break
    }
  }
  Some(points)
}

///|
fn Voronoi::clip(self : Voronoi, i : Int32) -> Array[Double]? {
  if i == 0 && self.delaunay.hull.length() == 1 {
    return Some(self.box())
  }
  guard self.cell(i) is Some(points) else { None }
  let v = self.vectors
  let k = i * 4
  simplify(
    if truthy(v[k]) || truthy(v[k + 1]) {
      self.clip_infinite(i, points, v[k], v[k + 1], v[k + 2], v[k + 3])
    } else {
      self.clip_finite(i, points)
    },
  )
}

///|
fn push_xy(
  p : Array[Double]?,
  x : Double,
  y : Double,
  capacity : Int32,
) -> Array[Double] {
  let p = match p {
    Some(p) => p
    None => Array(capacity~)
  }
  p.push(x)
  p.push(y)
  p
}

///|
fn Voronoi::clip_finite(
  self : Voronoi,
  i : Int32,
  points : Array[Double],
) -> Array[Double]? {
  let n = points.length()
  let mut p : Array[Double]? = None
  let mut x1 = points[n - 2]
  let mut y1 = points[n - 1]
  let mut c1 = self.regioncode(x1, y1)
  let mut e1 = 0
  for j = 0; j < n; j = j + 2 {
    let x0 = x1
    let y0 = y1
    x1 = points[j]
    y1 = points[j + 1]
    let c0 = c1
    c1 = self.regioncode(x1, y1)
    if c0 == 0 && c1 == 0 {
      e1 = 0
      p = Some(push_xy(p, x1, y1, n + 8))
    } else {
      let (sx1, sy1) = if c0 == 0 {
        guard self.clip_segment(x0, y0, x1, y1, c0, c1) is Some(s) else {
          continue
        }
        (s.2, s.3)
      } else {
        guard self.clip_segment(x1, y1, x0, y0, c1, c0) is Some(s) else {
          continue
        }
        let (sx1, sy1, sx0, sy0) = s
        let e0 = e1
        e1 = self.edgecode(sx0, sy0)
        if e0 != 0 && e1 != 0 && p is Some(q) {
          let _ = self.edge(i, e0, e1, q, q.length())
        }
        p = Some(push_xy(p, sx0, sy0, n + 8))
        (sx1, sy1)
      }
      let e0 = e1
      e1 = self.edgecode(sx1, sy1)
      if e0 != 0 && e1 != 0 && p is Some(q) {
        let _ = self.edge(i, e0, e1, q, q.length())
      }
      p = Some(push_xy(p, sx1, sy1, n + 8))
    }
  }
  match p {
    Some(q) => {
      let e0 = e1
      e1 = self.edgecode(q[0], q[1])
      if e0 != 0 && e1 != 0 {
        let _ = self.edge(i, e0, e1, q, q.length())
      }
      Some(q)
    }
    None =>
      if self.contains(
          i,
          (self.xmin + self.xmax) / 2.0,
          (self.ymin + self.ymax) / 2.0,
        ) {
        Some(self.box())
      } else {
        None
      }
  }
}

///|
/// Cohen-Sutherland clipping of a segment to the bounds; a step cap stands in
/// for rounding that would keep it bouncing between two sides.
fn Voronoi::clip_segment(
  self : Voronoi,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  c0 : Int32,
  c1 : Int32,
) -> (Double, Double, Double, Double)? {
  let flip = c0 < c1
  let x0_in = x0
  let y0_in = y0
  let c0_in = c0
  let mut x0 = x0
  let mut y0 = y0
  let mut x1 = x1
  let mut y1 = y1
  let mut c0 = c0
  let mut c1 = c1
  if flip {
    x0 = x1
    y0 = y1
    x1 = x0_in
    y1 = y0_in
    c0 = c1
    c1 = c0_in
  }
  for _ in 0..<64 {
    if c0 == 0 && c1 == 0 {
      return Some(if flip { (x1, y1, x0, y0) } else { (x0, y0, x1, y1) })
    }
    if (c0 & c1) != 0 {
      return None
    }
    let c = if c0 != 0 { c0 } else { c1 }
    let (x, y) = if (c & 0b1000) != 0 {
      (x0 + (x1 - x0) * (self.ymax - y0) / (y1 - y0), self.ymax)
    } else if (c & 0b0100) != 0 {
      (x0 + (x1 - x0) * (self.ymin - y0) / (y1 - y0), self.ymin)
    } else if (c & 0b0010) != 0 {
      (self.xmax, y0 + (y1 - y0) * (self.xmax - x0) / (x1 - x0))
    } else {
      (self.xmin, y0 + (y1 - y0) * (self.xmin - x0) / (x1 - x0))
    }
    if c0 != 0 {
      x0 = x
      y0 = y
      c0 = self.regioncode(x0, y0)
    } else {
      x1 = x
      y1 = y
      c1 = self.regioncode(x1, y1)
    }
  }
  None
}

///|
fn Voronoi::clip_infinite(
  self : Voronoi,
  i : Int32,
  points : Array[Double],
  vx0 : Double,
  vy0 : Double,
  vxn : Double,
  vyn : Double,
) -> Array[Double]? {
  let mut pts = points
  if self.project(pts[0], pts[1], vx0, vy0) is Some((x, y)) {
    pts = [x, y, ..pts]
  }
  if self.project(pts[pts.length() - 2], pts[pts.length() - 1], vxn, vyn)
    is Some((x, y)) {
    pts.push(x)
    pts.push(y)
  }
  match self.clip_finite(i, pts) {
    Some(p) => {
      let mut n = p.length()
      let mut c1 = self.edgecode(p[n - 2], p[n - 1])
      let mut j = 0
      while j < n {
        let c0 = c1
        c1 = self.edgecode(p[j], p[j + 1])
        if c0 != 0 && c1 != 0 {
          j = self.edge(i, c0, c1, p, j)
          n = p.length()
        }
        j += 2
      }
      Some(p)
    }
    None =>
      if self.contains(
          i,
          (self.xmin + self.xmax) / 2.0,
          (self.ymin + self.ymax) / 2.0,
        ) {
        Some([
          self.xmin,
          self.ymin,
          self.xmax,
          self.ymin,
          self.xmax,
          self.ymax,
          self.xmin,
          self.ymax,
        ])
      } else {
        None
      }
  }
}

///|
/// Inserts the bounds' corners from edge code `e0` round to `e1` that lie in
/// cell `i` into `p` at `j`; where the insertion ends.
fn Voronoi::edge(
  self : Voronoi,
  i : Int32,
  e0 : Int32,
  e1 : Int32,
  p : Array[Double],
  j : Int32,
) -> Int32 {
  let mut e0 = e0
  let mut j = j
  for _ in 0..<16 {
    if e0 == e1 {
      break
    }
    let (x, y) = match e0 {
      0b0101 => {
        e0 = 0b0100
        continue
      }
      0b0100 => {
        e0 = 0b0110
        (self.xmax, self.ymin)
      }
      0b0110 => {
        e0 = 0b0010
        continue
      }
      0b0010 => {
        e0 = 0b1010
        (self.xmax, self.ymax)
      }
      0b1010 => {
        e0 = 0b1000
        continue
      }
      0b1000 => {
        e0 = 0b1001
        (self.xmin, self.ymax)
      }
      0b1001 => {
        e0 = 0b0001
        continue
      }
      0b0001 => {
        e0 = 0b0101
        (self.xmin, self.ymin)
      }
      _ => break
    }
    if (j >= p.length() || p[j] != x || p[j + 1] != y) && self.contains(i, x, y) {
      p.insert(j, x)
      p.insert(j + 1, y)
      j += 2
    }
  }
  j
}

///|
/// Where the ray from `x0, y0` along `vx, vy` leaves the bounds; NaN for a
/// coordinate d3-delaunay leaves undefined (a zero vector).
fn Voronoi::project(
  self : Voronoi,
  x0 : Double,
  y0 : Double,
  vx : Double,
  vy : Double,
) -> (Double, Double)? {
  let mut t = @double.infinity
  let mut x = @double.not_a_number
  let mut y = @double.not_a_number
  if vy < 0.0 {
    if y0 <= self.ymin {
      return None
    }
    let c = (self.ymin - y0) / vy
    if c < t {
      y = self.ymin
      t = c
      x = x0 + t * vx
    }
  } else if vy > 0.0 {
    if y0 >= self.ymax {
      return None
    }
    let c = (self.ymax - y0) / vy
    if c < t {
      y = self.ymax
      t = c
      x = x0 + t * vx
    }
  }
  if vx > 0.0 {
    if x0 >= self.xmax {
      return None
    }
    let c = (self.xmax - x0) / vx
    if c < t {
      x = self.xmax
      t = c
      y = y0 + t * vy
    }
  } else if vx < 0.0 {
    if x0 <= self.xmin {
      return None
    }
    let c = (self.xmin - x0) / vx
    if c < t {
      x = self.xmin
      t = c
      y = y0 + t * vy
    }
  }
  Some((x, y))
}

///|
fn Voronoi::edgecode(self : Voronoi, x : Double, y : Double) -> Int32 {
  (if x == self.xmin { 0b0001 } else if x == self.xmax { 0b0010 } else { 0 }) |
  (if y == self.ymin { 0b0100 } else if y == self.ymax { 0b1000 } else { 0 })
}

///|
fn Voronoi::regioncode(self : Voronoi, x : Double, y : Double) -> Int32 {
  (if x < self.xmin { 0b0001 } else if x > self.xmax { 0b0010 } else { 0 }) |
  (if y < self.ymin { 0b0100 } else if y > self.ymax { 0b1000 } else { 0 })
}

///|
/// Drops the middle of three consecutive points on one vertical or horizontal
/// line (d3-delaunay's `_simplify`).
fn simplify(p : Array[Double]?) -> Array[Double]? {
  guard p is Some(p) && p.length() > 4 else { p }
  let mut i = 0
  while i < p.length() {
    let j = (i + 2) % p.length()
    let k = (i + 4) % p.length()
    if (p[i] == p[j] && p[j] == p[k]) ||
      (p[i + 1] == p[j + 1] && p[j + 1] == p[k + 1]) {
      p.remove(j) |> ignore
      p.remove(j) |> ignore
      i -= 2
    }
    i += 2
  }
  if p.length() == 0 {
    None
  } else {
    Some(p)
  }
}
