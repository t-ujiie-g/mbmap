// Ported from Esri's LEPCC (src/ClusterRGB.cpp `ClusterRGB::Decode`, `ReadHeaders`): Apache License
// 2.0, Copyright 2016 Esri. See NOTICE.

///|
/// `sizeof(TopHeader) + sizeof(Header1)` of an RGB blob: after the top header, an i64 blob size,
/// a u32 point count, a u16 colormap size, a u8 lookup method and a u8 index compression.
const RGB_HEADER_SIZE : Int32 = 32

///|
/// `lepcc_decodeRGB` of the blob in `data[start, start + len)`: r, g, b per point, or None where the
/// default build's C++ fails (it has no Huffman-coded indexes). Also refused: no points, more than
/// `MAX_POINTS`, and indexes past the colormap.
fn decode_rgb(
  data : FixedArray[Byte],
  start : Int32,
  len : Int32,
) -> FixedArray[Byte]? {
  let size = check_blob(data, start, len, Rgb, RGB_HEADER_SIZE)
  guard size >= 0 else { return None }
  let num_points = u32_at(data, start + 24)
  guard num_points > 0 && num_points <= MAX_POINTS.reinterpret_as_uint() else {
    return None
  }
  let n = num_points.reinterpret_as_int()
  let num_colors = u16_at(data, start + 28)
  let compression = u8_at(data, start + 31)
  let end = start + size
  let mut at = start + RGB_HEADER_SIZE
  let out = FixedArray::make(n * 3, b'\x00')
  if num_colors == 0 {
    guard at + n * 3 <= end else { return None }
    for i in 0..<(n * 3) {
      out[i] = data[at + i]
    }
    at += n * 3
  } else {
    guard at + num_colors * 3 <= end else { return None }
    let map = at
    at += num_colors * 3
    match compression {
      0 => {
        guard at + n <= end else { return None }
        for i in 0..<n {
          let index = data[at + i].to_int()
          guard index < num_colors else { return None }
          for k in 0..<3 {
            out[i * 3 + k] = data[map + index * 3 + k]
          }
        }
        at += n
      }
      1 =>
        for i in 0..<n {
          for k in 0..<3 {
            out[i * 3 + k] = data[map + k]
          }
        }
      _ => return None
    }
  }
  guard at == end else { return None }
  Some(out)
}
