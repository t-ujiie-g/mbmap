// Ported from @maplibre/geojson-vt 6.3.0: MIT License, Copyright (c) 2025
// MapLibre contributors, and ISC License, Copyright (c) 2024, Mapbox. See NOTICE.

///|
/// geojson-vt's `clip`: `set` cut to `start / scale <= v < end / scale` along x
/// (`axis` 0) or y (1), keeping features wholly inside as they are; None when
/// nothing is left. With line `metrics`, each slice of a line is a feature.
fn clip(
  set : Array[FRef],
  scale : Double,
  start : Double,
  end : Double,
  axis : Int32,
  min_all : Double,
  max_all : Double,
  metrics~ : Bool = false,
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
    match s.kind[f.i] {
      1 => {
        let i = clip_points(f, out, k1, k2, axis)
        if i >= 0 {
          clipped.push({ s: out, i, })
        }
      }
      2 if metrics =>
        for i in clip_slices(f, out, k1, k2, axis) {
          clipped.push({ s: out, i, })
        }
      kind => {
        let i = clip_lines(f, out, k1, k2, axis, kind == 3)
        if i >= 0 {
          clipped.push({ s: out, i, })
        }
      }
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
/// A line's slices cut to the range as features of their own, each with where
/// it lies along the line (geojson-vt's `clipLine` tracking metrics).
fn clip_slices(
  f : FRef,
  out : Store,
  k1 : Double,
  k2 : Double,
  axis : Int32,
) -> Array[Int32] {
  let s = f.s
  let row = s.row[f.i]
  let found = []
  for p in start(s.part_ends, f.i)..<s.part_ends[f.i] {
    for r in start(s.ring_ends, p)..<s.ring_ends[p] {
      clip_line(s, r, out, k1, k2, axis, false, sliced=() => {
        let i = out.end_feature(2, row)
        if i >= 0 {
          found.push(i)
        }
      })
    }
  }
  found
}

///|
/// geojson-vt's `clipLine` for ring `r` of `s`, written to `out`: the slices
/// it leaves are closed as rings (polygons) or as parts of their own (lines),
/// each then handed to `sliced` with where it lies along the line.
fn clip_line(
  s : Store,
  r : Int32,
  out : Store,
  k1 : Double,
  k2 : Double,
  axis : Int32,
  polygon : Bool,
  sliced? : () -> Unit,
) -> Unit {
  let metrics = sliced is Some(_)
  let size = s.size[r]
  let mut from = s.from[r]
  let mut to = s.to[r]
  let mut len = from
  let mut t = 0.0
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
    let seg = if metrics {
      ((ax - bx) * (ax - bx) + (ay - by) * (ay - by)).sqrt()
    } else {
      0.0
    }
    if a < k1 {
      // ---|-->  | (enters from the left)
      if b >= k1 {
        t = intersect(out, ax, ay, bx, by, k1, axis)
        from = len + seg * t
      }
    } else if a > k2 {
      // |  <--|--- (enters from the right)
      if b <= k2 {
        t = intersect(out, ax, ay, bx, by, k2, axis)
        from = len + seg * t
      }
    } else {
      out.push_point(ax, ay, az)
    }
    if b < k1 && a >= k1 {
      // <--|---  | (exits on the left)
      t = intersect(out, ax, ay, bx, by, k1, axis)
      exited = true
    }
    if b > k2 && a <= k2 {
      // |  ---|--> (exits on the right)
      t = intersect(out, ax, ay, bx, by, k2, axis)
      exited = true
    }
    if !polygon && exited {
      if metrics {
        to = len + seg * t
      }
      out.end_ring(size, from~, to~)
      out.end_part()
      if sliced is Some(f) {
        f()
      }
      // A new slice starts with the line's own range (geojson-vt's `newSlice`).
      from = s.from[r]
      to = s.to[r]
      slice = out.pts.length() / 3
    }
    len += seg
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
  let open = out.open_points() > 0
  out.end_ring(size, from~, to~)
  if !polygon {
    out.end_part()
    if open && sliced is Some(f) {
      f()
    }
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
) -> Double {
  if axis == 0 {
    let t = (v - ax) / (bx - ax)
    out.push_point(v, ay + (by - ay) * t, 1.0)
    t
  } else {
    let t = (v - ay) / (by - ay)
    out.push_point(ax + (bx - ax) * t, v, 1.0)
    t
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
        out.end_ring(s.size[r], from=s.from[r], to=s.to[r])
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
fn wrap(
  set : Array[FRef],
  buffer : Double,
  metrics~ : Bool = false,
) -> Array[FRef] {
  let left = clip(set, 1.0, -1.0 - buffer, buffer, 0, -1.0, 2.0, metrics~)
  let right = clip(set, 1.0, 1.0 - buffer, 2.0 + buffer, 0, -1.0, 2.0, metrics~)
  if left is None && right is None {
    return set
  }
  let mut merged = clip(set, 1.0, -buffer, 1.0 + buffer, 0, -1.0, 2.0, metrics~).unwrap_or([],
  )
  if left is Some(l) {
    merged = [..shifted(l, 1.0), ..merged]
  }
  if right is Some(r) {
    merged = [..merged, ..shifted(r, -1.0)]
  }
  merged
}
