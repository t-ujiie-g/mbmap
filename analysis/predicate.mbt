// Point in polygon follows point-in-polygon-hao 1.2.4 (MIT License, Copyright
// (c) 2021 Rowan Winsemius) with robust-predicates 3.0.3's orient2d (public
// domain, the Unlicense). See NOTICE.

///|
const EPSILON : Double = 1.1102230246251565e-16

///|
const SPLITTER : Double = 134217729.0

///|
/// robust-predicates' `orient2d(ax, ay, bx, by, 0, 0)`: the third point is the
/// origin, so every tail of its adaptive stage is zero and the expansion of
/// the exact determinant decides.
fn orient_origin(ax : Double, ay : Double, bx : Double, by : Double) -> Double {
  let left = ay * bx
  let right = ax * by
  let det = left - right
  let sum = (left + right).abs()
  if det.abs() >= (3.0 + 16.0 * EPSILON) * EPSILON * sum {
    return det
  }
  // Two_Product(ax, by) - Two_Product(ay, bx), as four components.
  let s1 = ax * by
  let mut c = SPLITTER * ax
  let mut ahi = c - (c - ax)
  let mut alo = ax - ahi
  c = SPLITTER * by
  let mut bhi = c - (c - by)
  let mut blo = by - bhi
  let s0 = alo * blo - (s1 - ahi * bhi - alo * bhi - ahi * blo)
  let t1 = ay * bx
  c = SPLITTER * ay
  ahi = c - (c - ay)
  alo = ay - ahi
  c = SPLITTER * bx
  bhi = c - (c - bx)
  blo = bx - bhi
  let t0 = alo * blo - (t1 - ahi * bhi - alo * bhi - ahi * blo)
  let mut i = s0 - t0
  let mut bvirt = s0 - i
  let b0 = s0 - (i + bvirt) + (bvirt - t0)
  let j = s1 + i
  bvirt = j - s1
  let z = s1 - (j - bvirt) + (i - bvirt)
  i = z - t1
  bvirt = z - i
  let b1 = z - (i + bvirt) + (bvirt - t1)
  let u3 = j + i
  bvirt = u3 - j
  let b2 = j - (u3 - bvirt) + (i - bvirt)
  -(b0 + b1 + b2 + u3)
}

///|
/// Where (x, y) lies against polygon part `p` of `t` (point-in-polygon-hao):
/// 0 on its boundary, 1 inside, -1 outside.
fn in_part(t : @geom.Table, p : Int32, x : Double, y : Double) -> Int32 {
  let c = t.coords
  let (r0, r1) = t.rings(p)
  let mut k = 0
  for r in r0..<r1 {
    let (a, b) = t.points(r)
    if b - a < 1 {
      continue
    }
    let mut u1 = c[a * 2] - x
    let mut v1 = c[a * 2 + 1] - y
    for i in (a + 1)..<b {
      let u2 = c[i * 2] - x
      let v2 = c[i * 2 + 1] - y
      if v1 == 0.0 && v2 == 0.0 {
        if (u2 <= 0.0 && u1 >= 0.0) || (u1 <= 0.0 && u2 >= 0.0) {
          return 0
        }
      } else if (v2 >= 0.0 && v1 <= 0.0) || (v2 <= 0.0 && v1 >= 0.0) {
        let f = orient_origin(u1, u2, v1, v2)
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
  }
  if k % 2 == 0 {
    -1
  } else {
    1
  }
}

///|
/// Whether (x, y) is inside polygon feature `f` or on its boundary (Turf's
/// `booleanPointInPolygon`); false for other kinds.
pub fn contains_point(
  t : @geom.Table,
  f : Int32,
  x : Double,
  y : Double,
) -> Bool {
  guard is_polygon(t.kinds[f]) else { return false }
  let (p0, p1) = t.parts(f)
  for p in p0..<p1 {
    if in_part(t, p, x, y) >= 0 {
      return true
    }
  }
  false
}
