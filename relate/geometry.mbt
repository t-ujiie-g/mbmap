///|
/// JTS's `Location` values.
const INTERIOR : Int32 = 0

///|
const BOUNDARY : Int32 = 1

///|
const EXTERIOR : Int32 = 2

///|
const NONE : Int32 = -1

///|
/// JTS's `Position` indices into a topology location.
const ON : Int32 = 0

///|
const LEFT : Int32 = 1

///|
const RIGHT : Int32 = 2

///|
priv struct Coord {
  x : Double
  y : Double
}

///|
fn Coord::eq2d(self : Coord, o : Coord) -> Bool {
  self.x == o.x && self.y == o.y
}

///|
/// JTS's `Coordinate.compareTo`.
fn Coord::compare(self : Coord, o : Coord) -> Int32 {
  if self.x < o.x {
    -1
  } else if self.x > o.x {
    1
  } else if self.y < o.y {
    -1
  } else if self.y > o.y {
    1
  } else {
    0
  }
}

///|
fn Coord::distance(self : Coord, o : Coord) -> Double {
  let dx = self.x - o.x
  let dy = self.y - o.y
  (dx * dx + dy * dy).sqrt()
}

///|
/// JTS's `Envelope`: null while `maxx < minx`.
priv struct Env {
  mut minx : Double
  mut maxx : Double
  mut miny : Double
  mut maxy : Double
}

///|
fn Env::null() -> Env {
  { minx: 0.0, maxx: -1.0, miny: 0.0, maxy: -1.0, }
}

///|
fn Env::of2(a : Coord, b : Coord) -> Env {
  let e = Env::null()
  if a.x < b.x {
    e.minx = a.x
    e.maxx = b.x
  } else {
    e.minx = b.x
    e.maxx = a.x
  }
  if a.y < b.y {
    e.miny = a.y
    e.maxy = b.y
  } else {
    e.miny = b.y
    e.maxy = a.y
  }
  e
}

///|
fn Env::is_null(self : Env) -> Bool {
  self.maxx < self.minx
}

///|
fn Env::expand(self : Env, x : Double, y : Double) -> Unit {
  if self.is_null() {
    self.minx = x
    self.maxx = x
    self.miny = y
    self.maxy = y
  } else {
    if x < self.minx {
      self.minx = x
    }
    if x > self.maxx {
      self.maxx = x
    }
    if y < self.miny {
      self.miny = y
    }
    if y > self.maxy {
      self.maxy = y
    }
  }
}

///|
fn Env::expand_env(self : Env, o : Env) -> Unit {
  if o.is_null() {
    return
  }
  if self.is_null() {
    self.minx = o.minx
    self.maxx = o.maxx
    self.miny = o.miny
    self.maxy = o.maxy
  } else {
    if o.minx < self.minx {
      self.minx = o.minx
    }
    if o.maxx > self.maxx {
      self.maxx = o.maxx
    }
    if o.miny < self.miny {
      self.miny = o.miny
    }
    if o.maxy > self.maxy {
      self.maxy = o.maxy
    }
  }
}

///|
fn Env::intersects(self : Env, o : Env) -> Bool {
  if self.is_null() || o.is_null() {
    return false
  }
  !(o.minx > self.maxx ||
  o.maxx < self.minx ||
  o.miny > self.maxy ||
  o.maxy < self.miny)
}

///|
fn Env::intersects_pt(self : Env, p : Coord) -> Bool {
  if self.is_null() {
    return false
  }
  !(p.x > self.maxx || p.x < self.minx || p.y > self.maxy || p.y < self.miny)
}

///|
/// `Envelope.covers(Envelope)`, which `contains(Envelope)` also is.
fn Env::covers(self : Env, o : Env) -> Bool {
  if self.is_null() || o.is_null() {
    return false
  }
  o.minx >= self.minx &&
  o.maxx <= self.maxx &&
  o.miny >= self.miny &&
  o.maxy <= self.maxy
}

///|
fn Env::covers_pt(self : Env, p : Coord) -> Bool {
  if self.is_null() {
    return false
  }
  p.x >= self.minx && p.x <= self.maxx && p.y >= self.miny && p.y <= self.maxy
}

///|
fn Env::equals(self : Env, o : Env) -> Bool {
  if self.is_null() {
    return o.is_null()
  }
  self.maxx == o.maxx &&
  self.maxy == o.maxy &&
  self.minx == o.minx &&
  self.miny == o.miny
}

