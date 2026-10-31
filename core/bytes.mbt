///|
/// Property value tags of the binary formats (docs/FORMATS.md, "Property values").
pub const PROP_NULL : Int32 = 0

///|
pub const PROP_FALSE : Int32 = 1

///|
pub const PROP_TRUE : Int32 = 2

///|
pub const PROP_NUMBER : Int32 = 3

///|
pub const PROP_STRING : Int32 = 4

///|
/// The feature lacks the key.
pub const PROP_ABSENT : Int32 = 5

///|
/// Little-endian bytes being written.
pub struct ByteWriter {
  priv buf : Array[Byte]
}

///|
pub fn ByteWriter::new() -> ByteWriter {
  { buf: [], }
}

///|
pub fn ByteWriter::u8(self : ByteWriter, v : Int32) -> Unit {
  self.buf.push(v.to_byte())
}

///|
pub fn ByteWriter::u32(self : ByteWriter, v : Int32) -> Unit {
  for i in 0..<4 {
    self.buf.push((v >> (i * 8)).to_byte())
  }
}

///|
/// `v` clamped to the i16 range.
pub fn ByteWriter::i16(self : ByteWriter, v : Int32) -> Unit {
  let c = @cmp.maximum(-32768, @cmp.minimum(32767, v))
  self.buf.push(c.to_byte())
  self.buf.push((c >> 8).to_byte())
}

///|
pub fn ByteWriter::f64(self : ByteWriter, v : Double) -> Unit {
  let bits = v.reinterpret_as_uint64()
  for i in 0..<8 {
    self.buf.push((bits >> (i * 8)).to_byte())
  }
}

///|
/// A u32 byte length and the UTF-8 bytes.
pub fn ByteWriter::utf8(self : ByteWriter, s : String) -> Unit {
  let b = @utf8.encode(s)
  self.u32(b.length())
  for x in b {
    self.buf.push(x)
  }
}

///|
/// Zero bytes up to a multiple of 4.
pub fn ByteWriter::pad4(self : ByteWriter) -> Unit {
  while self.buf.length() % 4 != 0 {
    self.buf.push(b'\x00')
  }
}

///|
/// Empties the writer, keeping its capacity for reuse.
pub fn ByteWriter::clear(self : ByteWriter) -> Unit {
  self.buf.clear()
}

///|
pub fn ByteWriter::to_bytes(self : ByteWriter) -> Bytes {
  Bytes::from_array(self.buf)
}

///|
/// Reads little-endian bytes. Errors are sticky: a read past the end
/// returns 0 (or "") and marks the reader failed, so a decoder checks `ok`
/// once at the end instead of after every read.
pub struct ByteReader {
  priv b : BytesView
  priv mut at : Int32
  priv mut failed : Bool
}

///|
pub fn ByteReader::new(b : BytesView) -> ByteReader {
  { b, at: 0, failed: false, }
}

///|
/// Whether no read has gone past the end (or been marked bad).
pub fn ByteReader::ok(self : ByteReader) -> Bool {
  !self.failed
}

///|
/// Whether every byte was read and nothing failed.
pub fn ByteReader::done(self : ByteReader) -> Bool {
  !self.failed && self.at == self.b.length()
}

///|
/// Marks the input bad (for a value the caller finds invalid).
pub fn ByteReader::fail(self : ByteReader) -> Unit {
  self.failed = true
  self.at = self.b.length()
}

///|
/// Whether `n` more bytes are there; fails the reader if not.
fn ByteReader::has(self : ByteReader, n : Int32) -> Bool {
  if n < 0 || n > self.b.length() - self.at {
    self.fail()
    return false
  }
  true
}

///|
pub fn ByteReader::u8(self : ByteReader) -> Int32 {
  if !self.has(1) {
    return 0
  }
  self.at += 1
  self.b[self.at - 1].to_int()
}

///|
pub fn ByteReader::u32(self : ByteReader) -> Int32 {
  if !self.has(4) {
    return 0
  }
  let b = self.b
  let a = self.at
  self.at += 4
  b[a].to_int() |
  (b[a + 1].to_int() << 8) |
  (b[a + 2].to_int() << 16) |
  (b[a + 3].to_int() << 24)
}

///|
pub fn ByteReader::i16(self : ByteReader) -> Int32 {
  if !self.has(2) {
    return 0
  }
  let v = self.b[self.at].to_int() | (self.b[self.at + 1].to_int() << 8)
  self.at += 2
  if v >= 0x8000 {
    v - 0x10000
  } else {
    v
  }
}

///|
pub fn ByteReader::f64(self : ByteReader) -> Double {
  if !self.has(8) {
    return 0.0
  }
  let mut bits = 0UL
  for i in 0..<8 {
    bits = bits | (self.b[self.at + i].to_uint64() << (i * 8))
  }
  self.at += 8
  bits.reinterpret_as_double()
}

///|
/// A u32 byte length and that much UTF-8 (invalid sequences replaced).
pub fn ByteReader::utf8(self : ByteReader) -> String {
  let n = self.u32()
  if !self.has(n) {
    return ""
  }
  self.at += n
  @utf8.decode_lossy(self.b[self.at - n:self.at])
}

///|
/// Skips to the next multiple of 4.
pub fn ByteReader::pad4(self : ByteReader) -> Unit {
  let n = (4 - self.at % 4) % 4
  if self.has(n) {
    self.at += n
  }
}
