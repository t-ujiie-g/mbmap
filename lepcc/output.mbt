///|
fn store_u32(out : FixedArray[Byte], at : Int32, v : Int32) -> Unit {
  out[at] = (v & 0xff).to_byte()
  out[at + 1] = ((v >> 8) & 0xff).to_byte()
  out[at + 2] = ((v >> 16) & 0xff).to_byte()
  out[at + 3] = ((v >> 24) & 0xff).to_byte()
}

///|
/// The blob in `data[start, start + len)` decoded as `kind` and laid out as docs/FORMATS.md "LEPCC
/// output", or None where its decoder refuses it (always for `FlagBytes`, which is not ported).
pub fn decode(
  kind : BlobType,
  data : FixedArray[Byte],
  start : Int32,
  len : Int32,
) -> FixedArray[Byte]? {
  match kind {
    Xyz => {
      guard decode_xyz(data, start, len) is Some(xyz) else { return None }
      let out = FixedArray::make(8 + xyz.length() * 8, b'\x00')
      store_u32(out, 0, xyz.length() / 3)
      for i, v in xyz {
        let bits = v.reinterpret_as_int64()
        store_u32(out, 8 + i * 8, bits.to_int())
        store_u32(out, 12 + i * 8, (bits >> 32).to_int())
      }
      Some(out)
    }
    Rgb => {
      guard decode_rgb(data, start, len) is Some(rgb) else { return None }
      let out = FixedArray::make(8 + rgb.length(), b'\x00')
      store_u32(out, 0, rgb.length() / 3)
      for i, v in rgb {
        out[8 + i] = v
      }
      Some(out)
    }
    Intensity => {
      guard decode_intensity(data, start, len) is Some(values) else {
        return None
      }
      let out = FixedArray::make(8 + values.length() * 2, b'\x00')
      store_u32(out, 0, values.length())
      for i, v in values {
        out[8 + i * 2] = (v & 0xff).to_byte()
        out[9 + i * 2] = (v >> 8).to_byte()
      }
      Some(out)
    }
    FlagBytes => None
  }
}
