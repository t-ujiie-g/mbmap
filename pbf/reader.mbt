///|
/// Zero-copy protobuf cursor. Reads never raise (see AGENTS.md §4): a failed read
/// records the first error, returns 0 and jumps to the end so `at_end` loops stop.
/// Check `error` once at a boundary.
pub struct Reader {
  priv data : Bytes
  priv mut pos : Int32
  priv mut end : Int32
  priv mut error : PbfError?
}

///|
/// A reader over `view`, at its start.
pub fn Reader::new(view : BytesView) -> Reader {
  let start = view.start_offset()
  { data: view.data(), pos: start, end: start + view.length(), error: None, }
}

///|
/// Repositions this reader over `[start, end)` of the same buffer and clears
/// its error; offsets are absolute, as returned by `pos`. Reusing one reader
/// avoids an allocation per message. Out-of-range bounds become an error.
pub fn Reader::reset(self : Reader, start : Int32, end : Int32) -> Unit {
  self.error = None
  if start < 0 || end < start || end > self.data.length() {
    self.pos = 0
    self.end = 0
    self.error = Some(LengthOutOfRange(pos=start, end - start))
  } else {
    self.pos = start
    self.end = end
  }
}

///|
/// Absolute offset of the next byte to read.
pub fn Reader::pos(self : Reader) -> Int32 {
  self.pos
}

///|
/// Whether nothing is left: the loop condition of a message, true after an error too.
pub fn Reader::at_end(self : Reader) -> Bool {
  self.pos >= self.end
}

///|
/// Bytes left in the current range.
pub fn Reader::remaining(self : Reader) -> Int32 {
  self.end - self.pos
}

///|
/// Whether a read has failed since the last `reset`.
pub fn Reader::failed(self : Reader) -> Bool {
  self.error is Some(_)
}

///|
/// The first error since the last `reset`.
pub fn Reader::error(self : Reader) -> PbfError? {
  self.error
}

///|
fn Reader::fail(self : Reader, err : PbfError) -> Unit {
  if self.error is None {
    self.error = Some(err)
  }
  self.pos = self.end
}

///|
fn Reader::byte(self : Reader) -> Int32 {
  if self.pos >= self.end {
    self.fail(UnexpectedEof(pos=self.pos))
    return 0
  }
  let b = self.data[self.pos].to_int()
  self.pos += 1
  b
}

///|
/// Reads a field tag (`field << 3 | wire`); see `tag` and `WIRE_*`. Group
/// wire types are an error.
pub fn Reader::read_tag(self : Reader) -> Int32 {
  let pos = self.pos
  let t = self.read_varint32()
  match t & WIRE_MASK {
    WIRE_VARINT | WIRE_FIXED64 | WIRE_LEN | WIRE_FIXED32 => t
    w => {
      self.fail(UnsupportedWireType(pos~, w))
      0
    }
  }
}

///|
/// Reads a varint and keeps its low 32 bits, as protobuf does for `uint32`.
pub fn Reader::read_varint32(self : Reader) -> Int32 {
  let p = self.pos
  if p < self.end {
    let b = self.data[p].to_int()
    if b < 0x80 {
      self.pos = p + 1
      return b
    }
  }
  self.read_varint32_multi()
}

///|
/// General case of `read_varint32`, keeping the cursor in locals.
fn Reader::read_varint32_multi(self : Reader) -> Int32 {
  let data = self.data
  let end = self.end
  let start = self.pos
  for p = start, v = 0, shift = 0 {
    if p >= end {
      self.fail(UnexpectedEof(pos=p))
      return 0
    }
    let b = data[p].to_int()
    let v = if shift < 32 { v | ((b & 0x7f) << shift) } else { v }
    if b < 0x80 {
      self.pos = p + 1
      return v
    }
    if shift >= 63 {
      self.fail(VarintTooLong(pos=start))
      return 0
    }
    continue p + 1, v, shift + 7
  }
}

///|
/// Reads a varint of at most 10 bytes; longer is an error.
pub fn Reader::read_varint64(self : Reader) -> UInt64 {
  let start = self.pos
  let mut v = 0UL
  for shift = 0; shift < 70; shift = shift + 7 {
    let b = self.byte()
    v = v | ((b & 0x7f).to_uint64() << shift)
    if b < 0x80 {
      return v
    }
  }
  self.fail(VarintTooLong(pos=start))
  0UL
}

///|
/// Reads a zigzag-encoded `sint32`.
pub fn Reader::read_svarint32(self : Reader) -> Int32 {
  zigzag32(self.read_varint32())
}

