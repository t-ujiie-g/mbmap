// Ports @turf/nearest-point-on-line and @turf/line-slice 7.4.0 (MIT License,
// Copyright (c) 2017 TurfJS). See NOTICE.

///|
/// Doubles per row of `nearest_point_on_line`.
pub const NEAREST_WORDS : Int32 = 6

///|
/// What `nearestPointOnLine` gives (`dist`, `location` in km); without a segment
/// Turf's start value: infinite point and `dist`, -1 elsewhere.
priv struct Nearest {
  mut lng : Double
  mut lat : Double
  mut dist : Double
  mut location : Double
  mut index : Int32
  mut line : Int32
}

///|
/// Whether `nearestPointOnLine` takes row `f`: a line or multi-line whose
/// segments have no NaN coordinates (Turf's `point()` throws on those).
fn accepts_line(t : @geom.Table, f : Int32) -> Bool {
  guard t.kinds[f] is (LineString | MultiLineString) else { return false }
  let (p0, p1) = t.parts(f)
  for p in p0..<p1 {
    let (r0, r1) = t.rings(p)
    for r in r0..<r1 {
      let (i0, i1) = t.points(r)
      if i1 - i0 >= 2 {
        for i in (i0 * 2)..<(i1 * 2) {
          if t.coords[i].is_nan() {
            return false
          }
        }
      }
    }
  }
  true
}

///|
/// `nearestPointOnLine(feature f, point([x, y]))` for an accepted row.
fn nearest_in(
  t : @geom.Table,
  f : Int32,
  x : Double,
  y : Double,
  trig : Trig,
) -> Nearest {
  let best = {
    lng: @double.infinity,
    lat: @double.infinity,
    dist: @double.infinity,
    location: -1.0,
    index: -1,
    line: -1,
  }
  let c = t.coords
  let mut total = 0.0
  let (p0, p1) = t.parts(f)
  for p in p0..<p1 {
    let (r0, r1) = t.rings(p)
    for r in r0..<r1 {
      let (i0, i1) = t.points(r)
      for k in i0..<(i1 - 1) {
        let ax = c[k * 2]
        let ay = c[k * 2 + 1]
        let bx = c[k * 2 + 2]
        let by = c[k * 2 + 3]
        let segment_length = distance(trig, ax, ay, bx, by)
        let (px, py, was_end) = if bx == x && by == y {
          (bx, by, true)
        } else if ax == x && ay == y {
          (ax, ay, false)
        } else {
          nearest_on_segment(trig, ax, ay, bx, by, x, y)
        }
        let point_distance = distance(trig, x, y, px, py)
        if point_distance < best.dist {
          best.lng = px
          best.lat = py
          best.dist = point_distance
          best.location = total + distance(trig, ax, ay, px, py)
          best.index = if was_end { k - i0 + 1 } else { k - i0 }
          best.line = p - p0
        }
        total += segment_length
      }
    }
  }
  best
}

///|
/// Per row, Turf's `nearestPointOnLine(row, point([x, y]))` as `NEAREST_WORDS`
/// doubles (lng, lat, `dist`, `location`, `index`, `multiFeatureIndex`); all NaN
/// where Turf rejects the row (not a line, NaN coordinates) or `x`, `y`.
pub fn nearest_point_on_line(
  t : @geom.Table,
  x : Double,
  y : Double,
  trig~ : Trig = Trig::moonbit(),
) -> FixedArray[Double] {
  let n = t.length()
  let out = FixedArray::make(n * NEAREST_WORDS, @double.not_a_number)
  if x.is_nan() || y.is_nan() {
    return out
  }
  for f in 0..<n {
    guard accepts_line(t, f) else { continue }
    let m = nearest_in(t, f, x, y, trig)
    let o = f * NEAREST_WORDS
    out[o] = m.lng
    out[o + 1] = m.lat
    out[o + 2] = m.dist
    out[o + 3] = m.location
    out[o + 4] = m.index.to_double()
    out[o + 5] = m.line.to_double()
  }
  out
}

///|
fn copy_props(b : @geom.TableBuilder, t : @geom.Table, f : Int32) -> Unit {
  for c in t.columns {
    if c.values[f] is Some(v) {
      b.prop(c.name, v)
    }
  }
}

///|
/// Per row, Turf's `lineSlice(start, stop, row)` as a LineString with the row's
/// id and properties; rows Turf rejects (not a LineString, NaN coordinates or
/// ends) keep them with no geometry.
pub fn line_slice(
  t : @geom.Table,
  start_x : Double,
  start_y : Double,
  stop_x : Double,
  stop_y : Double,
  trig~ : Trig = Trig::moonbit(),
) -> @geom.Table {
  let b = @geom.TableBuilder::new()
  let ends_ok = !(start_x.is_nan() ||
    start_y.is_nan() ||
    stop_x.is_nan() ||
    stop_y.is_nan())
  for f in 0..<t.length() {
    if ends_ok && t.kinds[f] is LineString && accepts_line(t, f) {
      let start = nearest_in(t, f, start_x, start_y, trig)
      let stop = nearest_in(t, f, stop_x, stop_y, trig)
      let (i0, i1) = t.points(t.rings(t.parts(f).0).0)
      let last = i1 - i0 - 2
      if start.index > last {
        start.index = last
      }
      if stop.index > last {
        stop.index = last
      }
      let (first, second) = if start.index <= stop.index {
        (start, stop)
      } else {
        (stop, start)
      }
      b.point(first.lng, first.lat)
      for i in (first.index + 1)..<(second.index + 1) {
        b.point(t.coords[(i0 + i) * 2], t.coords[(i0 + i) * 2 + 1])
      }
      b.point(second.lng, second.lat)
      b.end_ring()
      b.end_part()
    }
    copy_props(b, t, f)
    b.end_feature(LineString, id=t.ids[f])
  }
  b.finish()
}
