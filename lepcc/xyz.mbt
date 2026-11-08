// Ported from Esri's LEPCC (src/LEPCC.cpp `LEPCC::Decode`, `Decode_CutInSegments`, `ReadHeaders`):
// Apache License 2.0, Copyright 2016 Esri. See NOTICE.

///|
/// `sizeof(TopHeader) + sizeof(Header1)` of an XYZ blob: after the top header, an i64 blob size,
/// the extent's lower and upper corners and the max errors (f64 x, y, z each), a u32 point count
/// and 4 reserved bytes.
const XYZ_HEADER_SIZE : Int32 = 104

///|
/// `LEPCC::Decode_CutInSegments`: the section minimums bit-stuffed, then each section's values
/// above its minimum. None past `MAX_POINTS` values in all.
fn Cursor::segments(self : Cursor) -> Array[UInt32]? {
  guard self.decode() is Some(mins) else { return None }
  let out = []
  for min in mins {
    guard self.decode() is Some(values) &&
      out.length() + values.length() <= MAX_POINTS else {
      return None
    }
    for v in values {
      out.push(v + min)
    }
  }
  Some(out)
}

///|
/// `lepcc_decodeXYZ` of the blob in `data[start, start + len)`: x, y, z per point, or None where the
/// C++ fails. Also refused: no points, more than `MAX_POINTS`, and rows that do not hold exactly the
/// header's points (the C++ reads past its arrays or leaves points unwritten).
pub fn decode_xyz(
  data : FixedArray[Byte],
  start : Int32,
  len : Int32,
) -> FixedArray[Double]? {
  let size = check_blob(data, start, len, Xyz, XYZ_HEADER_SIZE)
  guard size >= 0 else { return None }
  let num_points = u32_at(data, start + 96)
  guard num_points > 0 && num_points <= MAX_POINTS.reinterpret_as_uint() else {
    return None
  }
  let n = num_points.reinterpret_as_int()
  let cursor = { data, pos: start + XYZ_HEADER_SIZE, end: start + size, }
  guard cursor.segments() is Some(y_deltas) &&
    cursor.segments() is Some(row_counts) &&
    cursor.segments() is Some(x_deltas) &&
    cursor.segments() is Some(zs) &&
    cursor.pos == start + size &&
    row_counts.length() >= y_deltas.length() else {
    return None
  }
  let x0 = f64_at(data, start + 24)
  let y0 = f64_at(data, start + 32)
  let z0 = f64_at(data, start + 40)
  let x1 = f64_at(data, start + 48)
  let y1 = f64_at(data, start + 56)
  let z1 = f64_at(data, start + 64)
  let cx = 2.0 * f64_at(data, start + 72)
  let cy = 2.0 * f64_at(data, start + 80)
  let cz = 2.0 * f64_at(data, start + 88)
  let mut limit = n
  if x_deltas.length() < limit {
    limit = x_deltas.length()
  }
  if zs.length() < limit {
    limit = zs.length()
  }
  let out = FixedArray::make(n * 3, 0.0)
  let mut cnt = 0
  let mut iy = 0
  for i, dy in y_deltas {
    iy = (iy.reinterpret_as_uint() + dy).reinterpret_as_int()
    let mut ix = 0
    let row = row_counts[i].reinterpret_as_int()
    guard row <= limit - cnt else { return None }
    for _ in 0..<row {
      ix = (ix.reinterpret_as_uint() + x_deltas[cnt]).reinterpret_as_int()
      let iz = zs[cnt].reinterpret_as_int()
      let x = x0 + ix.to_double() * cx
      let y = y0 + iy.to_double() * cy
      let z = z0 + iz.to_double() * cz
      out[cnt * 3] = if x1 < x { x1 } else { x }
      out[cnt * 3 + 1] = if y1 < y { y1 } else { y }
      out[cnt * 3 + 2] = if z1 < z { z1 } else { z }
      cnt += 1
    }
  }
  guard cnt == n else { return None }
  Some(out)
}
