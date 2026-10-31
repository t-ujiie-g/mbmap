// Ported from @maplibre/geojson-vt 6.3.0: MIT License, Copyright (c) 2025
// MapLibre contributors, and ISC License, Copyright (c) 2024, Mapbox. See NOTICE.

///|
/// geojson-vt's `clip`: `set` cut to `start / scale <= v < end / scale` along x
/// (`axis` 0) or y (1), keeping features wholly inside as they are; None when
/// nothing is left.
fn clip(
  set : Array[FRef],
  scale : Double,
  start : Double,
  end : Double,
  axis : Int32,
  min_all : Double,
  max_all : Double,
) -> Array[FRef]? {
  let k1 = start / scale
  let k2 = end / scale
  if min_all >= k1 && max_all < k2 {
    return Some(set)
  }
  if max_all < k1 || min_all >= k2 {
    return None
  }
  let out = Store::new()
  let clipped = []
  for f in set {
    let s = f.s
    let min = if axis == 0 { s.min_x[f.i] } else { s.min_y[f.i] }
    let max = if axis == 0 { s.max_x[f.i] } else { s.max_y[f.i] }
    if min >= k1 && max < k2 {
      clipped.push(f)
      continue
    }
    if max < k1 || min >= k2 {
      continue
    }
    let i = match s.kind[f.i] {
      1 => clip_points(f, out, k1, k2, axis)
      kind => clip_lines(f, out, k1, k2, axis, kind == 3)
    }
    if i >= 0 {
      clipped.push({ s: out, i, })
    }
  }
  if clipped.is_empty() {
    None
  } else {
    Some(clipped)
  }
}

///|
/// Points within `k1 <= v <= k2` (inclusive, unlike lines), as a new feature
/// in `out`.
fn clip_points(
  f : FRef,
  out : Store,
  k1 : Double,
  k2 : Double,
  axis : Int32,
) -> Int32 {
  let s = f.s
  let p = start(s.part_ends, f.i)
  let r = start(s.ring_ends, p)
  for i in start(s.point_ends, r)..<s.point_ends[r] {
    let a = s.pts[i * 3 + axis]
    if a >= k1 && a <= k2 {
      out.push_point(s.pts[i * 3], s.pts[i * 3 + 1], s.pts[i * 3 + 2])
    }
  }
  out.end_ring(0.0)
  out.end_part()
  out.end_feature(1, s.row[f.i])
}

///|
/// `f`'s lines or rings cut to the range, into `out`: a line splits into
/// slices, a ring is closed again after the cut.
fn clip_lines(
  f : FRef,
  out : Store,
  k1 : Double,
  k2 : Double,
  axis : Int32,
  polygon : Bool,
) -> Int32 {
  let s = f.s
  for p in start(s.part_ends, f.i)..<s.part_ends[f.i] {
    for r in start(s.ring_ends, p)..<s.ring_ends[p] {
      clip_line(s, r, out, k1, k2, axis, polygon)
    }
    if polygon {
      out.end_part()
    }
  }
  out.end_feature(if polygon { 3 } else { 2 }, s.row[f.i])
}

