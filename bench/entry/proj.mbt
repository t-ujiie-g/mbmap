///|
/// Coordinates (f64 x, y pairs in `bytes`) from EPSG `from` to EPSG `to`: x, y
/// pairs, NaN where a projection cannot reach; empty for an unknown code.
fn proj_coords(bytes : BytesView, from : Int32, to : Int32) -> Array[Double] {
  guard @proj.Crs::from_epsg(from) is Some(f) &&
    @proj.Crs::from_epsg(to) is Some(t) else {
    return []
  }
  let n = bytes.length() / 16
  let out = []
  for i in 0..<n {
    let x = f64_at(bytes, i * 16)
    let y = f64_at(bytes, i * 16 + 8)
    match @proj.transform(f, t, x, y) {
      Some((a, b)) => {
        out.push(a)
        out.push(b)
      }
      None => {
        out.push(@double.not_a_number)
        out.push(@double.not_a_number)
      }
    }
  }
  out
}

///|
fn f64_at(b : BytesView, at : Int32) -> Double {
  let mut bits = 0UL
  for k in 0..<8 {
    bits = bits | (b[at + k].to_uint64() << (k * 8))
  }
  bits.reinterpret_as_double()
}
