///|
/// Backing bytes of a `PackedTile` on targets without a linear memory to
/// write into (and in tests): a growable array.
priv struct Store {
  mut data : FixedArray[Byte]
}

///|
fn Store::new() -> Store {
  { data: FixedArray::make(64 * 1024, b'\x00'), }
}

///|
/// Makes `[0, need)` writable, keeping the first `keep` bytes.
fn Store::ensure(self : Store, need : Int32, keep : Int32) -> Bool {
  if need > self.data.length() {
    let grown = FixedArray::make(
      @cmp.maximum(need, self.data.length() * 2),
      b'\x00',
    )
    FixedArray::blit_to(self.data, grown, len=keep)
    self.data = grown
  }
  true
}

///|
fn Store::set_u8(self : Store, at : Int32, v : Int32) -> Unit {
  self.data[at] = v.to_byte()
}

///|
fn Store::set_u16(self : Store, at : Int32, v : Int32) -> Unit {
  self.data[at] = v.to_byte()
  self.data[at + 1] = (v >> 8).to_byte()
}

///|
fn Store::set_u32(self : Store, at : Int32, v : Int32) -> Unit {
  let d = self.data
  d[at] = v.to_byte()
  d[at + 1] = (v >> 8).to_byte()
  d[at + 2] = (v >> 16).to_byte()
  d[at + 3] = (v >> 24).to_byte()
}

///|
fn Store::get_u32(self : Store, at : Int32) -> Int32 {
  let d = self.data
  d[at].to_int() |
  (d[at + 1].to_int() << 8) |
  (d[at + 2].to_int() << 16) |
  (d[at + 3].to_int() << 24)
}

///|
fn Store::zero(self : Store, start : Int32, end : Int32) -> Unit {
  self.data.fill(b'\x00', start~, end~)
}

///|
fn Store::copy_out(self : Store, len : Int32) -> Bytes {
  Bytes::from_array(self.data[:len])
}

///|
/// Repeats the `len` bytes at `at` until `total` bytes from `at` are filled.
fn Store::repeat(self : Store, at : Int32, len : Int32, total : Int32) -> Unit {
  let mut filled = len
  while filled < total {
    let n = @cmp.minimum(filled, total - filled)
    FixedArray::blit_to(
      self.data,
      self.data,
      len=n,
      src_offset=at,
      dst_offset=at + filled,
    )
    filled += n
  }
}