///|
/// geojson-vt's `clipLine` for ring `r` of `s`, written to `out`: the slices
/// it leaves are closed as rings (polygons) or as parts of their own (lines).
fn clip_line(
  s : Store,
  r : Int32,
  out : Store,
  k1 : Double,
  k2 : Double,
  axis : Int32,
  polygon : Bool,
) -> Unit {
  let size = s.size[r]
  let first = start(s.point_ends, r)
  let last = s.point_ends[r] - 1
  let pts = s.pts
  // The slice being built starts at this point index of `out`.
  let mut slice = out.pts.length() / 3
  for i in first..<last {
    let ax = pts[i * 3]
    let ay = pts[i * 3 + 1]
    let az = pts[i * 3 + 2]
    let bx = pts[i * 3 + 3]
    let by = pts[i * 3 + 4]
    let a = if axis == 0 { ax } else { ay }
    let b = if axis == 0 { bx } else { by }
    let mut exited = false
    if a < k1 {
      // ---|-->  | (enters from the left)
      if b >= k1 {
        intersect(out, ax, ay, bx, by, k1, axis)
      }
    } else if a > k2 {
      // |  <--|--- (enters from the right)
      if b <= k2 {
        intersect(out, ax, ay, bx, by, k2, axis)
      }
    } else {
      out.push_point(ax, ay, az)
    }
    if b < k1 && a >= k1 {
      // <--|---  | (exits on the left)
      intersect(out, ax, ay, bx, by, k1, axis)
      exited = true
    }
    if b > k2 && a <= k2 {
      // |  ---|--> (exits on the right)
      intersect(out, ax, ay, bx, by, k2, axis)
      exited = true
    }
    if !polygon && exited {
      out.end_ring(size)
      out.end_part()
      slice = out.pts.length() / 3
    }
  }
  let ax = pts[last * 3]
  let ay = pts[last * 3 + 1]
  let a = if axis == 0 { ax } else { ay }
  if a >= k1 && a <= k2 {
    out.push_point(ax, ay, pts[last * 3 + 2])
  }
  // Close a cut ring whose ends no longer meet.
  let n = out.pts.length() / 3 - slice
  if polygon && n >= 2 {
    let l = (out.pts.length() / 3 - 1) * 3
    let f = slice * 3
    if out.pts[l] != out.pts[f] || out.pts[l + 1] != out.pts[f + 1] {
      out.push_point(out.pts[f], out.pts[f + 1], out.pts[f + 2])
    }
  }
  out.end_ring(size)
  if !polygon {
    out.end_part()
  }
}

///|
/// Adds the point where segment (ax, ay)-(bx, by) crosses `v` on `axis`,
/// marked important (geojson-vt's `intersectX` / `intersectY`).
fn intersect(
  out : Store,
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
  v : Double,
  axis : Int32,
) -> Unit {
  if axis == 0 {
    let t = (v - ax) / (bx - ax)
    out.push_point(v, ay + (by - ay) * t, 1.0)
  } else {
    let t = (v - ay) / (by - ay)
    out.push_point(ax + (bx - ax) * t, v, 1.0)
  }
}

///|
/// Copies of the features shifted by `offset` along x (geojson-vt's
/// `shiftFeatureCoords`).
fn shifted(set : Array[FRef], offset : Double) -> Array[FRef] {
  let out = Store::new()
  let refs = []
  for f in set {
    let s = f.s
    for p in start(s.part_ends, f.i)..<s.part_ends[f.i] {
      for r in start(s.ring_ends, p)..<s.ring_ends[p] {
        for i in start(s.point_ends, r)..<s.point_ends[r] {
          out.push_point(
            s.pts[i * 3] + offset,
            s.pts[i * 3 + 1],
            s.pts[i * 3 + 2],
          )
        }
        out.end_ring(s.size[r])
      }
      out.end_part()
    }
    let i = out.end_feature(s.kind[f.i], s.row[f.i])
    if i >= 0 {
      refs.push({ s: out, i, })
    }
  }
  refs
}

///|
/// Copies features near the antimeridian across it, so the tiles at either
/// edge show what lies past it (geojson-vt's `wrap`).
fn wrap(set : Array[FRef], buffer : Double) -> Array[FRef] {
  let left = clip(set, 1.0, -1.0 - buffer, buffer, 0, -1.0, 2.0)
  let right = clip(set, 1.0, 1.0 - buffer, 2.0 + buffer, 0, -1.0, 2.0)
  if left is None && right is None {
    return set
  }
  let mut merged = clip(set, 1.0, -buffer, 1.0 + buffer, 0, -1.0, 2.0).unwrap_or([],
  )
  if left is Some(l) {
    merged = [..shifted(l, 1.0), ..merged]
  }
  if right is Some(r) {
    merged = [..merged, ..shifted(r, -1.0)]
  }
  merged
}
