// Port of `distance` of @maplibre/maplibre-gl-style-spec 26.5.0 (distance.ts, cheap_ruler.ts,
// classify_rings.ts), BSD 3-Clause License, and tinyqueue 3.0.0, ISC License (NOTICE).

///|
/// A geometry `distance` measures to, in longitude, latitude pairs (MapLibre's
/// `SimpleGeometry`): `Other` is a type it skips.
pub(all) enum Shape {
  Point(Double, Double)
  Line(Array[Double])
  Polygon(Array[Array[Double]])
  Other
} derive(Debug, Eq)

///|
/// cheap-ruler's multipliers from degrees to meters at a latitude.
priv struct Ruler {
  kx : Double
  ky : Double
}

///|
fn Ruler::new(lat : Double, trig : @core.Trig) -> Ruler {
  let fe = 1.0 / 298.257223563
  let e2 = fe * (2.0 - fe)
  let rad = pi / 180.0
  let m = rad * 6378.137 * 1000.0
  let coslat = (trig.cos)(lat * rad)
  let w2 = 1.0 / (1.0 - e2 * (1.0 - coslat * coslat))
  let w = w2.sqrt()
  { kx: m * w * coslat, ky: m * w * w2 * (1.0 - e2), }
}

///|
fn wrap(deg : Double) -> Double {
  if deg.is_nan() || deg.is_inf() {
    return deg
  }
  let mut d = deg
  while d < -180.0 {
    d += 360.0
  }
  while d > 180.0 {
    d -= 360.0
  }
  d
}

///|
fn Ruler::distance(
  self : Ruler,
  a : (Double, Double),
  b : (Double, Double),
) -> Double {
  let dx = wrap(a.0 - b.0) * self.kx
  let dy = (a.1 - b.1) * self.ky
  (dx * dx + dy * dy).sqrt()
}

///|
/// cheap-ruler's `pointOnLine`: the point of `line` nearest to `p`.
fn Ruler::point_on_line(
  self : Ruler,
  line : ArrayView[(Double, Double)],
  p : (Double, Double),
) -> (Double, Double) {
  let mut min = @double.infinity
  let mut best = (@double.not_a_number, @double.not_a_number)
  for i in 0..<(line.length() - 1) {
    let mut x = line[i].0
    let mut y = line[i].1
    let mut dx = wrap(line[i + 1].0 - x) * self.kx
    let mut dy = (line[i + 1].1 - y) * self.ky
    if dx != 0.0 || dy != 0.0 {
      let t = (wrap(p.0 - x) * self.kx * dx + (p.1 - y) * self.ky * dy) /
        (dx * dx + dy * dy)
      if t > 1.0 {
        x = line[i + 1].0
        y = line[i + 1].1
      } else if t > 0.0 {
        x += dx / self.kx * t
        y += dy / self.ky * t
      }
    }
    dx = wrap(p.0 - x) * self.kx
    dy = (p.1 - y) * self.ky
    let d = dx * dx + dy * dy
    if d < min {
      min = d
      best = (x, y)
    }
  }
  best
}

///|
fn Ruler::to_line(
  self : Ruler,
  p : (Double, Double),
  line : ArrayView[(Double, Double)],
) -> Double {
  self.distance(p, self.point_on_line(line, p))
}

///|
fn Ruler::segments(
  self : Ruler,
  p1 : (Double, Double),
  p2 : (Double, Double),
  q1 : (Double, Double),
  q2 : (Double, Double),
) -> Double {
  let d1 = js_min(self.to_line(p1, [q1, q2]), self.to_line(p2, [q1, q2]))
  let d2 = js_min(self.to_line(q1, [p1, p2]), self.to_line(q2, [p1, p2]))
  js_min(d1, d2)
}

///|
fn range_safe(r : (Int32, Int32), n : Int32) -> Bool {
  r.1 >= r.0 && r.1 < n
}

///|
fn range_size(r : (Int32, Int32)) -> Int32 {
  r.1 - r.0 + 1
}

