// Memory layout: page 0 is left to MoonBit; input (GeoJSON) starts at PAGE,
// output (an encoded tile or an error message) follows it.

///|
extern "wasm" fn load_u8(addr : Int32) -> Int32 =
  #|(func (param i32) (result i32) (i32.load8_u (local.get 0)))

///|
extern "wasm" fn load_i32(addr : Int32) -> Int32 =
  #|(func (param i32) (result i32) (i32.load align=1 (local.get 0)))

///|
extern "wasm" fn store_u8(addr : Int32, v : Int32) =
  #|(func (param i32) (param i32) (i32.store8 (local.get 0) (local.get 1)))

///|
extern "wasm" fn memory_size() -> Int32 =
  #|(func (result i32) (memory.size))

///|
extern "wasm" fn memory_grow(pages : Int32) -> Int32 =
  #|(func (param i32) (result i32) (memory.grow (local.get 0)))

///|
const PAGE : Int32 = 65536

///|
/// Largest GeoJSON accepted (AGENTS.md §8.2: limit the size before tiling).
pub const MAX_GEOJSON_BYTES : Int32 = 256 * 1024 * 1024

///|
let input_len : Ref[Int32] = Ref(0)

///|
fn ensure_memory(bytes : Int32) -> Bool {
  let have = memory_size() * PAGE
  bytes <= have || memory_grow((bytes - have + PAGE - 1) / PAGE) >= 0
}

///|
fn output_start() -> Int32 {
  (PAGE + input_len.val + 7) / 8 * 8
}

///|
/// Makes room for `len` input bytes and returns where JS should write them,
/// or -1 if `len` is too large.
#export_name("prepare_input")
pub fn prepare_input(len : Int32) -> Int32 {
  if len < 0 || len > MAX_GEOJSON_BYTES || !ensure_memory(PAGE + len) {
    return -1
  }
  input_len.val = len
  PAGE
}

///|
/// Where the last call's output starts.
#export_name("output_addr")
pub fn output_addr() -> Int32 {
  output_start()
}

///|
/// The input copied into a `Bytes`, four bytes per load.
fn input_bytes() -> Bytes {
  let len = input_len.val
  let arr = FixedArray::make(len, b'\x00')
  let words = len / 4
  for w in 0..<words {
    let v = load_i32(PAGE + w * 4)
    let i = w * 4
    arr[i] = v.to_byte()
    arr[i + 1] = (v >> 8).to_byte()
    arr[i + 2] = (v >> 16).to_byte()
    arr[i + 3] = (v >> 24).to_byte()
  }
  for i in (words * 4)..<len {
    arr[i] = load_u8(PAGE + i).to_byte()
  }
  // Nothing else holds `arr`, so the reinterpretation cannot be observed mutating.
  arr.unsafe_reinterpret_as_bytes()
}

///|
/// Copies `bytes` to the output area; returns its length, or -1 without memory.
fn write_output(bytes : Bytes) -> Int32 {
  let at = output_start()
  if !ensure_memory(at + bytes.length()) {
    return -1
  }
  for i, b in bytes {
    store_u8(at + i, b.to_int())
  }
  bytes.length()
}
