// Ported from Turf 7.4.0 (@turf/simplify with simplify-js inlined,
// @turf/clean-coords, @turf/boolean-point-on-line), Copyright (c) 2019 Morgan
// Herlocker, and simplify-js, Copyright (c) 2017 Vladimir Agafonkin, both
// under the MIT license (NOTICE).

///|
/// JavaScript's `Number.EPSILON`, where Turf stops lowering a ring's tolerance.
const NUMBER_EPSILON : Double = 2.220446049250313e-16

///|
/// Points by their index in a table's `coords`: Turf compares positions by
/// identity in places, which an index keeps.
priv struct Points {
  coords : Array[Double]
}

///|
fn Points::x(self : Points, p : Int) -> Double {
  self.coords[2 * p]
}

///|
fn Points::y(self : Points, p : Int) -> Double {
  self.coords[2 * p + 1]
}

///|
fn Points::same(self : Points, a : Int, b : Int) -> Bool {
  self.x(a) == self.x(b) && self.y(a) == self.y(b)
}

///|
fn Points::sq_dist(self : Points, a : Int, b : Int) -> Double {
  let dx = self.x(a) - self.x(b)
  let dy = self.y(a) - self.y(b)
  dx * dx + dy * dy
}

///|
fn Points::sq_seg_dist(self : Points, p : Int, p1 : Int, p2 : Int) -> Double {
  let mut x = self.x(p1)
  let mut y = self.y(p1)
  let mut dx = self.x(p2) - x
  let mut dy = self.y(p2) - y
  if dx != 0.0 || dy != 0.0 {
    let t = ((self.x(p) - x) * dx + (self.y(p) - y) * dy) / (dx * dx + dy * dy)
    if t > 1.0 {
      x = self.x(p2)
      y = self.y(p2)
    } else if t > 0.0 {
      x += dx * t
      y += dy * t
    }
  }
  dx = self.x(p) - x
  dy = self.y(p) - y
  dx * dx + dy * dy
}

///|
/// boolean-point-on-line's `isPointOnLineSegment` without epsilon or excluded
/// ends: whether `p` lies on the segment `s`, `e` exactly.
fn Points::on_segment(self : Points, p : Int, s : Int, e : Int) -> Bool {
  let x = self.x(p)
  let y = self.y(p)
  let x1 = self.x(s)
  let y1 = self.y(s)
  let x2 = self.x(e)
  let y2 = self.y(e)
  let dxl = x2 - x1
  let dyl = y2 - y1
  let cross = (x - x1) * dyl - (y - y1) * dxl
  if cross != 0.0 {
    return false
  }
  if dxl.abs() == dyl.abs() && dxl.abs() == 0.0 {
    return x == x1 && y == y1
  }
  if dxl.abs() >= dyl.abs() {
    if dxl > 0.0 {
      x1 <= x && x <= x2
    } else {
      x2 <= x && x <= x1
    }
  } else if dyl > 0.0 {
    y1 <= y && y <= y2
  } else {
    y2 <= y && y <= y1
  }
}

///|
/// clean-coords' `cleanLine`; None where it throws (a ring that comes out
/// with fewer than 4 points or open). A line of one point stays one point
/// (Turf adds an `undefined` position).
fn Points::clean_line(self : Points, points : Array[Int], ring : Bool) -> Array[Int]? {
  let n = points.length()
  if n < 2 {
    return if ring { None } else { Some(points) }
  }
  if n == 2 && !self.same(points[0], points[1]) {
    return Some(points)
  }
  let out = [points[0]]
  let mut a = 0
  let mut b = 1
  let mut c = 2
  while c < n {
    if self.on_segment(points[b], points[a], points[c]) {
      b = c
    } else {
      out.push(points[b])
      a = b
      b += 1
      c = b
    }
    c += 1
  }
  out.push(points[b])
  if !ring {
    return Some(out)
  }
  if self.on_segment(out[0], out[1], out[out.length() - 2]) {
    out.remove(0) |> ignore
    out.unsafe_pop() |> ignore
    if out.length() == 0 {
      return None
    }
    out.push(out[0])
  }
  if out.length() < 4 || !self.same(out[0], out[out.length() - 1]) {
    return None
  }
  Some(out)
}

///|
/// The larger of `th` and the distance `d` a false `d > sq` compared: the
/// result stands for every tolerance whose square is at least this.
fn note(th : Double, d : Double) -> Double {
  if d > th {
    d
  } else {
    th
  }
}

