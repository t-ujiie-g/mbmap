///|
/// Linear memory from `base` on, as table bytes are read and written in place
/// (`input_table`, `write_table`): offsets were checked by the caller.
priv struct Linear {
  base : Int32
}

///|
impl @geom.TableSource for Linear with fn u8_at(self, at) {
  load_u8(self.base + at)
}

///|
impl @geom.TableSource for Linear with fn u32_at(self, at) {
  load_i32(self.base + at)
}

///|
impl @geom.TableSource for Linear with fn f64_at(self, at) {
  load_f64(self.base + at)
}

///|
impl @geom.TableSource for Linear with fn utf8_at(self, at, n) {
  let b = FixedArray::make(n, b'\x00')
  for i in 0..<n {
    b[i] = load_u8(self.base + at + i).to_byte()
  }
  @core.utf8_lossy(b.unsafe_reinterpret_as_bytes()[:])
}

///|
/// Room up to the output's cap.
impl @geom.TableSink for Linear with fn room(self, n) {
  n <= MAX_OUTPUT_BYTES && ensure_memory(self.base + n)
}

///|
impl @geom.TableSink for Linear with fn set_u8(self, at, v) {
  store_u8(self.base + at, v)
}

///|
impl @geom.TableSink for Linear with fn set_u32(self, at, v) {
  store_i32(self.base + at, v)
}

///|
impl @geom.TableSink for Linear with fn set_f64(self, at, v) {
  store_f64(self.base + at, v)
}

///|
/// `@geom.Table::from_bytes` of input bytes `[start, start + len)`, read in
/// place; None if they are malformed or not all input.
pub fn input_table(start : Int32, len : Int32) -> @geom.Table? {
  guard lengths_fit(start, len, input_len.val) else { return None }
  @geom.Table::read_from(Linear::{ base: PAGE + start, }, len)
}

///|
/// Writes `@geom.Table::to_bytes` of `t` to the output in place; returns their
/// length, or -2 without memory.
pub fn write_table(t : @geom.Table) -> Int32 {
  let n = t.write_to(Linear::{ base: output_addr(), })
  if n < 0 {
    -2
  } else {
    n
  }
}
