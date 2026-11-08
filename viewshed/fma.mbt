///|
/// `a * b + c` rounded once: clang contracts GDAL's `a * b + c` (and the first
/// product of `a * b + c * d`) into fused multiply-adds on arm64. Boldo and
/// Melquiond's emulation by round-to-odd, exact away from overflow and underflow.
fn fma(a : Double, b : Double, c : Double) -> Double {
  let p = a * b
  if p == 0.0 || p - p != 0.0 || c - c != 0.0 {
    return p + c
  }
  let (ah, al) = split(a)
  let (bh, bl) = split(b)
  let pl = al * bl - (p - ah * bh - al * bh - ah * bl)
  let (th, tl) = two_sum(c, p)
  let (s, err) = two_sum(tl, pl)
  let bits = s.reinterpret_as_int64()
  let odd = if err != 0.0 && (bits & 1L) == 0L {
    let away = (err > 0.0) == (s > 0.0)
    (if away { bits + 1L } else { bits - 1L }).reinterpret_as_double()
  } else {
    s
  }
  th + odd
}

///|
/// Veltkamp's split of `a` into two halves of 26 bits.
fn split(a : Double) -> (Double, Double) {
  let c = 134217729.0 * a
  let hi = c - (c - a)
  (hi, a - hi)
}

///|
/// Knuth's TwoSum: `a + b` rounded and its exact error.
fn two_sum(a : Double, b : Double) -> (Double, Double) {
  let s = a + b
  let bb = s - a
  (s, a - (s - bb) + (b - bb))
}