///|
fn zigzag32(v : Int32) -> Int32 {
  (v.reinterpret_as_uint() >> 1).reinterpret_as_int() ^ -(v & 1)
}

///|
/// Reads an `int64`: a varint in two's complement.
pub fn Reader::read_int64(self : Reader) -> Int64 {
  self.read_varint64().reinterpret_as_int64()
}

///|
/// Reads a zigzag-encoded `sint64`.
pub fn Reader::read_sint64(self : Reader) -> Int64 {
  let v = self.read_varint64()
  (v >> 1).reinterpret_as_int64() ^ -(v & 1UL).reinterpret_as_int64()
}

///|
/// Reads a `bool`: any varint but 0 is true.
pub fn Reader::read_bool(self : Reader) -> Bool {
  self.read_varint64() != 0UL
}

///|
/// Advances past `n` bytes and returns where they start, or -1 on EOF.
fn Reader::take(self : Reader, n : Int32) -> Int32 {
  if self.end - self.pos < n {
    self.fail(UnexpectedEof(pos=self.pos))
    return -1
  }
  let p = self.pos
  self.pos += n
  p
}

///|
/// Reads a little-endian `fixed32`.
pub fn Reader::read_fixed32(self : Reader) -> UInt32 {
  let p = self.take(4)
  if p < 0 {
    return 0
  }
  let d = self.data
  d[p].to_uint() |
  (d[p + 1].to_uint() << 8) |
  (d[p + 2].to_uint() << 16) |
  (d[p + 3].to_uint() << 24)
}

///|
/// Reads a little-endian `fixed64`.
pub fn Reader::read_fixed64(self : Reader) -> UInt64 {
  let lo = self.read_fixed32().to_uint64()
  let hi = self.read_fixed32().to_uint64()
  lo | (hi << 32)
}

///|
/// Reads a `float`: IEEE 754 bits as a `fixed32`.
pub fn Reader::read_float(self : Reader) -> Float {
  Float::reinterpret_from_uint(self.read_fixed32())
}

///|
/// Reads a `double`: IEEE 754 bits as a `fixed64`.
pub fn Reader::read_double(self : Reader) -> Double {
  self.read_fixed64().reinterpret_as_double()
}

///|
/// Reads a length prefix and checks it fits; returns -1 on error.
fn Reader::read_len(self : Reader) -> Int32 {
  let pos = self.pos
  let len = self.read_varint32()
  if self.error is Some(_) {
    return -1
  }
  if len < 0 || len > self.end - self.pos {
    self.fail(LengthOutOfRange(pos~, len))
    return -1
  }
  len
}

///|
/// Narrows the reader to the next length-delimited field, without allocating.
/// Pass the returned token to `exit` once the field has been read.
pub fn Reader::enter(self : Reader) -> Int32 {
  let len = self.read_len()
  if len < 0 {
    return self.end
  }
  let outer = self.end
  self.end = self.pos + len
  outer
}

///|
/// Leaves the field entered with `enter`, skipping whatever was not read.
pub fn Reader::exit(self : Reader, token : Int32) -> Unit {
  if self.error is None {
    self.pos = self.end
    self.end = token
  }
}

///|
/// Skips over a length-delimited field and returns its absolute start offset;
/// its end is `pos()` afterwards.
pub fn Reader::read_len_start(self : Reader) -> Int32 {
  let len = self.read_len()
  if len < 0 {
    return self.pos
  }
  let start = self.pos
  self.pos += len
  start
}

///|
/// Reads a length-delimited field as a view of the original buffer (no copy).
pub fn Reader::read_bytes(self : Reader) -> BytesView {
  let start = self.read_len_start()
  self.data[start:self.pos]
}

///|
/// Reads a UTF-8 string; invalid sequences become U+FFFD, like `TextDecoder`.
pub fn Reader::read_string(self : Reader) -> String {
  @core.utf8_lossy(self.read_bytes())
}

///|
/// Skips the value of a field whose tag was just read.
pub fn Reader::skip(self : Reader, tag : Int32) -> Unit {
  match tag & WIRE_MASK {
    WIRE_VARINT => ignore(self.read_varint64())
    WIRE_FIXED64 => ignore(self.take(8))
    WIRE_FIXED32 => ignore(self.take(4))
    WIRE_LEN => ignore(self.read_len_start())
    w => self.fail(UnsupportedWireType(pos=self.pos, w))
  }
}
