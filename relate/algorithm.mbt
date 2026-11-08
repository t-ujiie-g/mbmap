///|
/// The part of JTS's `DD` (double-double) that `orientationIndex` uses.
priv struct DD {
  mut hi : Double
  mut lo : Double
}

///|
const DD_SPLIT : Double = 134217729.0

///|
/// `selfAdd(double)`.
fn DD::add_num(self : DD, y : Double) -> DD {
  let s0 = self.hi + y
  let e = s0 - self.hi
  let mut s = s0 - e
  s = y - e + (self.hi - s)
  let f = s + self.lo
  let h0 = s0 + f
  let h = f + (s0 - h0)
  self.hi = h0 + h
  self.lo = h + (h0 - self.hi)
  self
}

///|
/// `selfAdd(yhi, ylo)`.
fn DD::add2(self : DD, yhi : Double, ylo : Double) -> DD {
  let s0 = self.hi + yhi
  let t0 = self.lo + ylo
  let mut e = s0 - self.hi
  let f = t0 - self.lo
  let mut s = s0 - e
  let mut t = t0 - f
  s = yhi - e + (self.hi - s)
  t = ylo - f + (self.lo - t)
  e = s + t0
  let h0 = s0 + e
  let h = e + (s0 - h0)
  e = t + h
  let zhi = h0 + e
  let zlo = e + (h0 - zhi)
  self.hi = zhi
  self.lo = zlo
  self
}

///|
/// `selfMultiply(yhi, ylo)`.
fn DD::mul2(self : DD, yhi : Double, ylo : Double) -> DD {
  let mut c0 = DD_SPLIT * self.hi
  let mut hx = c0 - self.hi
  let mut c = DD_SPLIT * yhi
  hx = c0 - hx
  let tx = self.hi - hx
  let mut hy = c - yhi
  c0 = self.hi * yhi
  hy = c - hy
  let ty = yhi - hy
  c = hx * hy -
    c0 +
    hx * ty +
    tx * hy +
    tx * ty +
    (self.hi * ylo + self.lo * yhi)
  let zhi = c0 + c
  hx = c0 - zhi
  let zlo = c + hx
  self.hi = zhi
  self.lo = zlo
  self
}

///|
fn DD::signum(self : DD) -> Int32 {
  if self.hi > 0.0 {
    1
  } else if self.hi < 0.0 {
    -1
  } else if self.lo > 0.0 {
    1
  } else if self.lo < 0.0 {
    -1
  } else {
    0
  }
}

///|
fn signum(x : Double) -> Int32 {
  if x > 0.0 {
    1
  } else if x < 0.0 {
    -1
  } else {
    0
  }
}

///|
/// `CGAlgorithmsDD.orientationIndexFilter`: 2 when the sign is uncertain.
fn orientation_filter(pa : Coord, pb : Coord, pc : Coord) -> Int32 {
  let detleft = (pa.x - pc.x) * (pb.y - pc.y)
  let detright = (pa.y - pc.y) * (pb.x - pc.x)
  let det = detleft - detright
  let detsum = if detleft > 0.0 {
    if detright <= 0.0 {
      return signum(det)
    }
    detleft + detright
  } else if detleft < 0.0 {
    if detright >= 0.0 {
      return signum(det)
    }
    -detleft - detright
  } else {
    return signum(det)
  }
  let errbound = 1.0e-15 * detsum
  if det >= errbound || -det >= errbound {
    return signum(det)
  }
  2
}

///|
/// `Orientation.index`: 1 if `q` is left of p1→p2, -1 right, 0 collinear.
fn orientation_index(p1 : Coord, p2 : Coord, q : Coord) -> Int32 {
  let index = orientation_filter(p1, p2, q)
  if index <= 1 {
    return index
  }
  let dx1 = { hi: p2.x, lo: 0.0, }.add_num(-p1.x)
  let dy1 = { hi: p2.y, lo: 0.0, }.add_num(-p1.y)
  let dx2 = { hi: q.x, lo: 0.0, }.add_num(-p2.x)
  let dy2 = { hi: q.y, lo: 0.0, }.add_num(-p2.y)
  let a = dx1.mul2(dy2.hi, dy2.lo)
  let b = dy1.mul2(dx2.hi, dx2.lo)
  if !a.hi.is_nan() {
    let _ = a.add2(-b.hi, -b.lo)
  }
  a.signum()
}

