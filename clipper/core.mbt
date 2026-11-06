// Ports Clipper2 2.0.1 (CPP/Clipper2Lib/include/clipper2/clipper.core.h, commit
// 642390d), Boost Software License 1.0, Copyright (c) Angus Johnson 2010-2026.
// See NOTICE.

///|
/// A point with integer coordinates (Clipper2's `Point64`).
#derive(Debug, Eq)
pub(all) struct Point64 {
  x : Int64
  y : Int64
}

///|
/// Which regions of a set of paths count as filled (Clipper2's `FillRule`).
#derive(Debug, Eq)
pub(all) enum FillRule {
  EvenOdd
  NonZero
  Positive
  Negative
}

///|
/// A boolean operation (Clipper2's `ClipType`; all but `Difference` commute).
#derive(Debug, Eq)
pub(all) enum ClipType {
  NoClip
  Intersection
  Union
  Difference
  Xor
}

///|
/// Largest coordinate Clipper2 accepts (`INT64_MAX >> 2`).
pub const MAX_COORD : Int64 = 2305843009213693951L

///|
/// `x` rounded to the nearest integer, ties to even (C's `nearbyint` in the
/// default rounding mode).
fn nearbyint(x : Double) -> Int64 {
  let f = x.floor()
  let d = x - f
  let r = if d < 0.5 {
    f
  } else if d > 0.5 {
    f + 1.0
  } else if f % 2.0 == 0.0 {
    f
  } else {
    f + 1.0
  }
  r.to_int64()
}

///|
fn tri_sign(x : Int64) -> Int32 {
  if x > 0L {
    1
  } else if x < 0L {
    -1
  } else {
    0
  }
}

///|
/// `a * b` of two unsigned 64-bit values as (low, high) halves (`MultiplyUInt64`).
fn multiply_u64(a : UInt64, b : UInt64) -> (UInt64, UInt64) {
  let mask = 0xFFFFFFFFUL
  let x1 = (a & mask) * (b & mask)
  let x2 = (a >> 32) * (b & mask) + (x1 >> 32)
  let x3 = (a & mask) * (b >> 32) + (x2 & mask)
  (
    ((x3 & mask) << 32) | (x1 & mask),
    (a >> 32) * (b >> 32) + (x2 >> 32) + (x3 >> 32),
  )
}

///|
fn abs_u64(v : Int64) -> UInt64 {
  (if v < 0L { -v } else { v }).reinterpret_as_uint64()
}

///|
/// Whether `a * b == c * d` exactly (`ProductsAreEqual`).
fn products_are_equal(a : Int64, b : Int64, c : Int64, d : Int64) -> Bool {
  let ab = multiply_u64(abs_u64(a), abs_u64(b))
  let cd = multiply_u64(abs_u64(c), abs_u64(d))
  ab == cd && tri_sign(a) * tri_sign(b) == tri_sign(c) * tri_sign(d)
}

///|
/// The sign of the cross product of (pt2 - pt1) and (pt3 - pt2), exactly
/// (`CrossProductSign`).
fn cross_product_sign(pt1 : Point64, pt2 : Point64, pt3 : Point64) -> Int32 {
  let a = pt2.x - pt1.x
  let b = pt3.y - pt2.y
  let c = pt2.y - pt1.y
  let d = pt3.x - pt2.x
  let ab = multiply_u64(abs_u64(a), abs_u64(b))
  let cd = multiply_u64(abs_u64(c), abs_u64(d))
  let sign_ab = tri_sign(a) * tri_sign(b)
  let sign_cd = tri_sign(c) * tri_sign(d)
  if sign_ab == sign_cd {
    let result = if ab.1 == cd.1 {
      if ab.0 == cd.0 {
        return 0
      }
      if ab.0 > cd.0 {
        1
      } else {
        -1
      }
    } else if ab.1 > cd.1 {
      1
    } else {
      -1
    }
    if sign_ab > 0 {
      result
    } else {
      -result
    }
  } else if sign_ab > sign_cd {
    1
  } else {
    -1
  }
}

///|
fn is_collinear(pt1 : Point64, shared : Point64, pt2 : Point64) -> Bool {
  products_are_equal(
    shared.x - pt1.x,
    pt2.y - shared.y,
    shared.y - pt1.y,
    pt2.x - shared.x,
  )
}

///|
fn dot_product(pt1 : Point64, pt2 : Point64, pt3 : Point64) -> Double {
  (pt2.x - pt1.x).to_double() * (pt3.x - pt2.x).to_double() +
  (pt2.y - pt1.y).to_double() * (pt3.y - pt2.y).to_double()
}

///|
fn sqr(v : Double) -> Double {
  v * v
}