///|
/// The static `Envelope.intersects(p1, p2, q)`.
fn seg_env_has(p1 : Coord, p2 : Coord, q : Coord) -> Bool {
  q.x >= (if p1.x < p2.x { p1.x } else { p2.x }) &&
  q.x <= (if p1.x > p2.x { p1.x } else { p2.x }) &&
  q.y >= (if p1.y < p2.y { p1.y } else { p2.y }) &&
  q.y <= (if p1.y > p2.y { p1.y } else { p2.y })
}

///|
/// JavaScript's `Math.min`: NaN if either is.
fn js_min(a : Double, b : Double) -> Double {
  if a.is_nan() || b.is_nan() {
    @double.not_a_number
  } else if a < b {
    a
  } else if b < a {
    b
  } else if a == 0.0 && (1.0 / a < 0.0 || 1.0 / b < 0.0) {
    -0.0
  } else {
    a
  }
}

///|
/// JavaScript's `Math.max`: NaN if either is.
fn js_max(a : Double, b : Double) -> Double {
  if a.is_nan() || b.is_nan() {
    @double.not_a_number
  } else if a > b {
    a
  } else if b > a {
    b
  } else if a == 0.0 && (1.0 / a > 0.0 || 1.0 / b > 0.0) {
    0.0
  } else {
    a
  }
}

///|
/// The static `Envelope.intersects(p1, p2, q1, q2)`.
fn seg_envs_meet(p1 : Coord, p2 : Coord, q1 : Coord, q2 : Coord) -> Bool {
  let mut minq = js_min(q1.x, q2.x)
  let mut maxq = js_max(q1.x, q2.x)
  let mut minp = js_min(p1.x, p2.x)
  let mut maxp = js_max(p1.x, p2.x)
  if minp > maxq || maxp < minq {
    return false
  }
  minq = js_min(q1.y, q2.y)
  maxq = js_max(q1.y, q2.y)
  minp = js_min(p1.y, p2.y)
  maxp = js_max(p1.y, p2.y)
  !(minp > maxq || maxp < minq)
}

///|
#derive(Eq)
priv enum Kind {
  Empty
  Point
  MultiPoint
  Line
  MultiLine
  Poly
  MultiPoly
}

///|
/// A row as the JTS geometry it stands for: `points` for (multi)points,
/// `lines` for (multi)line strings, `polys` (shell first) for (multi)polygons;
/// `envelope` caches `env`.
priv struct Geometry {
  kind : Kind
  points : Array[Coord]
  lines : Array[Array[Coord]]
  polys : Array[Array[Array[Coord]]]
  mut envelope : Env?
}

///|
fn end_at(ends : Array[Int32], i : Int32, limit : Int32) -> Int32 {
  if i < 0 || i >= ends.length() {
    0
  } else {
    let e = ends[i]
    if e < 0 {
      0
    } else if e > limit {
      limit
    } else {
      e
    }
  }
}

///|
/// Ranges of the table's offsets, clamped so a table whose offsets disagree
/// cannot index out of bounds.
fn range_of(ends : Array[Int32], i : Int32, limit : Int32) -> (Int32, Int32) {
  let s = if i == 0 { 0 } else { end_at(ends, i - 1, limit) }
  let e = end_at(ends, i, limit)
  (s, if e < s { s } else { e })
}

///|
fn ring_coords(t : @geom.Table, r : Int32) -> Array[Coord] {
  let (s, e) = range_of(t.point_ends, r, t.coords.length() / 2)
  let out = Array(capacity=e - s)
  for k in s..<e {
    out.push({ x: t.coords[2 * k], y: t.coords[2 * k + 1], })
  }
  out
}

///|
fn part_rings(t : @geom.Table, p : Int32) -> Array[Array[Coord]] {
  let (s, e) = range_of(t.ring_ends, p, t.point_ends.length())
  let out = []
  for r in s..<e {
    let c = ring_coords(t, r)
    if c.length() > 0 {
      out.push(c)
    }
  }
  out
}

///|
fn row_parts(t : @geom.Table, i : Int32) -> Array[Array[Array[Coord]]] {
  if i < 0 || i >= t.kinds.length() {
    return []
  }
  let (s, e) = range_of(t.part_ends, i, t.ring_ends.length())
  let out = []
  for p in s..<e {
    let rings = part_rings(t, p)
    if rings.length() > 0 {
      out.push(rings)
    }
  }
  out
}

