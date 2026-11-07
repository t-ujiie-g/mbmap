// Point in polygon follows point-in-polygon-hao 1.2.4 (MIT License, Copyright
// (c) 2021 Rowan Winsemius) as @turf/boolean-point-in-polygon 7.4.0 calls it,
// and ring areas @turf/area 7.4.0. See NOTICE.

///|
/// Most ring pairs plus edge tests `isobands` spends nesting one band's rings
/// (Turf's `groupNestedRings` is quadratic in rings).
pub const MAX_NESTING_TESTS : Int64 = 100_000_000

///|
/// Turf's mean earth radius in meters.
const EARTH_RADIUS : Double = 6371008.8

///|
const PI_OVER_180 : Double = 3.141592653589793 / 180.0

///|
/// Turf's `assembleRings`: segments joined into contours, open ones closed
/// along the grid's edges counter-clockwise, rings under 4 points dropped.
/// Rings as flat x, y with the first point repeated last. None where Turf
/// throws (a contour ending inside the grid) or loops forever (an open
/// contour that no contour, itself included, starts along the edges after).
fn assemble(seg : Array[Double], g : Grid) -> Array[Array[Double]]? {
  let contours = join(seg)
  let count = contours.length()
  let alive = FixedArray::make(count, true)
  let right = (g.cols - 1).to_double()
  let top = (g.rows - 1).to_double()
  let result = []
  let mut head = 0
  let mut corners = 0
  while head < count {
    if !alive[head] {
      head += 1
      continue
    }
    let c = contours[head]
    let n = c.length()
    if c[0] == c[n - 2] && c[1] == c[n - 1] {
      result.push(c)
      alive[head] = false
      head += 1
      corners = 0
      continue
    }
    let ex = c[n - 2]
    let ey = c[n - 1]
    // `side`: 0 left, 1 bottom, 2 right, 3 top, as Turf tests them.
    let side = if ex == 0.0 && ey != 0.0 {
      0
    } else if ey == 0.0 && ex != right {
      1
    } else if ex == right && ey != top {
      2
    } else if ey == top && ex != 0.0 {
      3
    } else {
      return None
    }
    let mut found = -1
    for j in head..<count {
      if !alive[j] {
        continue
      }
      let sx = contours[j][0]
      let sy = contours[j][1]
      let hit = match side {
        0 => sx == 0.0 && sy < ey
        1 => sy == 0.0 && sx > ex
        2 => sx == right && sy > ey
        _ => sy == top && sx < ex
      }
      guard hit else { continue }
      if found == -1 {
        found = j
        continue
      }
      let mx = contours[found][0]
      let my = contours[found][1]
      let order = match side {
        0 => sy - my
        1 => mx - sx
        2 => my - sy
        _ => sx - mx
      }
      if order > 0.0 {
        found = j
      }
    }
    if found == -1 {
      corners += 1
      if corners > 4 {
        return None
      }
      let (x, y) = match side {
        0 => (0.0, 0.0)
        1 => (right, 0.0)
        2 => (right, top)
        _ => (0.0, top)
      }
      c.push(x)
      c.push(y)
    } else if found == head {
      c.push(c[0])
      c.push(c[1])
      result.push(c)
      alive[head] = false
      head += 1
      corners = 0
    } else {
      alive[found] = false
      for v in contours[found] {
        c.push(v)
      }
      corners = 0
    }
  }
  Some(result.filter(r => r.length() >= 8))
}

///|
/// @turf/area's `ringArea` (signed, square meters) of a closed flat ring.
fn ring_area(r : Array[Double], trig : Trig) -> Double {
  let len = r.length() / 2 - 1
  if len <= 2 {
    return 0.0
  }
  let mut total = 0.0
  for i in 0..<len {
    let middle = if i + 1 == len { 0 } else { i + 1 }
    let upper = if i + 2 >= len { (i + 2) % len } else { i + 2 }
    let lower_x = r[i * 2] * PI_OVER_180
    let middle_y = r[middle * 2 + 1] * PI_OVER_180
    let upper_x = r[upper * 2] * PI_OVER_180
    total += (upper_x - lower_x) * trig.sin(middle_y)
  }
  total * (EARTH_RADIUS * EARTH_RADIUS / 2.0)
}

///|
/// point-in-polygon-hao on one closed flat ring: 0 on its boundary, 1 inside,
/// -1 outside.
fn in_ring(r : Array[Double], x : Double, y : Double) -> Int32 {
  let mut k = 0
  let mut u1 = r[0] - x
  let mut v1 = r[1] - y
  for i in 1..<(r.length() / 2) {
    let u2 = r[i * 2] - x
    let v2 = r[i * 2 + 1] - y
    if v1 == 0.0 && v2 == 0.0 {
      if (u2 <= 0.0 && u1 >= 0.0) || (u1 <= 0.0 && u2 >= 0.0) {
        return 0
      }
    } else if (v2 >= 0.0 && v1 <= 0.0) || (v2 <= 0.0 && v1 >= 0.0) {
      let f = @robust.orient2d(u1, u2, v1, v2, 0.0, 0.0)
      if f == 0.0 {
        return 0
      }
      if (f > 0.0 && v2 > 0.0 && v1 <= 0.0) ||
        (f < 0.0 && v2 <= 0.0 && v1 > 0.0) {
        k += 1
      }
    }
    u1 = u2
    v1 = v2
  }
  if k % 2 == 0 {
    -1
  } else {
    1
  }
}