///|
fn perpendic_dist_from_line_sqrd(
  pt : Point64,
  line1 : Point64,
  line2 : Point64,
) -> Double {
  let a = (pt.x - line1.x).to_double()
  let b = (pt.y - line1.y).to_double()
  let c = (line2.x - line1.x).to_double()
  let d = (line2.y - line1.y).to_double()
  if c == 0.0 && d == 0.0 {
    return 0.0
  }
  sqr(a * d - c * b) / (c * c + d * d)
}

///|
/// A path's signed area, positive for counter-clockwise paths in a y-up frame
/// (`Area`).
pub fn area(path : ArrayView[Point64]) -> Double {
  let cnt = path.length()
  if cnt < 3 {
    return 0.0
  }
  let mut a = 0.0
  let mut i2 = cnt - 1
  let stop = if cnt % 2 == 0 { cnt } else { cnt - 1 }
  let mut i1 = 0
  while i1 != stop {
    a += (path[i2].y + path[i1].y).to_double() *
      (path[i2].x - path[i1].x).to_double()
    i2 = i1 + 1
    a += (path[i1].y + path[i2].y).to_double() *
      (path[i1].x - path[i2].x).to_double()
    i1 += 2
  }
  if cnt % 2 == 1 {
    a += (path[i2].y + path[i1].y).to_double() *
      (path[i2].x - path[i1].x).to_double()
  }
  a * 0.5
}

///|
/// Where the lines through `ln1a`-`ln1b` and `ln2a`-`ln2b` cross, kept within
/// the first segment; None when they are parallel (`GetLineIntersectPt`).
fn get_line_intersect_pt(
  ln1a : Point64,
  ln1b : Point64,
  ln2a : Point64,
  ln2b : Point64,
) -> Point64? {
  let dx1 = (ln1b.x - ln1a.x).to_double()
  let dy1 = (ln1b.y - ln1a.y).to_double()
  let dx2 = (ln2b.x - ln2a.x).to_double()
  let dy2 = (ln2b.y - ln2a.y).to_double()
  let det = dy1 * dx2 - dy2 * dx1
  if det == 0.0 {
    return None
  }
  let t = (
      (ln1a.x - ln2a.x).to_double() * dy2 - (ln1a.y - ln2a.y).to_double() * dx2
    ) /
    det
  if t <= 0.0 {
    Some(ln1a)
  } else if t >= 1.0 {
    Some(ln1b)
  } else {
    Some({
      x: (ln1a.x.to_double() + t * dx1).to_int64(),
      y: (ln1a.y.to_double() + t * dy1).to_int64(),
    })
  }
}

///|
/// Whether two segments cross, touching ends excluded unless `inclusive`
/// (`SegmentsIntersect`).
fn segments_intersect(
  seg1a : Point64,
  seg1b : Point64,
  seg2a : Point64,
  seg2b : Point64,
  inclusive~ : Bool = false,
) -> Bool {
  let dy1 = (seg1b.y - seg1a.y).to_double()
  let dx1 = (seg1b.x - seg1a.x).to_double()
  let dy2 = (seg2b.y - seg2a.y).to_double()
  let dx2 = (seg2b.x - seg2a.x).to_double()
  let cp = dy1 * dx2 - dy2 * dx1
  if cp == 0.0 {
    return false
  }
  let ax = (seg1a.x - seg2a.x).to_double()
  let ay = (seg1a.y - seg2a.y).to_double()
  if inclusive {
    let t = ax * dy2 - ay * dx2
    if t == 0.0 {
      return true
    }
    if t > 0.0 {
      if cp < 0.0 || t > cp {
        return false
      }
    } else if cp > 0.0 || t < cp {
      return false
    }
    let t = ax * dy1 - ay * dx1
    if t == 0.0 {
      return true
    }
    if t > 0.0 {
      cp > 0.0 && t <= cp
    } else {
      cp < 0.0 && t >= cp
    }
  } else {
    let t = ax * dy2 - ay * dx2
    if t == 0.0 {
      return false
    }
    if t > 0.0 {
      if cp < 0.0 || t >= cp {
        return false
      }
    } else if cp > 0.0 || t <= cp {
      return false
    }
    let t = ax * dy1 - ay * dx1
    if t == 0.0 {
      return false
    }
    if t > 0.0 {
      cp > 0.0 && t < cp
    } else {
      cp < 0.0 && t > cp
    }
  }
}

///|
fn get_closest_point_on_segment(
  off : Point64,
  seg1 : Point64,
  seg2 : Point64,
) -> Point64 {
  if seg1.x == seg2.x && seg1.y == seg2.y {
    return seg1
  }
  let dx = (seg2.x - seg1.x).to_double()
  let dy = (seg2.y - seg1.y).to_double()
  let q = (
      (off.x - seg1.x).to_double() * dx + (off.y - seg1.y).to_double() * dy
    ) /
    (sqr(dx) + sqr(dy))
  let q = if q < 0.0 { 0.0 } else if q > 1.0 { 1.0 } else { q }
  { x: seg1.x + nearbyint(q * dx), y: seg1.y + nearbyint(q * dy), }
}