///|
/// Row `i` of `t`: a Point, LineString or Polygon is its first point, ring or
/// part; a row with no points is an empty geometry.
fn Geometry::of_row(t : @geom.Table, i : Int32) -> Geometry {
  let parts = row_parts(t, i)
  let empty = { kind: Empty, points: [], lines: [], polys: [], envelope: None, }
  if parts.length() == 0 {
    return empty
  }
  match t.kinds[i] {
    NoGeometry => empty
    Point =>
      {
        kind: Point,
        points: [parts[0][0][0]],
        lines: [],
        polys: [],
        envelope: None,
      }
    MultiPoint => {
      let pts = []
      for rings in parts {
        for r in rings {
          pts.append(r)
        }
      }
      { kind: MultiPoint, points: pts, lines: [], polys: [], envelope: None, }
    }
    LineString =>
      {
        kind: Line,
        points: [],
        lines: [parts[0][0]],
        polys: [],
        envelope: None,
      }
    MultiLineString => {
      let lines = []
      for rings in parts {
        lines.append(rings)
      }
      { kind: MultiLine, points: [], lines, polys: [], envelope: None, }
    }
    Polygon =>
      { kind: Poly, points: [], lines: [], polys: [parts[0]], envelope: None, }
    MultiPolygon =>
      { kind: MultiPoly, points: [], lines: [], polys: parts, envelope: None, }
  }
}

///|
fn Geometry::point_count(t : @geom.Table, i : Int32) -> Int32 {
  if i < 0 || i >= t.kinds.length() {
    return 0
  }
  let (ps, pe) = range_of(t.part_ends, i, t.ring_ends.length())
  if pe <= ps {
    return 0
  }
  let rs = range_of(t.ring_ends, ps, t.point_ends.length()).0
  let re = range_of(t.ring_ends, pe - 1, t.point_ends.length()).1
  if re <= rs {
    return 0
  }
  let limit = t.coords.length() / 2
  let s = range_of(t.point_ends, rs, limit).0
  let e = range_of(t.point_ends, re - 1, limit).1
  if e < s {
    0
  } else {
    e - s
  }
}

///|
fn Geometry::dimension(self : Geometry) -> Int32 {
  match self.kind {
    Empty => -1
    Point | MultiPoint => 0
    Line | MultiLine => 1
    Poly | MultiPoly => 2
  }
}

///|
fn line_closed(pts : Array[Coord]) -> Bool {
  pts.length() > 0 && pts[0].eq2d(pts[pts.length() - 1])
}

///|
fn Geometry::boundary_dimension(self : Geometry) -> Int32 {
  match self.kind {
    Empty | Point | MultiPoint => -1
    Line | MultiLine => {
      for l in self.lines {
        if !line_closed(l) {
          return 0
        }
      }
      -1
    }
    Poly | MultiPoly => 1
  }
}

///|
fn coords_env(pts : Array[Coord]) -> Env {
  let e = Env::null()
  for p in pts {
    e.expand(p.x, p.y)
  }
  e
}

///|
/// `getEnvelopeInternal`: a polygon's is its shell's, a collection's the union
/// of its elements'.
fn Geometry::env(self : Geometry) -> Env {
  if self.envelope is Some(e) {
    return e
  }
  let e = self.compute_env()
  self.envelope = Some(e)
  e
}

///|
fn Geometry::compute_env(self : Geometry) -> Env {
  match self.kind {
    Empty => Env::null()
    Point | Line =>
      coords_env(if self.kind == Point { self.points } else { self.lines[0] })
    Poly => coords_env(self.polys[0][0])
    MultiPoint => {
      let e = Env::null()
      for p in self.points {
        e.expand_env(coords_env([p]))
      }
      e
    }
    MultiLine => {
      let e = Env::null()
      for l in self.lines {
        e.expand_env(coords_env(l))
      }
      e
    }
    MultiPoly => {
      let e = Env::null()
      for p in self.polys {
        e.expand_env(coords_env(p[0]))
      }
      e
    }
  }
}

///|
/// `getLength`, as `Length.ofLine` sums it.
fn Geometry::length(self : Geometry) -> Double {
  let mut sum = 0.0
  for l in self.lines {
    let mut len = 0.0
    for k in 1..<l.length() {
      let dx = l[k].x - l[k - 1].x
      let dy = l[k].y - l[k - 1].y
      len += (dx * dx + dy * dy).sqrt()
    }
    sum += len
  }
  sum
}
