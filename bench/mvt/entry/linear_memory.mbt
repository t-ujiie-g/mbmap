///|
extern "wasm" fn load_u8(addr : Int32) -> Int32 =
  #|(func (param i32) (result i32) (i32.load8_u (local.get 0)))

///|
extern "wasm" fn load_i32(addr : Int32) -> Int32 =
  #|(func (param i32) (result i32) (i32.load align=1 (local.get 0)))

///|
/// Copies `[addr, addr + len)` of linear memory into a new `Bytes`, four
/// bytes per load. The caller guarantees the range is inside linear memory.
fn bytes_from_mem(addr : Int32, len : Int32) -> Bytes {
  let arr = FixedArray::make(len, b'\x00')
  let words = len / 4
  for w in 0..<words {
    let v = load_i32(addr + w * 4)
    let i = w * 4
    arr[i] = v.to_byte()
    arr[i + 1] = (v >> 8).to_byte()
    arr[i + 2] = (v >> 16).to_byte()
    arr[i + 3] = (v >> 24).to_byte()
  }
  for i in (words * 4)..<len {
    arr[i] = load_u8(addr + i).to_byte()
  }
  // Nothing else holds `arr`, so the reinterpretation cannot be observed mutating.
  arr.unsafe_reinterpret_as_bytes()
}

///|
extern "wasm" fn memory_grow(pages : Int32) -> Int32 =
  #|(func (param i32) (result i32) (memory.grow (local.get 0)))

///|
/// Grows linear memory by `pages` 64KiB pages; returns the previous size.
#export_name("grow_memory")
pub fn grow_memory(pages : Int32) -> Int32 {
  memory_grow(pages)
}

///|
/// Copies the tile at `addr` into a MoonBit `Bytes` inside wasm, then decodes it.
/// The caller guarantees `[addr, addr + len)` is inside linear memory.
#export_name("decode_mem")
pub fn decode_mem(addr : Int32, len : Int32) -> Int32 {
  decode_all(bytes_from_mem(addr, len)[:])
}

///|
/// Only the copy step of `decode_mem`, to separate its cost in the bench.
#export_name("copy_mem")
pub fn copy_mem(addr : Int32, len : Int32) -> Int32 {
  bytes_from_mem(addr, len).length()
}

///|
/// `decode_mem` with only the steps in `mode` (bit 0 properties, bit 1 geometry).
#export_name("decode_mem_parts")
pub fn decode_mem_parts(addr : Int32, len : Int32, mode : Int32) -> Int32 {
  decode_parts(bytes_from_mem(addr, len)[:], mode)
}
