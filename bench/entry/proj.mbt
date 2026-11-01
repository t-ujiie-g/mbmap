///|
/// The CRS EPSG `code`, or for code 0 the definition encoded in the
/// `@proj.DEFINITION_SLOTS` f64s at `at` of `bytes`.
fn proj_crs(
  code : Int32,
  bytes : BytesView,
  at : Int32,
  trig : @proj.Trig,
) -> @proj.Crs? {
  if code != 0 {
    return @proj.Crs::from_epsg(code, trig~)
  }
  let slots = FixedArray::makei(@proj.DEFINITION_SLOTS, i => {
    f64_at(bytes, at + i * 8)
  })
  match @proj.Definition::decode(slots[:]) {
    Some(d) => @proj.Crs::new(d, trig~)
    None => None
  }
}

///|
/// Coordinates from `from` to `to` (EPSG codes, or 0 for the definitions
/// that open `bytes`, from's then to's), as x, y pairs after them: x, y
/// pairs, NaN where a projection cannot reach; empty for an unknown CRS.
fn proj_coords(
  bytes : BytesView,
  from : Int32,
  to : Int32,
  trig~ : @proj.Trig = @proj.Trig::moonbit(),
) -> Array[Double] {
  let header = @proj.DEFINITION_SLOTS * 16
  guard bytes.length() >= header &&
    proj_crs(from, bytes, 0, trig) is Some(f) &&
    proj_crs(to, bytes, @proj.DEFINITION_SLOTS * 8, trig) is Some(t) else {
    return []
  }
  let n = (bytes.length() - header) / 16
  let out = []
  for i in 0..<n {
    let x = f64_at(bytes, header + i * 16)
    let y = f64_at(bytes, header + i * 16 + 8)
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
