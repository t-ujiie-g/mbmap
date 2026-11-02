// Hit tests of rendered-feature queries as MapLibre GL JS 6.16.0 makes them
// (src/util/intersection_tests.ts), BSD-3-Clause, Copyright (c) 2020,
// MapLibre contributors. See NOTICE.

///|
/// A point, a polyline or a ring (closed by repeating its first point).
pub type Line = Array[(Double, Double)]

///|
fn ccw(
  a : (Double, Double),
  b : (Double, Double),
  c : (Double, Double),
) -> Bool {
  (c.1 - a.1) * (b.0 - a.0) > (b.1 - a.1) * (c.0 - a.0)
}

///|
fn segments_cross(
  a0 : (Double, Double),
  a1 : (Double, Double),
  b0 : (Double, Double),
  b1 : (Double, Double),
) -> Bool {
  ccw(a0, b0, b1) != ccw(a1, b0, b1) && ccw(a0, a1, b0) != ccw(a0, a1, b1)
}

///|
fn lines_cross(a : Line, b : Line) -> Bool {
  for i in 0..<(a.length() - 1) {
    for j in 0..<(b.length() - 1) {
      if segments_cross(a[i], a[i + 1], b[j], b[j + 1]) {
        return true
      }
    }
  }
  false
}

///|
/// Even-odd ray casting over `rings` together (MapLibre's
/// `multiPolygonContainsPoint`); a single ring is `polygonContainsPoint`.
fn rings_contain(rings : Array[Line], p : (Double, Double)) -> Bool {
  let mut c = false
  for ring in rings {
    let n = ring.length()
    for i in 0..<n {
      let p1 = ring[i]
      let p2 = ring[if i == 0 { n - 1 } else { i - 1 }]
      if (p1.1 > p.1) != (p2.1 > p.1) &&
        p.0 < (p2.0 - p1.0) * (p.1 - p1.1) / (p2.1 - p1.1) + p1.0 {
        c = !c
      }
    }
  }
  c
}

///|
fn dist2(a : (Double, Double), b : (Double, Double)) -> Double {
  let dx = a.0 - b.0
  let dy = a.1 - b.1
  dx * dx + dy * dy
}

///|
fn dist_to_segment2(
  p : (Double, Double),
  v : (Double, Double),
  w : (Double, Double),
) -> Double {
  let l2 = dist2(v, w)
  if l2 == 0.0 {
    return dist2(p, v)
  }
  let t = ((p.0 - v.0) * (w.0 - v.0) + (p.1 - v.1) * (w.1 - v.1)) / l2
  if t < 0.0 {
    return dist2(p, v)
  }
  if t > 1.0 {
    return dist2(p, w)
  }
  dist2(p, ((w.0 - v.0) * t + v.0, (w.1 - v.1) * t + v.1))
}

///|
/// Whether `p` lies within `radius` of `line` (`pointIntersectsBufferedLine`).
fn near_line(p : (Double, Double), line : Line, radius : Double) -> Bool {
  let r2 = radius * radius
  if line.length() == 1 {
    return dist2(p, line[0]) < r2
  }
  for i in 1..<line.length() {
    if dist_to_segment2(p, line[i - 1], line[i]) < r2 {
      return true
    }
  }
  false
}

///|
fn lines_near(a : Line, b : Line, radius : Double) -> Bool {
  if a.length() > 1 {
    if lines_cross(a, b) {
      return true
    }
    for p in b {
      if near_line(p, a, radius) {
        return true
      }
    }
  }
  for p in a {
    if near_line(p, b, radius) {
      return true
    }
  }
  false
}

///|
/// `polygonIntersectsMultiPolygon`: a query of one point tests containment.
pub fn polygon_hits_polygons(q : Line, rings : Array[Line]) -> Bool {
  if q.length() == 1 {
    return rings_contain(rings, q[0])
  }
  for ring in rings {
    for p in ring {
      if rings_contain([q], p) {
        return true
      }
    }
  }
  for p in q {
    if rings_contain(rings, p) {
      return true
    }
  }
  rings.iter().any(ring => lines_cross(q, ring))
}

///|
/// `polygonIntersectsPolygon`.
pub fn polygon_hits_polygon(a : Line, b : Line) -> Bool {
  a.iter().any(p => rings_contain([b], p)) ||
  b.iter().any(p => rings_contain([a], p)) ||
  lines_cross(a, b)
}

///|
/// `polygonIntersectsBufferedMultiLine`.
pub fn polygon_hits_lines(
  q : Line,
  lines : Array[Line],
  radius : Double,
) -> Bool {
  for line in lines {
    if q.length() >= 3 && line.iter().any(p => rings_contain([q], p)) {
      return true
    }
    if lines_near(q, line, radius) {
      return true
    }
  }
  false
}

///|
/// `polygonIntersectsBufferedPoint`.
pub fn polygon_hits_point(
  q : Line,
  p : (Double, Double),
  radius : Double,
) -> Bool {
  rings_contain([q], p) || near_line(p, q, radius)
}

///|
/// `polygonIntersectsBox`, the box as its corners (`x0` <= `x1`, `y0` <= `y1`).
pub fn polygon_hits_box(
  q : Line,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
) -> Bool {
  if q.iter().any(p => x0 <= p.0 && y0 <= p.1 && x1 >= p.0 && y1 >= p.1) {
    return true
  }
  let corners = [(x0, y0), (x0, y1), (x1, y1), (x1, y0)]
  if q.length() > 2 && corners.iter().any(c => rings_contain([q], c)) {
    return true
  }
  for i in 0..<(q.length() - 1) {
    let (e1, e2) = (q[i], q[i + 1])
    if (e1.0 < x0 && e2.0 < x0) ||
      (e1.0 > x1 && e2.0 > x1) ||
      (e1.1 < y0 && e2.1 < y0) ||
      (e1.1 > y1 && e2.1 > y1) {
      continue
    }
    let dir = ccw(e1, e2, corners[0])
    if dir != ccw(e1, e2, corners[1]) ||
      dir != ccw(e1, e2, corners[2]) ||
      dir != ccw(e1, e2, corners[3]) {
      return true
    }
  }
  false
}