///|
/// `Orientation.isCCW` over a ring of at least 4 points.
fn is_ccw(ring : Array[Coord]) -> Bool {
  let n = ring.length() - 1
  let mut hi = ring[0]
  let mut hi_index = 0
  for i in 1..<=n {
    if ring[i].y > hi.y {
      hi = ring[i]
      hi_index = i
    }
  }
  let mut prev_i = hi_index
  while true {
    prev_i = prev_i - 1
    if prev_i < 0 {
      prev_i = n
    }
    if !(ring[prev_i].eq2d(hi) && prev_i != hi_index) {
      break
    }
  }
  let mut next_i = hi_index
  while true {
    next_i = (next_i + 1) % n
    if !(ring[next_i].eq2d(hi) && next_i != hi_index) {
      break
    }
  }
  let prev = ring[prev_i]
  let next = ring[next_i]
  if prev.eq2d(hi) || next.eq2d(hi) || prev.eq2d(next) {
    return false
  }
  let disc = orientation_index(prev, hi, next)
  if disc == 0 {
    prev.x > next.x
  } else {
    disc > 0
  }
}

///|
/// `Intersection.intersection`: None when the lines are parallel.
fn line_intersection(p1 : Coord, p2 : Coord, q1 : Coord, q2 : Coord) -> Coord? {
  let min_x0 = if p1.x < p2.x { p1.x } else { p2.x }
  let min_y0 = if p1.y < p2.y { p1.y } else { p2.y }
  let max_x0 = if p1.x > p2.x { p1.x } else { p2.x }
  let max_y0 = if p1.y > p2.y { p1.y } else { p2.y }
  let min_x1 = if q1.x < q2.x { q1.x } else { q2.x }
  let min_y1 = if q1.y < q2.y { q1.y } else { q2.y }
  let max_x1 = if q1.x > q2.x { q1.x } else { q2.x }
  let max_y1 = if q1.y > q2.y { q1.y } else { q2.y }
  let int_min_x = if min_x0 > min_x1 { min_x0 } else { min_x1 }
  let int_max_x = if max_x0 < max_x1 { max_x0 } else { max_x1 }
  let int_min_y = if min_y0 > min_y1 { min_y0 } else { min_y1 }
  let int_max_y = if max_y0 < max_y1 { max_y0 } else { max_y1 }
  let midx = (int_min_x + int_max_x) / 2.0
  let midy = (int_min_y + int_max_y) / 2.0
  let p1x = p1.x - midx
  let p1y = p1.y - midy
  let p2x = p2.x - midx
  let p2y = p2.y - midy
  let q1x = q1.x - midx
  let q1y = q1.y - midy
  let q2x = q2.x - midx
  let q2y = q2.y - midy
  let px = p1y - p2y
  let py = p2x - p1x
  let pw = p1x * p2y - p2x * p1y
  let qx = q1y - q2y
  let qy = q2x - q1x
  let qw = q1x * q2y - q2x * q1y
  let x = py * qw - qy * pw
  let y = qx * pw - px * qw
  let w = px * qy - qx * py
  let x_int = x / w
  let y_int = y / w
  if x_int.is_nan() || x_int.is_inf() || y_int.is_nan() || y_int.is_inf() {
    None
  } else {
    Some({ x: x_int + midx, y: y_int + midy, })
  }
}

///|
/// `Distance.pointToSegment`.
fn point_to_segment(p : Coord, a : Coord, b : Coord) -> Double {
  if a.x == b.x && a.y == b.y {
    return p.distance(a)
  }
  let len2 = (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)
  let r = ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / len2
  if r <= 0.0 {
    return p.distance(a)
  }
  if r >= 1.0 {
    return p.distance(b)
  }
  let s = ((a.y - p.y) * (b.x - a.x) - (a.x - p.x) * (b.y - a.y)) / len2
  s.abs() * len2.sqrt()
}