///|
fn split_range(
  r : (Int32, Int32),
  line : Bool,
) -> ((Int32, Int32)?, (Int32, Int32)?) {
  if r.0 > r.1 {
    return (None, None)
  }
  let size = range_size(r)
  if line {
    if size == 2 {
      return (Some(r), None)
    }
    let half = size / 2
    return (Some((r.0, r.0 + half)), Some((r.0 + half, r.1)))
  }
  if size == 1 {
    return (Some(r), None)
  }
  let half = size / 2 - 1
  (Some((r.0, r.0 + half)), Some((r.0 + half + 1, r.1)))
}

///|
fn range_box(points : Array[(Double, Double)], r : (Int32, Int32)) -> BBox {
  let b = BBox::empty()
  if range_safe(r, points.length()) {
    for i in r.0..<=r.1 {
      b.add(points[i])
    }
  }
  b
}

///|
fn polygon_box(polygon : Array[Array[(Double, Double)]]) -> BBox {
  let b = BBox::empty()
  for ring in polygon {
    for p in ring {
      b.add(p)
    }
  }
  b
}

///|
/// MapLibre's `bboxToBBoxDistance` (whose validity check never fails for an
/// empty box, as there).
fn box_distance(a : BBox, b : BBox, ruler : Ruler) -> Double {
  let valid = (b : BBox) => {
    b.x0 != @double.neg_infinity &&
    b.y0 != @double.neg_infinity &&
    b.x1 != @double.infinity &&
    b.y1 != @double.infinity
  }
  if !valid(a) || !valid(b) {
    return @double.not_a_number
  }
  let mut dx = 0.0
  let mut dy = 0.0
  if a.x1 < b.x0 {
    dx = b.x0 - a.x1
  }
  if a.x0 > b.x1 {
    dx = a.x0 - b.x1
  }
  if a.y0 > b.y1 {
    dy = a.y0 - b.y1
  }
  if a.y1 < b.y0 {
    dy = b.y0 - a.y1
  }
  ruler.distance((0.0, 0.0), (dx, dy))
}

///|
/// tinyqueue with MapLibre's `compareDistPair`: the largest distance on top.
priv struct Queue {
  data : Array[(Double, (Int32, Int32), (Int32, Int32))]
}

///|
fn order_of(
  a : (Double, (Int32, Int32), (Int32, Int32)),
  b : (Double, (Int32, Int32), (Int32, Int32)),
) -> Double {
  b.0 - a.0
}

///|
fn Queue::push(
  self : Queue,
  item : (Double, (Int32, Int32), (Int32, Int32)),
) -> Unit {
  let data = self.data
  data.push(item)
  let mut pos = data.length() - 1
  while pos > 0 {
    let parent = (pos - 1) >> 1
    let current = data[parent]
    if order_of(item, current) >= 0.0 {
      break
    }
    data[pos] = current
    pos = parent
  }
  data[pos] = item
}

///|
fn Queue::pop(self : Queue) -> (Double, (Int32, Int32), (Int32, Int32)) {
  let data = self.data
  let top = data[0]
  let bottom = data.unsafe_pop()
  let n = data.length()
  if n > 0 {
    let half = n >> 1
    let mut pos = 0
    while pos < half {
      let mut best = (pos << 1) + 1
      let right = best + 1
      if right < n && order_of(data[right], data[best]) < 0.0 {
        best = right
      }
      if order_of(data[best], bottom) >= 0.0 {
        break
      }
      data[pos] = data[best]
      pos = best
    }
    data[pos] = bottom
  }
  top
}

///|
fn line_to_line(
  a : Array[(Double, Double)],
  ra : (Int32, Int32),
  b : Array[(Double, Double)],
  rb : (Int32, Int32),
  ruler : Ruler,
) -> Double {
  if !(range_safe(ra, a.length()) && range_safe(rb, b.length())) {
    return @double.infinity
  }
  let mut dist = @double.infinity
  for i in ra.0..<ra.1 {
    for j in rb.0..<rb.1 {
      if segments_cross(a[i], a[i + 1], b[j], b[j + 1]) {
        return 0.0
      }
      dist = js_min(dist, ruler.segments(a[i], a[i + 1], b[j], b[j + 1]))
    }
  }
  dist
}

