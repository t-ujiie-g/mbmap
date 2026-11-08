///|
/// `a * b + c` rounded once: clang contracts GDAL's `a * b + c` (and the first
/// product of `a * b + c * d`) into fused multiply-adds on arm64. Boldo and
/// Melquiond's emulation by round-to-odd, exact away from overflow and underflow.
fn fma(a : Double, b : Double, c : Double) -> Double {
  let p = a * b
  if fma_trivial(p, c) {
    return p + c
  }
  let ah = high_half(a)
  fma_rest(p, product_error(ah, a - ah, b, p), c)
}

///|
/// Whether `p + c` is already `fma`'s result for the product `p`: a zero
/// product or `c`, or a sum that is not finite.
fn fma_trivial(p : Double, c : Double) -> Bool {
  p == 0.0 || p - p != 0.0 || c - c != 0.0 || c == 0.0
}

///|
/// The high 26 bits of `a` in Veltkamp's split (the low half is `a` minus it).
fn high_half(a : Double) -> Double {
  let c = 134217729.0 * a
  c - (c - a)
}

///|
/// Dekker's exact error `a * b - p` of the product `p` of `a` (split into `ah`
/// and `al`) and `b`.
fn product_error(ah : Double, al : Double, b : Double, p : Double) -> Double {
  let bh = high_half(b)
  let bl = b - bh
  al * bl - (p - ah * bh - al * bh - ah * bl)
}

///|
/// `fma` of a product `p` with exact error `pl`, and `c`: Knuth's TwoSum of
/// `c + p`, then of its error and `pl` rounded to odd.
fn fma_rest(p : Double, pl : Double, c : Double) -> Double {
  let th = c + p
  let tb = th - c
  let tl = c - (th - tb) + (p - tb)
  let s = tl + pl
  let sb = s - tl
  let err = tl - (s - sb) + (pl - sb)
  let bits = s.reinterpret_as_int64()
  let odd = if err != 0.0 && (bits & 1L) == 0L {
    let away = (err > 0.0) == (s > 0.0)
    (if away { bits + 1L } else { bits - 1L }).reinterpret_as_double()
  } else {
    s
  }
  th + odd
}
