// Ported from Esri's LEPCC (src/Intensity.cpp `Intensity::Decode`, `ReadHeaders`): Apache License
// 2.0, Copyright 2016 Esri. See NOTICE.

///|
/// `sizeof(TopHeader) + sizeof(Header1)` of an intensity blob: after the top header, an i64 blob
/// size, a u32 point count, a u16 upscale factor, a u8 bits per value and a reserved byte.
const INTENSITY_HEADER_SIZE : Int32 = 32

///|
/// `lepcc_decodeIntensity` of the blob in `data[start, start + len)`: each value 0 to 65535, or None
/// where the C++ fails. Also refused: no values, more than `MAX_POINTS`, and a bit-stuffed array of
/// another length than the header's (the C++ reads past it or refuses).
pub fn decode_intensity(
  data : FixedArray[Byte],
  start : Int32,
  len : Int32,
) -> FixedArray[Int32]? {
  let size = check_blob(data, start, len, Intensity, INTENSITY_HEADER_SIZE)
  guard size >= 0 else { return None }
  let num_points = u32_at(data, start + 24)
  guard num_points > 0 && num_points <= MAX_POINTS.reinterpret_as_uint() else {
    return None
  }
  let n = num_points.reinterpret_as_int()
  let scale = u16_at(data, start + 28)
  let bpp = u8_at(data, start + 30)
  guard scale >= 1 && bpp <= 16 else { return None }
  let end = start + size
  let at = start + INTENSITY_HEADER_SIZE
  if bpp == 16 {
    guard at + n * 2 == end else { return None }
    let out = FixedArray::make(n, 0)
    for i in 0..<n {
      out[i] = u16_at(data, at + i * 2)
    }
    Some(out)
  } else if bpp == 8 {
    guard at + n == end else { return None }
    let out = FixedArray::make(n, 0)
    for i in 0..<n {
      out[i] = (data[at + i].to_int() * scale) & 0xffff
    }
    Some(out)
  } else {
    let cursor = { data, pos: at, end, }
    guard cursor.decode(n) is Some(values) &&
      values.length() == n &&
      cursor.pos == end else {
      return None
    }
    let s = scale.reinterpret_as_uint()
    let out = FixedArray::make(n, 0)
    for i in 0..<n {
      out[i] = ((values[i] * s) & 0xffffU).reinterpret_as_int()
    }
    Some(out)
  }
}