///|
fn points_to_points(
  a : Array[(Double, Double)],
  ra : (Int32, Int32),
  b : Array[(Double, Double)],
  rb : (Int32, Int32),
  ruler : Ruler,
) -> Double {
  if !(range_safe(ra, a.length()) && range_safe(rb, b.length())) {
    return @double.not_a_number
  }
  let mut dist = @double.infinity
  for i in ra.0..<=ra.1 {
    for j in rb.0..<=rb.1 {
      dist = js_min(dist, ruler.distance(a[i], b[j]))
      if dist == 0.0 {
        return dist
      }
    }
  }
  dist
}

///|
fn point_to_polygon(
  p : (Double, Double),
  polygon : Array[Array[(Double, Double)]],
  ruler : Ruler,
) -> Double {
  if point_within_polygon(p, polygon, on_edge=true) {
    return 0.0
  }
  let mut dist = @double.infinity
  for ring in polygon {
    // MapLibre compares the ends by identity, which always differ.
    dist = js_min(dist, ruler.to_line(p, [ring[ring.length() - 1], ring[0]]))
    if dist == 0.0 {
      return dist
    }
    dist = js_min(dist, ruler.to_line(p, ring[:]))
    if dist == 0.0 {
      return dist
    }
  }
  dist
}

///|
fn line_to_polygon(
  line : Array[(Double, Double)],
  r : (Int32, Int32),
  polygon : Array[Array[(Double, Double)]],
  ruler : Ruler,
) -> Double {
  if !range_safe(r, line.length()) {
    return @double.not_a_number
  }
  for i in r.0..<=r.1 {
    if point_within_polygon(line[i], polygon, on_edge=true) {
      return 0.0
    }
  }
  let mut dist = @double.infinity
  for i in r.0..<r.1 {
    let (p1, p2) = (line[i], line[i + 1])
    for ring in polygon {
      let n = ring.length()
      for j in 0..<n {
        let q1 = ring[if j == 0 { n - 1 } else { j - 1 }]
        let q2 = ring[j]
        if segments_cross(p1, p2, q1, q2) {
          return 0.0
        }
        dist = js_min(dist, ruler.segments(p1, p2, q1, q2))
      }
    }
  }
  dist
}

///|
fn polygons_touch(
  a : Array[Array[(Double, Double)]],
  b : Array[Array[(Double, Double)]],
) -> Bool {
  a
  .iter()
  .any(ring => ring.iter().any(p => point_within_polygon(p, b, on_edge=true)))
}

///|
fn polygon_to_polygon(
  a : Array[Array[(Double, Double)]],
  b : Array[Array[(Double, Double)]],
  ruler : Ruler,
  current : Double,
) -> Double {
  let box_a = polygon_box(a)
  let box_b = polygon_box(b)
  if current != @double.infinity && box_distance(box_a, box_b, ruler) >= current {
    return current
  }
  if box_within_box(box_a, box_b) {
    if polygons_touch(a, b) {
      return 0.0
    }
  } else if polygons_touch(b, a) {
    return 0.0
  }
  let mut dist = @double.infinity
  for ring1 in a {
    let n1 = ring1.length()
    for i in 0..<n1 {
      let p1 = ring1[if i == 0 { n1 - 1 } else { i - 1 }]
      let p2 = ring1[i]
      for ring2 in b {
        let n2 = ring2.length()
        for j in 0..<n2 {
          let q1 = ring2[if j == 0 { n2 - 1 } else { j - 1 }]
          let q2 = ring2[j]
          if segments_cross(p1, p2, q1, q2) {
            return 0.0
          }
          dist = js_min(dist, ruler.segments(p1, p2, q1, q2))
        }
      }
    }
  }
  dist
}

///|
/// Below these many points (or line points) a range is measured directly.
const MIN_POINTS : Int32 = 100

///|
const MIN_LINE_POINTS : Int32 = 50