///|
/// simplify-js's `simplify` with the square tolerance `sq`, and the threshold
/// of `note` for it.
fn Points::simplify(
  self : Points,
  points : Array[Int],
  sq : Double,
  high_quality : Bool,
) -> (Array[Int], Double) {
  let mut th = @double.neg_infinity
  if points.length() <= 2 {
    return (points, th)
  }
  let pts = if high_quality {
    points
  } else {
    let mut prev = points[0]
    let out = [prev]
    for i in 1..<points.length() {
      let d = self.sq_dist(points[i], prev)
      if d > sq {
        out.push(points[i])
        prev = points[i]
      } else {
        th = note(th, d)
      }
    }
    let last = points[points.length() - 1]
    if prev != last {
      out.push(last)
    }
    out
  }
  let last = pts.length() - 1
  let kept = FixedArray::make(pts.length(), false)
  let stack = [0, last]
  while stack.length() > 0 {
    let hi = stack.unsafe_pop()
    let lo = stack.unsafe_pop()
    let mut max = sq
    let mut index = -1
    for i in (lo + 1)..<hi {
      let d = self.sq_seg_dist(pts[i], pts[lo], pts[hi])
      if d > max {
        index = i
        max = d
      } else if index < 0 {
        th = note(th, d)
      }
    }
    if max > sq {
      kept[index] = true
      if index - lo > 1 {
        stack.push(lo)
        stack.push(index)
      }
      if hi - index > 1 {
        stack.push(index)
        stack.push(hi)
      }
    }
  }
  let out = [pts[0]]
  for i in 1..<last {
    if kept[i] {
      out.push(pts[i])
    }
  }
  out.push(pts[last])
  (out, th)
}

///|
fn Points::valid_ring(self : Points, ring : Array[Int]) -> Bool {
  if ring.length() < 3 {
    return false
  }
  !(ring.length() == 3 && self.same(ring[2], ring[0]))
}

///|
/// simplify's `simplifyPolygon` for one ring: the tolerance lowered by 1% at a
/// time until the ring keeps a valid shape, else the ring as given. Tolerances
/// that cannot change the result are stepped over without simplifying again.
fn Points::simplify_ring(
  self : Points,
  ring : Array[Int],
  tolerance : Double,
  high_quality : Bool,
) -> Array[Int] {
  let mut tol = tolerance
  let (first, th) = self.simplify(ring, tol * tol, high_quality)
  let mut simple = first
  let mut th = th
  while !self.valid_ring(simple) && tol >= NUMBER_EPSILON {
    tol -= tol * 0.01
    if th > tol * tol {
      let (s, t) = self.simplify(ring, tol * tol, high_quality)
      simple = s
      th = t
    }
  }
  if !self.valid_ring(simple) {
    return ring
  }
  if !self.same(simple[simple.length() - 1], simple[0]) {
    simple.push(simple[0])
  }
  simple
}

///|
/// Each row of `t` simplified as Turf 7.4.0's `simplify` (with `tolerance` and
/// `highQuality`) simplifies its geometry: lines and polygon rings cleaned of
/// repeated and collinear points, then radial distance and Douglas-Peucker
/// passes (`high_quality` skips the radial one); a ring's tolerance is lowered
/// until it keeps at least 4 points, else it stays as cleaned. Points and
/// multipoints are kept, as are rows, ids and properties. Where Turf throws, the
/// row keeps its geometry: a polygon with a ring that cleans to fewer than 4
/// points or is open, and every row for a negative tolerance.
pub fn simplify(
  t : @geom.Table,
  tolerance : Double,
  high_quality : Bool,
) -> @geom.Table {
  let b = @geom.TableBuilder::new()
  let pts : Points = { coords: t.coords }
  for f in 0..<t.length() {
    let kind = t.kinds[f]
    let lines = match kind {
      _ if tolerance < 0.0 => None
      LineString | MultiLineString => Some(false)
      Polygon | MultiPolygon => Some(true)
      _ => None
    }
    let parts = match lines {
      Some(ring) => simplify_parts(t, pts, f, ring, tolerance, high_quality)
      None => None
    }
    let (p0, p1) = t.parts(f)
    match parts {
      Some(parts) =>
        for part in parts {
          for ring in part {
            for p in ring {
              b.point(pts.x(p), pts.y(p))
            }
            b.end_ring()
          }
          b.end_part()
        }
      None =>
        for p in p0..<p1 {
          let (r0, r1) = t.rings(p)
          for r in r0..<r1 {
            let (c0, c1) = t.points(r)
            for c in c0..<c1 {
              b.point(pts.x(c), pts.y(c))
            }
            b.end_ring()
          }
          b.end_part()
        }
    }
    for c in t.columns {
      if c.values[f] is Some(v) {
        b.prop(c.name, v)
      }
    }
    b.end_feature(kind, id=t.ids[f])
  }
  b.finish()
}

///|
/// Row `f`'s parts and rings simplified, or None where Turf would throw.
fn simplify_parts(
  t : @geom.Table,
  pts : Points,
  f : Int,
  rings : Bool,
  tolerance : Double,
  high_quality : Bool,
) -> Array[Array[Array[Int]]]? {
  let out = []
  let (p0, p1) = t.parts(f)
  for p in p0..<p1 {
    let part = []
    let (r0, r1) = t.rings(p)
    for r in r0..<r1 {
      let (c0, c1) = t.points(r)
      let ring = Array::makei(c1 - c0, i => c0 + i)
      guard pts.clean_line(ring, rings) is Some(clean) else { return None }
      if rings {
        if clean.length() < 4 {
          return None
        }
        part.push(pts.simplify_ring(clean, tolerance, high_quality))
      } else {
        part.push(pts.simplify(clean, tolerance * tolerance, high_quality).0)
      }
    }
    out.push(part)
  }
  Some(out)
}
