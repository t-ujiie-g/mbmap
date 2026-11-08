///|
extern "wasm" fn store_u8(addr : Int32, v : Int32) =
  #|(func (param i32) (param i32) (i32.store8 (local.get 0) (local.get 1)))

///|
/// `meshopt_decode` of `[addr, addr + len)` into `[out, out + count * size)` of linear
/// memory: 1 when decoded, 0 when not. The caller guarantees both ranges are in memory.
#export_name("meshopt_decode_mem")
pub fn meshopt_decode_mem(
  addr : Int32,
  len : Int32,
  out : Int32,
  count : Int32,
  size : Int32,
  mode : Int32,
  filter : Int32,
) -> Int32 {
  let source = FixedArray::make(len, b'\x00')
  for i in 0..<len {
    source[i] = load_u8(addr + i).to_byte()
  }
  let target = FixedArray::make(count * size, b'\x00')
  if !meshopt_decode(target, count, size, source, mode, filter) {
    return 0
  }
  for i in 0..<target.length() {
    store_u8(out + i, target[i].to_int())
  }
  1
}