///|
/// MapLibre's `pointsToPolygonDistance` (divide and conquer).
fn points_to_polygon(
  points : Array[(Double, Double)],
  line : Bool,
  polygon : Array[Array[(Double, Double)]],
  ruler : Ruler,
  current : Double,
) -> Double {
  let mut min = js_min(ruler.distance(points[0], polygon[0][0]), current)
  if min == 0.0 {
    return min
  }
  let queue = Queue::{ data: [(0.0, (0, points.length() - 1), (0, 0))], }
  let poly_box = polygon_box(polygon)
  let threshold = if line { MIN_LINE_POINTS } else { MIN_POINTS }
  while queue.data.length() > 0 {
    let pair = queue.pop()
    if pair.0 >= min {
      continue
    }
    let r = pair.1
    if range_size(r) <= threshold {
      if !range_safe(r, points.length()) {
        return @double.not_a_number
      }
      if line {
        let d = line_to_polygon(points, r, polygon, ruler)
        if d.is_nan() || d == 0.0 {
          return d
        }
        min = js_min(min, d)
      } else {
        for i in r.0..<=r.1 {
          min = js_min(min, point_to_polygon(points[i], polygon, ruler))
          if min == 0.0 {
            return 0.0
          }
        }
      }
    } else {
      let (a, b) = split_range(r, line)
      for half in [a, b] {
        if half is Some(h) {
          let d = box_distance(range_box(points, h), poly_box, ruler)
          if d < min {
            queue.push((d, h, (0, 0)))
          }
        }
      }
    }
  }
  min
}

///|
/// MapLibre's `pointSetToPointSetDistance`.
fn set_to_set(
  a : Array[(Double, Double)],
  line_a : Bool,
  b : Array[(Double, Double)],
  line_b : Bool,
  ruler : Ruler,
  current : Double,
) -> Double {
  let mut min = js_min(current, ruler.distance(a[0], b[0]))
  if min == 0.0 {
    return min
  }
  let queue = Queue::{
    data: [(0.0, (0, a.length() - 1), (0, b.length() - 1))],
  }
  let threshold_a = if line_a { MIN_LINE_POINTS } else { MIN_POINTS }
  let threshold_b = if line_b { MIN_LINE_POINTS } else { MIN_POINTS }
  while queue.data.length() > 0 {
    let pair = queue.pop()
    if pair.0 >= min {
      continue
    }
    let (ra, rb) = (pair.1, pair.2)
    if range_size(ra) <= threshold_a && range_size(rb) <= threshold_b {
      if !range_safe(ra, a.length()) && range_safe(rb, b.length()) {
        return @double.not_a_number
      }
      if line_a && line_b {
        min = js_min(min, line_to_line(a, ra, b, rb, ruler))
      } else if line_a || line_b {
        let (line, rl, points, rp) = if line_a {
          (a, ra, b, rb)
        } else {
          (b, rb, a, ra)
        }
        let start = @cmp.maximum(0, @cmp.minimum(rl.0, line.length()))
        let end = @cmp.maximum(start, @cmp.minimum(rl.1 + 1, line.length()))
        let part = line[start:end]
        for i in rp.0..<=rp.1 {
          min = js_min(min, ruler.to_line(points[i], part))
          if min == 0.0 {
            return min
          }
        }
      } else {
        min = js_min(min, points_to_points(a, ra, b, rb, ruler))
      }
    } else {
      let (a0, a1) = split_range(ra, line_a)
      let (b0, b1) = split_range(rb, line_b)
      for pa in [a0, a1] {
        for pb in [b0, b1] {
          if pa is Some(x) && pb is Some(y) {
            let d = box_distance(range_box(a, x), range_box(b, y), ruler)
            if d < min {
              queue.push((d, x, y))
            }
          }
        }
      }
    }
  }
  min
}