///|
/// `RobustLineIntersector.computeIntersection(p, p1, p2)`: whether `p` lies on
/// the segment.
fn point_on_segment(p : Coord, p1 : Coord, p2 : Coord) -> Bool {
  seg_env_has(p1, p2, p) &&
  orientation_index(p1, p2, p) == 0 &&
  orientation_index(p2, p1, p) == 0
}

///|
const NO_INTERSECTION : Int32 = 0

///|
const POINT_INTERSECTION : Int32 = 1

///|
const COLLINEAR_INTERSECTION : Int32 = 2

///|
/// JTS's `RobustLineIntersector` without a precision model. `input` holds
/// the segments' ends: p1, p2, q1, q2.
priv struct LineIntersector {
  mut result : Int32
  input : FixedArray[Coord]
  int_pt : FixedArray[Coord]
  mut proper : Bool
}

///|
fn LineIntersector::new() -> LineIntersector {
  let o = { x: 0.0, y: 0.0, }
  {
    result: 0,
    input: FixedArray::make(4, o),
    int_pt: FixedArray::make(2, o),
    proper: false,
  }
}

///|
fn LineIntersector::has_intersection(self : LineIntersector) -> Bool {
  self.result != NO_INTERSECTION
}

///|
fn LineIntersector::is_proper(self : LineIntersector) -> Bool {
  self.has_intersection() && self.proper
}

///|
fn LineIntersector::is_intersection(self : LineIntersector, pt : Coord) -> Bool {
  for i in 0..<self.result {
    if self.int_pt[i].eq2d(pt) {
      return true
    }
  }
  false
}

///|
fn LineIntersector::compute(
  self : LineIntersector,
  p1 : Coord,
  p2 : Coord,
  q1 : Coord,
  q2 : Coord,
) -> Unit {
  self.input[0] = p1
  self.input[1] = p2
  self.input[2] = q1
  self.input[3] = q2
  self.result = self.compute_intersect(p1, p2, q1, q2)
}

///|
/// `LineIntersector.computeEdgeDistance`.
fn edge_distance(p : Coord, p0 : Coord, p1 : Coord) -> Double {
  let dx = (p1.x - p0.x).abs()
  let dy = (p1.y - p0.y).abs()
  if p.eq2d(p0) {
    0.0
  } else if p.eq2d(p1) {
    if dx > dy {
      dx
    } else {
      dy
    }
  } else {
    let pdx = (p.x - p0.x).abs()
    let pdy = (p.y - p0.y).abs()
    let dist = if dx > dy { pdx } else { pdy }
    if dist == 0.0 && !p.eq2d(p0) {
      @core.js_max(pdx, pdy)
    } else {
      dist
    }
  }
}

///|
/// `getEdgeDistance(segmentIndex, intIndex)`: along input segment `seg` (0 or 1).
fn LineIntersector::edge_distance(
  self : LineIntersector,
  seg : Int32,
  int_index : Int32,
) -> Double {
  edge_distance(
    self.int_pt[int_index],
    self.input[2 * seg],
    self.input[2 * seg + 1],
  )
}

///|
fn LineIntersector::in_segment_envelopes(
  self : LineIntersector,
  p : Coord,
) -> Bool {
  Env::of2(self.input[0], self.input[1]).covers_pt(p) &&
  Env::of2(self.input[2], self.input[3]).covers_pt(p)
}

///|
fn nearest_endpoint(p1 : Coord, p2 : Coord, q1 : Coord, q2 : Coord) -> Coord {
  let mut nearest = p1
  let mut min = point_to_segment(p1, q1, q2)
  let mut d = point_to_segment(p2, q1, q2)
  if d < min {
    min = d
    nearest = p2
  }
  d = point_to_segment(q1, p1, p2)
  if d < min {
    min = d
    nearest = q1
  }
  d = point_to_segment(q2, p1, p2)
  if d < min {
    nearest = q2
  }
  nearest
}