///|
/// Where a point lies relative to a polygon (`PointInPolygonResult`).
#derive(Debug, Eq)
pub(all) enum PointInPolygonResult {
  IsOn
  IsInside
  IsOutside
}

///|
/// Whether `pt` is on, inside or outside `polygon` (`PointInPolygon`).
pub fn point_in_polygon(
  pt : Point64,
  polygon : ArrayView[Point64],
) -> PointInPolygonResult {
  let len = polygon.length()
  if len < 3 {
    return IsOutside
  }
  let mut val = 0
  let mut first = 0
  while first != len && polygon[first].y == pt.y {
    first += 1
  }
  if first == len {
    return IsOutside
  }
  let mut cend = len
  let mut is_above = polygon[first].y < pt.y
  let starting_above = is_above
  let mut curr = first + 1
  let mut prev = 0
  while true {
    if curr == cend {
      if cend == first || first == 0 {
        break
      }
      cend = first
      curr = 0
    }
    if is_above {
      while curr != cend && polygon[curr].y < pt.y {
        curr += 1
      }
      if curr == cend {
        continue
      }
    } else {
      while curr != cend && polygon[curr].y > pt.y {
        curr += 1
      }
      if curr == cend {
        continue
      }
    }
    prev = if curr == 0 { len - 1 } else { curr - 1 }
    let c = polygon[curr]
    let p = polygon[prev]
    if c.y == pt.y {
      if c.x == pt.x || (c.y == p.y && (pt.x < p.x) != (pt.x < c.x)) {
        return IsOn
      }
      curr += 1
      if curr == first {
        break
      }
      continue
    }
    if pt.x < c.x && pt.x < p.x {
      ()
    } else if pt.x > p.x && pt.x > c.x {
      val = 1 - val
    } else {
      let d = cross_product_sign(p, c, pt)
      if d == 0 {
        return IsOn
      }
      if (d < 0) == is_above {
        val = 1 - val
      }
    }
    is_above = !is_above
    curr += 1
  }
  if is_above != starting_above {
    cend = len
    if curr == cend {
      curr = 0
    }
    prev = if curr == 0 { cend - 1 } else { curr - 1 }
    let d = cross_product_sign(polygon[prev], polygon[curr], pt)
    if d == 0 {
      return IsOn
    }
    if (d < 0) == is_above {
      val = 1 - val
    }
  }
  if val == 0 {
    IsOutside
  } else {
    IsInside
  }
}

///|
/// Sorts `a` by `less`, keeping equal elements in order (`std::stable_sort`).
fn[T] stable_sort(a : Array[T], less : (T, T) -> Bool) -> Unit {
  let n = a.length()
  if n < 2 {
    return
  }
  let tmp = a.copy()
  let mut width = 1
  while width < n {
    let mut lo = 0
    while lo < n {
      let mid = @cmp.minimum(lo + width, n)
      let hi = @cmp.minimum(lo + 2 * width, n)
      let mut i = lo
      let mut j = mid
      let mut k = lo
      while i < mid && j < hi {
        if less(a[j], a[i]) {
          tmp[k] = a[j]
          j += 1
        } else {
          tmp[k] = a[i]
          i += 1
        }
        k += 1
      }
      while i < mid {
        tmp[k] = a[i]
        i += 1
        k += 1
      }
      while j < hi {
        tmp[k] = a[j]
        j += 1
        k += 1
      }
      lo = hi
    }
    for i in 0..<n {
      a[i] = tmp[i]
    }
    width *= 2
  }
}

///|
/// Whether `path2` contains `path1`, given that they do not cross except for
/// micro intersections from rounding (`Path2ContainsPath1`).
fn path2_contains_path1(path1 : Array[Point64], path2 : Array[Point64]) -> Bool {
  let mut pip = IsOn
  for pt in path1 {
    match point_in_polygon(pt, path2[:]) {
      IsOutside => {
        if pip == IsOutside {
          return false
        }
        pip = IsOutside
      }
      IsInside => {
        if pip == IsInside {
          return true
        }
        pip = IsInside
      }
      IsOn => ()
    }
  }
  if pip != IsInside {
    return false
  }
  let b = bounds_of(path1)
  let mid : Point64 = {
    x: (b.left + b.right) / 2L,
    y: (b.top + b.bottom) / 2L,
  }
  point_in_polygon(mid, path2[:]) == IsInside
}