///|
/// MapLibre's `classifyRings` (style-spec's, keeping every ring): outer rings
/// with their holes, by winding.
fn classify_rings(
  rings : Array[Array[(Double, Double)]],
) -> Array[Array[Array[(Double, Double)]]] {
  if rings.length() <= 1 {
    return [rings]
  }
  let polygons = []
  let mut polygon : Array[Array[(Double, Double)]]? = None
  let mut ccw : Bool? = None
  for ring in rings {
    let mut area = 0.0
    let n = ring.length()
    for i in 0..<n {
      let p1 = ring[i]
      let p2 = ring[if i == 0 { n - 1 } else { i - 1 }]
      area += (p2.0 - p1.0) * (p1.1 + p2.1)
    }
    if area == 0.0 {
      continue
    }
    if ccw is None {
      ccw = Some(area < 0.0)
    }
    if ccw == Some(area < 0.0) {
      if polygon is Some(p) {
        polygons.push(p)
      }
      polygon = Some([ring])
    } else if polygon is Some(p) {
      p.push(ring)
    }
  }
  if polygon is Some(p) {
    polygons.push(p)
  }
  polygons
}

///|
fn pairs(flat : Array[Double]) -> Array[(Double, Double)] {
  Array::makei(flat.length() / 2, i => (flat[i * 2], flat[i * 2 + 1]))
}

///|
/// The shortest distance in meters from `g` (a feature of `kind` "Point",
/// "LineString" or "Polygon") to `shapes`, as MapLibre's `distance`: NaN for
/// other kinds, `Failed` where it throws.
pub fn geometry_distance(
  shapes : Array[Shape],
  kind : String,
  g : TileGeometry,
  trig : @core.Trig,
) -> Value {
  guard kind is ("Point" | "LineString" | "Polygon") else {
    return Num(@double.not_a_number)
  }
  let tiles = tiles_at(g.z)
  let extent = GEOMETRY_EXTENT.to_double()
  let lng_lat = (p : (Double, Double)) => {
    let x = (p.0 / extent + g.x.to_double()) / tiles
    let y = (p.1 / extent + g.y.to_double()) / tiles
    (
      x * 360.0 - 180.0,
      360.0 / pi * (trig.atan)((trig.exp)((180.0 - y * 360.0) * pi / 180.0)) -
      90.0,
    )
  }
  let rings = g.rings((0.0, 0.0))
  if rings.length() == 0 {
    return Num(@double.not_a_number)
  }
  let mut dist = @double.infinity
  if kind == "Polygon" {
    if rings[0].length() == 0 {
      return Num(@double.not_a_number)
    }
    let polygons = classify_rings(rings).map(polygon => {
      polygon.map(ring => ring.map(lng_lat))
    })
    guard polygons.length() > 0 &&
      polygons[0].length() > 0 &&
      polygons[0][0].length() > 0 else {
      return Failed
    }
    let ruler = Ruler::new(polygons[0][0][0].1, trig)
    for shape in shapes {
      for polygon in polygons {
        let d = match shape {
          Point(x, y) =>
            points_to_polygon([(x, y)], false, polygon, ruler, dist)
          Line(c) => points_to_polygon(pairs(c), true, polygon, ruler, dist)
          Polygon(rs) => polygon_to_polygon(polygon, rs.map(pairs), ruler, dist)
          Other => dist
        }
        dist = js_min(dist, d)
        if dist == 0.0 {
          return Num(dist)
        }
      }
    }
    return Num(dist)
  }
  let positions = []
  for ring in rings {
    for p in ring {
      positions.push(lng_lat(p))
    }
  }
  guard positions.length() > 0 else { return Failed }
  let line = kind == "LineString"
  let ruler = Ruler::new(positions[0].1, trig)
  for shape in shapes {
    let d = match shape {
      Point(x, y) => set_to_set(positions, line, [(x, y)], false, ruler, dist)
      Line(c) => set_to_set(positions, line, pairs(c), true, ruler, dist)
      Polygon(rs) =>
        points_to_polygon(positions, line, rs.map(pairs), ruler, dist)
      Other => dist
    }
    dist = js_min(dist, d)
    if dist == 0.0 {
      return Num(dist)
    }
  }
  Num(dist)
}
