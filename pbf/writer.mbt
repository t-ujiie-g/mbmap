///|
/// Minimal protobuf encoder, for building test data and fixtures.
pub struct Writer {
  priv buf : Array[Byte]
}

///|
pub fn Writer::new() -> Writer {
  { buf: [], }
}

///|
pub fn Writer::to_bytes(self : Writer) -> Bytes {
  Bytes::from_array(self.buf)
}

///|
pub fn Writer::write_varint(self : Writer, v : UInt64) -> Unit {
  let mut v = v
  while v >= 0x80UL {
    self.buf.push(((v & 0x7fUL) | 0x80UL).to_byte())
    v = v >> 7
  }
  self.buf.push(v.to_byte())
}

///|
/// Writes a 32-bit value as protobuf does: negatives take 10 bytes.
pub fn Writer::write_varint32(self : Writer, v : Int32) -> Unit {
  self.write_varint(v.to_int64().reinterpret_as_uint64())
}

///|
pub fn Writer::write_svarint32(self : Writer, v : Int32) -> Unit {
  self.write_varint(((v << 1) ^ (v >> 31)).reinterpret_as_uint().to_uint64())
}

///|
pub fn Writer::write_sint64(self : Writer, v : Int64) -> Unit {
  self.write_varint(((v << 1) ^ (v >> 63)).reinterpret_as_uint64())
}

///|
pub fn Writer::write_tag(self : Writer, field : Int32, wire : Int32) -> Unit {
  self.write_varint(tag(field, wire).reinterpret_as_uint().to_uint64())
}

///|
pub fn Writer::write_fixed32(self : Writer, v : UInt32) -> Unit {
  for i in 0..<4 {
    self.buf.push((v >> (i * 8)).to_byte())
  }
}

///|
pub fn Writer::write_fixed64(self : Writer, v : UInt64) -> Unit {
  self.write_fixed32(v.to_uint())
  self.write_fixed32((v >> 32).to_uint())
}

///|
pub fn Writer::write_bytes(self : Writer, b : BytesView) -> Unit {
  self.write_varint(b.length().to_uint64())
  for x in b {
    self.buf.push(x)
  }
}

///|
pub fn Writer::write_string(self : Writer, s : String) -> Unit {
  self.write_bytes(@utf8.encode(s))
}
