// Ported from robust-predicates 3.0.3 (orient2d.js, util.js; the Unlicense),
// after Jonathan Richard Shewchuk's public-domain predicates.c.

///|
let epsilon : Double = 1.1102230246251565e-16

///|
let splitter : Double = 134217729.0

///|
let resulterrbound : Double = (3.0 + 8.0 * epsilon) * epsilon

///|
let ccwerrbound_a : Double = (3.0 + 16.0 * epsilon) * epsilon

///|
let ccwerrbound_b : Double = (2.0 + 12.0 * epsilon) * epsilon

///|
let ccwerrbound_c : Double = (9.0 + 64.0 * epsilon) * epsilon * epsilon

///|
let b_exp : FixedArray[Double] = FixedArray::make(4, 0.0)

///|
let c1_exp : FixedArray[Double] = FixedArray::make(8, 0.0)

///|
let c2_exp : FixedArray[Double] = FixedArray::make(12, 0.0)

///|
let d_exp : FixedArray[Double] = FixedArray::make(16, 0.0)

///|
let u_exp : FixedArray[Double] = FixedArray::make(4, 0.0)

///|
/// `e[i]`, or 0 past its end where JavaScript reads `undefined`: `sum` looks
/// one element ahead but never uses that value.
fn at(e : FixedArray[Double], i : Int32) -> Double {
  if i < e.length() {
    e[i]
  } else {
    0.0
  }
}

///|
/// util.js's `sum` (fast_expansion_sum_zeroelim): `e` + `f` into `h`, its length.
fn sum(
  elen : Int32,
  e : FixedArray[Double],
  flen : Int32,
  f : FixedArray[Double],
  h : FixedArray[Double],
) -> Int32 {
  let mut enow = e[0]
  let mut fnow = f[0]
  let mut eindex = 0
  let mut findex = 0
  let mut q = 0.0
  if (fnow > enow) == (fnow > -enow) {
    q = enow
    eindex += 1
    enow = at(e, eindex)
  } else {
    q = fnow
    findex += 1
    fnow = at(f, findex)
  }
  let mut hindex = 0
  if eindex < elen && findex < flen {
    let mut qnew = 0.0
    let mut hh = 0.0
    if (fnow > enow) == (fnow > -enow) {
      qnew = enow + q
      hh = q - (qnew - enow)
      eindex += 1
      enow = at(e, eindex)
    } else {
      qnew = fnow + q
      hh = q - (qnew - fnow)
      findex += 1
      fnow = at(f, findex)
    }
    q = qnew
    if hh != 0.0 {
      h[hindex] = hh
      hindex += 1
    }
    while eindex < elen && findex < flen {
      let mut bvirt = 0.0
      if (fnow > enow) == (fnow > -enow) {
        qnew = q + enow
        bvirt = qnew - q
        hh = q - (qnew - bvirt) + (enow - bvirt)
        eindex += 1
        enow = at(e, eindex)
      } else {
        qnew = q + fnow
        bvirt = qnew - q
        hh = q - (qnew - bvirt) + (fnow - bvirt)
        findex += 1
        fnow = at(f, findex)
      }
      q = qnew
      if hh != 0.0 {
        h[hindex] = hh
        hindex += 1
      }
    }
  }
  while eindex < elen {
    let qnew = q + enow
    let bvirt = qnew - q
    let hh = q - (qnew - bvirt) + (enow - bvirt)
    eindex += 1
    enow = at(e, eindex)
    q = qnew
    if hh != 0.0 {
      h[hindex] = hh
      hindex += 1
    }
  }
  while findex < flen {
    let qnew = q + fnow
    let bvirt = qnew - q
    let hh = q - (qnew - bvirt) + (fnow - bvirt)
    findex += 1
    fnow = at(f, findex)
    q = qnew
    if hh != 0.0 {
      h[hindex] = hh
      hindex += 1
    }
  }
  if q != 0.0 || hindex == 0 {
    h[hindex] = q
    hindex += 1
  }
  hindex
}

