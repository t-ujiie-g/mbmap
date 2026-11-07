///|
/// Turf's `isoContours` / `getSegments`: the marching-squares segments of
/// `g` at `threshold`, appended to `out` as x0, y0, x1, y1 in matrix units.
/// False once `out` would pass `MAX_SEGMENTS` segments.
fn add_segments(g : Grid, threshold : Double, out : Array[Double]) -> Bool {
  fn frac(z0 : Double, z1 : Double) -> Double {
    if z0 == z1 {
      return 0.5
    }
    let t = (threshold - z0) / (z1 - z0)
    if t > 1.0 {
      1.0
    } else if t < 0.0 {
      0.0
    } else {
      t
    }
  }

  fn seg(ax : Double, ay : Double, bx : Double, by : Double) {
    out.push(ax)
    out.push(ay)
    out.push(bx)
    out.push(by)
  }

  for y in 0..<(g.rows - 1) {
    for x in 0..<(g.cols - 1) {
      let tr = g.at(y + 1, x + 1)
      let br = g.at(y, x + 1)
      let bl = g.at(y, x)
      let tl = g.at(y + 1, x)
      let grid = (if tl >= threshold { 8 } else { 0 }) |
        (if tr >= threshold { 4 } else { 0 }) |
        (if br >= threshold { 2 } else { 0 }) |
        (if bl >= threshold { 1 } else { 0 })
      if grid == 0 || grid == 15 {
        continue
      }
      if out.length() / 4 + 2 > MAX_SEGMENTS {
        return false
      }
      let fx = x.to_double()
      let fy = y.to_double()
      match grid {
        1 => seg(fx + frac(bl, br), fy, fx, fy + frac(bl, tl))
        2 => seg(fx + 1.0, fy + frac(br, tr), fx + frac(bl, br), fy)
        3 => seg(fx + 1.0, fy + frac(br, tr), fx, fy + frac(bl, tl))
        4 => seg(fx + frac(tl, tr), fy + 1.0, fx + 1.0, fy + frac(br, tr))
        5 => {
          let avg = (tl + tr + br + bl) / 4.0
          if avg >= threshold {
            seg(fx + frac(tl, tr), fy + 1.0, fx, fy + frac(bl, tl))
            seg(fx + frac(bl, br), fy, fx + 1.0, fy + frac(br, tr))
          } else {
            seg(fx + frac(tl, tr), fy + 1.0, fx + 1.0, fy + frac(br, tr))
            seg(fx + frac(bl, br), fy, fx, fy + frac(bl, tl))
          }
        }
        6 => seg(fx + frac(tl, tr), fy + 1.0, fx + frac(bl, br), fy)
        7 => seg(fx + frac(tl, tr), fy + 1.0, fx, fy + frac(bl, tl))
        8 => seg(fx, fy + frac(bl, tl), fx + frac(tl, tr), fy + 1.0)
        9 => seg(fx + frac(bl, br), fy, fx + frac(tl, tr), fy + 1.0)
        10 => {
          let avg = (tl + tr + br + bl) / 4.0
          if avg >= threshold {
            seg(fx, fy + frac(bl, tl), fx + frac(bl, br), fy)
            seg(fx + 1.0, fy + frac(br, tr), fx + frac(tl, tr), fy + 1.0)
          } else {
            seg(fx, fy + frac(bl, tl), fx + frac(tl, tr), fy + 1.0)
            seg(fx + 1.0, fy + frac(br, tr), fx + frac(bl, br), fy)
          }
        }
        11 => seg(fx + 1.0, fy + frac(br, tr), fx + frac(tl, tr), fy + 1.0)
        12 => seg(fx, fy + frac(bl, tl), fx + 1.0, fy + frac(br, tr))
        13 => seg(fx + frac(bl, br), fy, fx + 1.0, fy + frac(br, tr))
        _ => seg(fx, fy + frac(bl, tl), fx + frac(bl, br), fy)
      }
    }
  }
  true
}

///|
/// Segment indices by an end point, in order, with the first not yet taken.
priv struct Bucket {
  list : Array[Int32]
  mut at : Int32
}

///|
/// A point as a key for `===` on both coordinates: -0 as 0, None for NaN
/// (equal to nothing).
fn key(x : Double, y : Double) -> (Double, Double)? {
  if x.is_nan() || y.is_nan() {
    None
  } else {
    Some((x + 0.0, y + 0.0))
  }
}

///|
fn index_by(seg : Array[Double], at : Int32) -> Map[(Double, Double), Bucket] {
  let map : Map[(Double, Double), Bucket] = Map([])
  for i in 0..<(seg.length() / 4) {
    guard key(seg[i * 4 + at], seg[i * 4 + at + 1]) is Some(k) else { continue }
    match map.get(k) {
      Some(b) => b.list.push(i)
      None => map[k] = { list: [i], at: 0, }
    }
  }
  map
}

///|
/// The first segment not yet taken that has an end at (x, y), or `limit`.
fn first_at(
  map : Map[(Double, Double), Bucket],
  x : Double,
  y : Double,
  taken : FixedArray[Bool],
  limit : Int32,
) -> Int32 {
  guard key(x, y) is Some(k) && map.get(k) is Some(b) else { return limit }
  while b.at < b.list.length() && taken[b.list[b.at]] {
    b.at += 1
  }
  if b.at < b.list.length() {
    b.list[b.at]
  } else {
    limit
  }
}

///|
/// Turf's stitching of segments into contours: from the first segment left,
/// repeatedly the first one starting where the contour ends (appended) or
/// ending where it starts (prepended). Indexed by end point instead of
/// Turf's scan of the list, with the same result. Contours as flat x, y.
fn join(seg : Array[Double]) -> Array[Array[Double]] {
  let count = seg.length() / 4
  let by_start = index_by(seg, 0)
  let by_end = index_by(seg, 2)
  let taken = FixedArray::make(count, false)
  let contours = []
  let mut next = 0
  while next < count {
    if taken[next] {
      next += 1
      continue
    }
    let first = next
    taken[first] = true
    // `front` holds prepended points in reverse.
    let front = []
    let back = [
      seg[first * 4],
      seg[first * 4 + 1],
      seg[first * 4 + 2],
      seg[first * 4 + 3],
    ]
    while true {
      let (sx, sy) = if front.length() > 0 {
        (front[front.length() - 2], front[front.length() - 1])
      } else {
        (back[0], back[1])
      }
      let ex = back[back.length() - 2]
      let ey = back[back.length() - 1]
      let a = first_at(by_start, ex, ey, taken, count)
      let b = first_at(by_end, sx, sy, taken, count)
      if a == count && b == count {
        break
      }
      if a <= b {
        taken[a] = true
        back.push(seg[a * 4 + 2])
        back.push(seg[a * 4 + 3])
      } else {
        taken[b] = true
        front.push(seg[b * 4])
        front.push(seg[b * 4 + 1])
      }
    }
    let contour = Array(capacity=front.length() + back.length())
    for i = front.length() - 2; i >= 0; i = i - 2 {
      contour.push(front[i])
      contour.push(front[i + 1])
    }
    for v in back {
      contour.push(v)
    }
    contours.push(contour)
  }
  contours
}
