// Ported from @maplibre/geojson-vt 6.3.0: MIT License, Copyright (c) 2025
// MapLibre contributors, and ISC License, Copyright (c) 2024, Mapbox. See NOTICE.

///|
/// Longitude to world x in [0, 1].
fn project_x(lng : Double) -> Double {
  lng / 360.0 + 0.5
}

///|
/// The projection's sine and logarithm. A wasm-gc build passes the host's
/// `Math.sin`/`Math.log` to match geojson-vt bit for bit; `@math` differs in
/// the last bit now and then.
pub(all) struct Trig {
  sin : (Double) -> Double
  ln : (Double) -> Double
}

///|
pub fn Trig::moonbit() -> Trig {
  { sin: @math.sin, ln: @math.ln, }
}

///|
/// Latitude to world y in [0, 1] (spherical mercator, clamped).
fn project_y(trig : Trig, lat : Double) -> Double {
  let s = (trig.sin)(lat * @math.PI / 180.0)
  let y = 0.5 - 0.25 * (trig.ln)((1.0 + s) / (1.0 - s)) / @math.PI
  if y < 0.0 {
    0.0
  } else if y > 1.0 {
    1.0
  } else {
    y
  }
}

///|
/// Projects the table's features into `store` with simplification data
/// (geojson-vt's `convertToInternal`) and returns their indices.
fn convert(
  table : @geom.Table,
  sq_tolerance : Double,
  trig : Trig,
) -> Array[FRef] {
  let store = Store::new()
  let out = []
  for f in 0..<table.length() {
    let kind = match table.kinds[f] {
      Point | MultiPoint => 1
      LineString | MultiLineString => 2
      Polygon | MultiPolygon => 3
      NoGeometry => continue
    }
    let (p0, p1) = table.parts(f)
    for p in p0..<p1 {
      let (r0, r1) = table.rings(p)
      for r in r0..<r1 {
        let (a, b) = table.points(r)
        if kind == 1 {
          for i in a..<b {
            store.push_point(
              project_x(table.coords[i * 2]),
              project_y(trig, table.coords[i * 2 + 1]),
              0.0,
            )
          }
          continue
        }
        convert_line(store, table.coords, a, b, sq_tolerance, kind == 3, trig)
      }
      if kind != 1 {
        store.end_part()
      }
    }
    if kind == 1 {
      store.end_ring(0.0)
      store.end_part()
    }
    let i = store.end_feature(kind, f)
    if i >= 0 {
      out.push({ s: store, i, })
    }
  }
  out
}

///|
/// One ring or line (geojson-vt's `convertLine`): projected points, the ends
/// marked important, the rest ranked by Douglas-Peucker, and its size.
fn convert_line(
  store : Store,
  coords : Array[Double],
  a : Int32,
  b : Int32,
  sq_tolerance : Double,
  polygon : Bool,
  trig : Trig,
) -> Unit {
  let first = store.pts.length()
  let mut size = 0.0
  let mut x0 = 0.0
  let mut y0 = 0.0
  for j in a..<b {
    let x = project_x(coords[j * 2])
    let y = project_y(trig, coords[j * 2 + 1])
    store.push_point(x, y, 0.0)
    if j > a {
      size += if polygon {
        (x0 * y - x * y0) / 2.0
      } else {
        ((x - x0) * (x - x0) + (y - y0) * (y - y0)).sqrt()
      }
    }
    x0 = x
    y0 = y
  }
  let last = store.pts.length() - 3
  store.pts[first + 2] = 1.0
  if sq_tolerance > 0.0 {
    simplify(store.pts, first, last, sq_tolerance)
  }
  store.pts[last + 2] = 1.0
  store.end_ring(size.abs())
}

///|
/// Ranks the points between `first` and `last` (indices of x in `coords`,
/// stride 3) by Douglas-Peucker: a point's z becomes the squared distance
/// at which it would be dropped (geojson-vt's `simplify`).
fn simplify(
  coords : Array[Double],
  first : Int32,
  last : Int32,
  sq_tolerance : Double,
) -> Unit {
  let stack = [first, last]
  while stack.pop() is Some(l) {
    let f = stack.pop().unwrap()
    let mut max = sq_tolerance
    let mid = f + ((l - f) >> 1)
    let mut min_pos_to_mid = l - f
    let mut index = -1
    let ax = coords[f]
    let ay = coords[f + 1]
    let bx = coords[l]
    let by = coords[l + 1]
    let mut i = f + 3
    while i < l {
      let d = sq_seg_dist(coords[i], coords[i + 1], ax, ay, bx, by)
      if d > max {
        index = i
        max = d
      } else if d == max {
        // Prefer a pivot near the middle on ties, for shallower recursion
        // on degenerate input (geojson-vt issue #104).
        let pos_to_mid = (i - mid).abs()
        if pos_to_mid < min_pos_to_mid {
          index = i
          min_pos_to_mid = pos_to_mid
        }
      }
      i += 3
    }
    if max > sq_tolerance {
      coords[index + 2] = max
      if index - f > 3 {
        stack.push(f)
        stack.push(index)
      }
      if l - index > 3 {
        stack.push(index)
        stack.push(l)
      }
    }
  }
}

///|
/// Squared distance from (px, py) to the segment (x, y)-(bx, by).
fn sq_seg_dist(
  px : Double,
  py : Double,
  x : Double,
  y : Double,
  bx : Double,
  by : Double,
) -> Double {
  let mut x = x
  let mut y = y
  let mut dx = bx - x
  let mut dy = by - y
  if dx != 0.0 || dy != 0.0 {
    let t = ((px - x) * dx + (py - y) * dy) / (dx * dx + dy * dy)
    if t > 1.0 {
      x = bx
      y = by
    } else if t > 0.0 {
      x += dx * t
      y += dy * t
    }
  }
  dx = px - x
  dy = py - y
  dx * dx + dy * dy
}