///|
fn estimate(elen : Int32, e : FixedArray[Double]) -> Double {
  let mut q = e[0]
  for i in 1..<elen {
    q += e[i]
  }
  q
}

///|
/// The high half of `a`, Shewchuk's Split.
fn split_hi(a : Double) -> Double {
  let c = splitter * a
  c - (c - a)
}

///|
/// Two-Product's error term of `a * b`, whose rounded value is `p`.
fn product_tail(a : Double, b : Double, p : Double) -> Double {
  let ahi = split_hi(a)
  let alo = a - ahi
  let bhi = split_hi(b)
  let blo = b - bhi
  alo * blo - (p - ahi * bhi - alo * bhi - ahi * blo)
}

///|
/// Two-Two-Diff of `a * b - c * d` into the four words of `out`.
fn two_two_diff(
  a : Double,
  b : Double,
  c : Double,
  d : Double,
  out : FixedArray[Double],
) -> Unit {
  let s1 = a * b
  let s0 = product_tail(a, b, s1)
  let t1 = c * d
  let t0 = product_tail(c, d, t1)
  let mut i = s0 - t0
  let mut bvirt = s0 - i
  out[0] = s0 - (i + bvirt) + (bvirt - t0)
  let j = s1 + i
  bvirt = j - s1
  let z = s1 - (j - bvirt) + (i - bvirt)
  i = z - t1
  bvirt = z - i
  out[1] = z - (i + bvirt) + (bvirt - t1)
  let u3 = j + i
  bvirt = u3 - j
  out[2] = j - (u3 - bvirt) + (i - bvirt)
  out[3] = u3
}

///|
/// The tail of `a - b`, whose rounded value is `x` (Two-Diff-Tail).
fn diff_tail(a : Double, b : Double, x : Double) -> Double {
  let bvirt = a - x
  a - (x + bvirt) + (bvirt - b)
}

///|
fn orient2dadapt(
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
  cx : Double,
  cy : Double,
  detsum : Double,
) -> Double {
  let acx = ax - cx
  let bcx = bx - cx
  let acy = ay - cy
  let bcy = by - cy
  two_two_diff(acx, bcy, acy, bcx, b_exp)
  let mut det = estimate(4, b_exp)
  let mut errbound = ccwerrbound_b * detsum
  if det >= errbound || -det >= errbound {
    return det
  }
  let acxtail = diff_tail(ax, cx, acx)
  let bcxtail = diff_tail(bx, cx, bcx)
  let acytail = diff_tail(ay, cy, acy)
  let bcytail = diff_tail(by, cy, bcy)
  if acxtail == 0.0 && acytail == 0.0 && bcxtail == 0.0 && bcytail == 0.0 {
    return det
  }
  errbound = ccwerrbound_c * detsum + resulterrbound * det.abs()
  det += acx * bcytail + bcy * acxtail - (acy * bcxtail + bcx * acytail)
  if det >= errbound || -det >= errbound {
    return det
  }
  two_two_diff(acxtail, bcy, acytail, bcx, u_exp)
  let c1len = sum(4, b_exp, 4, u_exp, c1_exp)
  two_two_diff(acx, bcytail, acy, bcxtail, u_exp)
  let c2len = sum(c1len, c1_exp, 4, u_exp, c2_exp)
  two_two_diff(acxtail, bcytail, acytail, bcxtail, u_exp)
  let dlen = sum(c2len, c2_exp, 4, u_exp, d_exp)
  d_exp[dlen - 1]
}

///|
/// Twice the signed area of the triangle a, b, c, exact in sign: positive when
/// clockwise in a y-up frame, negative counter-clockwise, 0 when collinear.
/// Bit for bit robust-predicates 3.0.3's `orient2d`.
pub fn orient2d(
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
  cx : Double,
  cy : Double,
) -> Double {
  let detleft = (ay - cy) * (bx - cx)
  let detright = (ax - cx) * (by - cy)
  let det = detleft - detright
  let detsum = (detleft + detright).abs()
  if det.abs() >= ccwerrbound_a * detsum {
    return det
  }
  -orient2dadapt(ax, ay, bx, by, cx, cy, detsum)
}
