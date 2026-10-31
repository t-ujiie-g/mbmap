// Memory layout: page 0 is left to MoonBit; input (a tile or the style JSON)
// starts at INPUT_ADDR, output (a packed tile or an error message) follows it.

///|
extern "wasm" fn load_u8(addr : Int32) -> Int32 =
  #|(func (param i32) (result i32) (i32.load8_u (local.get 0)))

///|
extern "wasm" fn load_i32(addr : Int32) -> Int32 =
  #|(func (param i32) (result i32) (i32.load align=1 (local.get 0)))

///|
extern "wasm" fn store_i32(addr : Int32, v : Int32) =
  #|(func (param i32) (param i32) (i32.store align=1 (local.get 0) (local.get 1)))

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
const INPUT_ADDR : Int32 = PAGE

///|
let input_len : Ref[Int32] = Ref(0)

///|
let processor : Ref[TileProcessor?] = Ref(None)

///|
/// Grows linear memory to at least `bytes`; false if the engine refuses.
fn ensure_memory(bytes : Int32) -> Bool {
  let have = memory_size() * PAGE
  if bytes <= have {
    return true
  }
  memory_grow((bytes - have + PAGE - 1) / PAGE) >= 0
}

///|
fn output_start() -> Int32 {
  (INPUT_ADDR + input_len.val + 7) / 8 * 8
}

///|
/// Makes room for `len` input bytes and returns where JS should write them.
#export_name("prepare_input")
pub fn prepare_input(len : Int32) -> Int32 {
  if len < 0 || len > MAX_PACKED_BYTES || !ensure_memory(INPUT_ADDR + len) {
    return -1
  }
  input_len.val = len
  INPUT_ADDR
}

///|
/// Where the last call's output (packed tile or error message) starts.
#export_name("output_addr")
pub fn output_addr() -> Int32 {
  output_start()
}

///|
fn input_bytes() -> Bytes {
  let len = input_len.val
  let arr = FixedArray::make(len, b'\x00')
  let words = len / 4
  for w in 0..<words {
    let v = load_i32(INPUT_ADDR + w * 4)
    let i = w * 4
    arr[i] = v.to_byte()
    arr[i + 1] = (v >> 8).to_byte()
    arr[i + 2] = (v >> 16).to_byte()
    arr[i + 3] = (v >> 24).to_byte()
  }
  for i in (words * 4)..<len {
    arr[i] = load_u8(INPUT_ADDR + i).to_byte()
  }
  // Nothing else holds `arr`, so the reinterpretation cannot be observed mutating.
  arr.unsafe_reinterpret_as_bytes()
}

///|
/// Copies `bytes` to the output area; returns its length, or -1 without memory.
fn write_output(bytes : ArrayView[Byte]) -> Int32 {
  let at = output_start()
  let len = bytes.length()
  if !ensure_memory(at + len) {
    return -1
  }
  let words = len / 4
  for w in 0..<words {
    let i = w * 4
    store_i32(
      at + i,
      bytes[i].to_int() |
      (bytes[i + 1].to_int() << 8) |
      (bytes[i + 2].to_int() << 16) |
      (bytes[i + 3].to_int() << 24),
    )
  }
  for i in (words * 4)..<len {
    store_u8(at + i, bytes[i].to_int())
  }
  len
}

///|
/// Writes `message` as UTF-8 to the output area; returns minus its length.
fn fail_with(message : Bytes) -> Int32 {
  -write_output(message[:].to_fixedarray()[:])
}

///|
/// Parses the style JSON placed as input. Returns 0, or minus the length of
/// a UTF-8 error message written at `output_addr`.
#export_name("init_style")
pub fn init_style() -> Int32 {
  try TileProcessor::from_utf8(input_bytes()[:]) catch {
    e => fail_with(@utf8.encode("\{Repr(e)}"))
  } noraise {
    p => {
      processor.val = Some(p)
      0
    }
  }
}

///|
/// Processes the tile placed as input for the style's source with index
/// `source` at zoom `z`. Returns the packed tile's length at `output_addr`, or
/// minus the length of a UTF-8 error message there.
#export_name("process_tile")
pub fn process_tile(source : Int32, z : Int32) -> Int32 {
  guard processor.val is Some(p) else {
    return fail_with(@utf8.encode("style not initialized"))
  }
  if source < 0 || source >= p.style.sources.length() {
    return fail_with(@utf8.encode("no source \{source}"))
  }
  if p.process(p.style.sources[source].id, input_bytes()[:], z) {
    write_output(p.out.bytes())
  } else {
    fail_with(p.error_utf8())
  }
}