///|
fn LineIntersector::intersection(
  self : LineIntersector,
  p1 : Coord,
  p2 : Coord,
  q1 : Coord,
  q2 : Coord,
) -> Coord {
  let pt = match line_intersection(p1, p2, q1, q2) {
    Some(pt) => pt
    None => nearest_endpoint(p1, p2, q1, q2)
  }
  if self.in_segment_envelopes(pt) {
    pt
  } else {
    nearest_endpoint(p1, p2, q1, q2)
  }
}

///|
fn LineIntersector::collinear(
  self : LineIntersector,
  p1 : Coord,
  p2 : Coord,
  q1 : Coord,
  q2 : Coord,
) -> Int32 {
  let p1q1p2 = seg_env_has(p1, p2, q1)
  let p1q2p2 = seg_env_has(p1, p2, q2)
  let q1p1q2 = seg_env_has(q1, q2, p1)
  let q1p2q2 = seg_env_has(q1, q2, p2)
  let set = fn(a : Coord, b : Coord) {
    self.int_pt[0] = a
    self.int_pt[1] = b
  }
  if p1q1p2 && p1q2p2 {
    set(q1, q2)
    return COLLINEAR_INTERSECTION
  }
  if q1p1q2 && q1p2q2 {
    set(p1, p2)
    return COLLINEAR_INTERSECTION
  }
  let point_or_collinear = fn(b : Bool) {
    if b {
      POINT_INTERSECTION
    } else {
      COLLINEAR_INTERSECTION
    }
  }
  if p1q1p2 && q1p1q2 {
    set(q1, p1)
    return point_or_collinear(q1.eq2d(p1) && !p1q2p2 && !q1p2q2)
  }
  if p1q1p2 && q1p2q2 {
    set(q1, p2)
    return point_or_collinear(q1.eq2d(p2) && !p1q2p2 && !q1p1q2)
  }
  if p1q2p2 && q1p1q2 {
    set(q2, p1)
    return point_or_collinear(q2.eq2d(p1) && !p1q1p2 && !q1p2q2)
  }
  if p1q2p2 && q1p2q2 {
    set(q2, p2)
    return point_or_collinear(q2.eq2d(p2) && !p1q1p2 && !q1p1q2)
  }
  NO_INTERSECTION
}

///|
fn LineIntersector::compute_intersect(
  self : LineIntersector,
  p1 : Coord,
  p2 : Coord,
  q1 : Coord,
  q2 : Coord,
) -> Int32 {
  self.proper = false
  if !seg_envs_meet(p1, p2, q1, q2) {
    return NO_INTERSECTION
  }
  let pq1 = orientation_index(p1, p2, q1)
  let pq2 = orientation_index(p1, p2, q2)
  if (pq1 > 0 && pq2 > 0) || (pq1 < 0 && pq2 < 0) {
    return NO_INTERSECTION
  }
  let qp1 = orientation_index(q1, q2, p1)
  let qp2 = orientation_index(q1, q2, p2)
  if (qp1 > 0 && qp2 > 0) || (qp1 < 0 && qp2 < 0) {
    return NO_INTERSECTION
  }
  if pq1 == 0 && pq2 == 0 && qp1 == 0 && qp2 == 0 {
    return self.collinear(p1, p2, q1, q2)
  }
  if pq1 == 0 || pq2 == 0 || qp1 == 0 || qp2 == 0 {
    self.proper = false
    if p1.eq2d(q1) || p1.eq2d(q2) {
      self.int_pt[0] = p1
    } else if p2.eq2d(q1) || p2.eq2d(q2) {
      self.int_pt[0] = p2
    } else if pq1 == 0 {
      self.int_pt[0] = q1
    } else if pq2 == 0 {
      self.int_pt[0] = q2
    } else if qp1 == 0 {
      self.int_pt[0] = p1
    } else if qp2 == 0 {
      self.int_pt[0] = p2
    }
  } else {
    self.proper = true
    self.int_pt[0] = self.intersection(p1, p2, q1, q2)
  }
  POINT_INTERSECTION
}