///|
/// A ring's bounding box: min x, min y, max x, max y.
fn ring_box(r : Array[Double]) -> (Double, Double, Double, Double) {
  let mut x0 = r[0]
  let mut y0 = r[1]
  let mut x1 = r[0]
  let mut y1 = r[1]
  for i in 1..<(r.length() / 2) {
    x0 = if r[i * 2] < x0 { r[i * 2] } else { x0 }
    x1 = if r[i * 2] > x1 { r[i * 2] } else { x1 }
    y0 = if r[i * 2 + 1] < y0 { r[i * 2 + 1] } else { y0 }
    y1 = if r[i * 2 + 1] > y1 { r[i * 2 + 1] } else { y1 }
  }
  (x0, y0, x1, y1)
}

///|
/// Turf's `orderByArea` and `groupNestedRings`: rings by decreasing area
/// (stable), then each ring not yet grouped starts a polygon taking every
/// later ungrouped ring all of whose points are in or on it and in or on none
/// of the polygon's holes so far. A ring reaching out of another's bounding
/// box is not inside it, which skips Turf's point tests with the same answer.
/// None past `MAX_NESTING_TESTS`.
fn nest(rings : Array[Array[Double]], trig : Trig) -> Array[Array[Int32]]? {
  let count = rings.length()
  let areas = rings.map(r => ring_area(r, trig).abs())
  let order = Array::makei(count, i => i)
  order.sort_by((a, b) => {
    if areas[a] > areas[b] {
      -1
    } else if areas[a] < areas[b] {
      1
    } else {
      a - b
    }
  })
  let boxes = order.map(i => ring_box(rings[i]))
  let mut tests = 0L
  fn inside(j : Int32, i : Int32) -> Bool {
    tests += 1L
    let (ax0, ay0, ax1, ay1) = boxes[j]
    let (bx0, by0, bx1, by1) = boxes[i]
    if ax0 < bx0 || ay0 < by0 || ax1 > bx1 || ay1 > by1 {
      return false
    }
    let a = rings[order[j]]
    let b = rings[order[i]]
    for p in 0..<(a.length() / 2) {
      tests += (b.length() / 2).to_int64()
      if in_ring(b, a[p * 2], a[p * 2 + 1]) < 0 {
        return false
      }
    }
    true
  }

  let grouped = FixedArray::make(count, false)
  let polygons = []
  for i in 0..<count {
    if grouped[i] {
      continue
    }
    let group = [i]
    grouped[i] = true
    for j in (i + 1)..<count {
      if grouped[j] || !inside(j, i) {
        continue
      }
      let mut in_hole = false
      for k in 1..<group.length() {
        if inside(j, group[k]) {
          in_hole = true
          break
        }
      }
      if tests > MAX_NESTING_TESTS {
        return None
      }
      if !in_hole {
        group.push(j)
        grouped[j] = true
      }
    }
    polygons.push(group.map(k => order[k]))
  }
  Some(polygons)
}

///|
/// Turf's `isobands(grid, breaks, { zProperty })` over the table's Point rows
/// and their `z_property` values (read as `isolines` reads them): a
/// MultiPolygon row per pair of consecutive breaks, with `z_property` set to
/// Turf's label `lower + "-" + upper` (numbers by `number_text`, JavaScript's
/// `String(x)` by default). Rings, their order, starts and nesting are Turf's,
/// nested in matrix units, where Turf measures ring areas on the sphere as if
/// they were degrees (`trig`). A band meeting no cell has no geometry unless
/// the grid's first value lies in it, which gives Turf's whole-grid rectangle.
/// None where `isolines` gives None, where Turf throws (a contour ending inside
/// the grid) or never returns, and past `MAX_NESTING_TESTS`.
pub fn isobands(
  t : @geom.Table,
  breaks : Array[Double],
  z_property : String,
  trig~ : Trig = Trig::moonbit(),
  number_text~ : (Double) -> String = Double::to_string,
) -> @geom.Table? {
  guard breaks_ok(breaks) && grid_of(t, z_property) is Some(g) else {
    return None
  }
  guard work_ok(g, breaks.length()) else { return None }
  let (scale_x, scale_y) = g.scale()
  let b = @geom.TableBuilder::new()
  let mut total = 0
  let mut prev = []
  for i in 1..<breaks.length() {
    if i == 1 {
      guard add_segments(g, breaks[0], prev) else { return None }
      total += prev.length() / 4
    }
    let upper = breaks[i]
    let lower = breaks[i - 1]
    let current = []
    guard add_segments(g, upper, current) else { return None }
    total += current.length() / 4
    if total > MAX_SEGMENTS {
      return None
    }
    let seg = Array(capacity=prev.length() + current.length())
    for v in prev {
      seg.push(v)
    }
    for s in 0..<(current.length() / 4) {
      seg.push(current[s * 4 + 2])
      seg.push(current[s * 4 + 3])
      seg.push(current[s * 4])
      seg.push(current[s * 4 + 1])
    }
    guard assemble(seg, g) is Some(rings) else { return None }
    guard nest(rings, trig) is Some(polygons) else { return None }
    let first = g.at(0, 0)
    if polygons.length() == 0 && first < upper && first >= lower {
      let right = (g.cols - 1).to_double()
      let top = (g.rows - 1).to_double()
      rings.push([0.0, 0.0, right, 0.0, right, top, 0.0, top, 0.0, 0.0])
      polygons.push([rings.length() - 1])
    }
    for polygon in polygons {
      for r in polygon {
        let ring = rings[r]
        for k = 0; k < ring.length(); k = k + 2 {
          b.point(ring[k] * scale_x + g.min_x, ring[k + 1] * scale_y + g.min_y)
        }
        b.end_ring()
      }
      b.end_part()
    }
    b.prop(z_property, Str(number_text(lower) + "-" + number_text(upper)))
    b.end_feature(MultiPolygon)
    prev = current
  }
  Some(b.finish())
}
