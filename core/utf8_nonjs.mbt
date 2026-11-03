///|
fn uint16_string(units : FixedArray[UInt16]) -> String = "%string.unsafe_from_uint16_fixedarray"

///|
/// One pass, where `@utf8.decode_lossy` validates first and decodes after
/// (two decoders in every module that reads text).
fn decode_lossy(b : BytesView) -> String {
  let n = b.length()
  // Every byte gives at most one UTF-16 unit (four-byte sequences give two).
  let out = FixedArray::make(n, (0 : UInt16))
  let mut w = 0
  let mut i = 0
  while i < n {
    let c = b[i].to_int()
    if c < 0x80 {
      out[w] = c.to_uint16()
      w += 1
      i += 1
      continue
    }
    // Continuation bytes the lead byte allows first, and how many follow.
    let (need, lo, hi, init) = match c {
      0xC2..<=0xDF => (1, 0x80, 0xBF, c & 0x1F)
      0xE0 => (2, 0xA0, 0xBF, 0)
      0xE1..<=0xEC | 0xEE..<=0xEF => (2, 0x80, 0xBF, c & 0x0F)
      0xED => (2, 0x80, 0x9F, 0x0D)
      0xF0 => (3, 0x90, 0xBF, 0)
      0xF1..<=0xF3 => (3, 0x80, 0xBF, c & 0x07)
      0xF4 => (3, 0x80, 0x8F, 4)
      _ => (0, 0, 0, 0)
    }
    let mut cp = init
    let mut j = i + 1
    let mut k = 0
    while k < need && j < n {
      let d = b[j].to_int()
      let (l, h) = if k == 0 { (lo, hi) } else { (0x80, 0xBF) }
      if d < l || d > h {
        break
      }
      cp = (cp << 6) | (d & 0x3F)
      j += 1
      k += 1
    }
    if need == 0 || k < need {
      out[w] = (0xFFFD : UInt16)
      w += 1
      // A malformed subpart ends before the byte that broke it.
      i = if need == 0 { i + 1 } else { j }
    } else if cp < 0x10000 {
      out[w] = cp.to_uint16()
      w += 1
      i = j
    } else {
      let v = cp - 0x10000
      out[w] = (0xD800 + (v >> 10)).to_uint16()
      out[w + 1] = (0xDC00 + (v & 0x3FF)).to_uint16()
      w += 2
      i = j
    }
  }
  if w == n {
    return uint16_string(out)
  }
  let trimmed = FixedArray::make(w, (0 : UInt16))
  trimmed.unsafe_blit(0, out, 0, w)
  uint16_string(trimmed)
}
