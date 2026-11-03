// Memory layout: page 0 is left to MoonBit; input (a tile or the compiled style)
// starts at INPUT_ADDR, output (a packed tile, written in place by its Store,
// or an error message) follows it.

///|
const INPUT_ADDR : Int32 = PAGE

///|
let input_len : Ref[Int32] = Ref(0)

///|
let processor : Ref[TileProcessor?] = Ref(None)

///|
/// Appends a UTF-16 code unit to the host's text (`wasmio/js/host.mjs`'s
/// `hostText`).
fn host_text_char(c : Int32) = "host" "text_char"

///|
/// `Number()` of the host's text, which it then empties.
fn host_text_number() -> Double = "host" "text_number"

///|
/// `to-number` of a string by the host's `Number()`, passed a code unit at a
/// time: the output area may hold a tile being packed.
fn host_text_number_of(s : String) -> Double {
  for i in 0..<s.length() {
    host_text_char(s[i].to_int())
  }
  host_text_number()
}

///|
/// The length of the host's `String(x)`, which `host_text_code` then reads.
fn host_number_text(x : Double) -> Int32 = "host" "number_text"

///|
fn host_text_code(i : Int32) -> Int32 = "host" "text_code"

///|
/// `String(x)` by the host, which keeps MoonBit's float printing out of the
/// module.
fn host_number_text_of(x : Double) -> String {
  let out = StringBuilder()
  for i in 0..<host_number_text(x) {
    out.write_char(host_text_code(i).unsafe_to_char())
  }
  out.to_string()
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
/// Copies `bytes` (an error message) to the output area; returns its length,
/// or -1 without memory.
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
/// Reads the compiled style (`@style.Style::to_compiled`) placed as input.
/// Returns 0, or minus the length of a UTF-8 error message written at
/// `output_addr`.
#export_name("init_style")
pub fn init_style() -> Int32 {
  try
    TileProcessor::from_compiled(
      input_bytes()[:],
      text_number=host_text_number_of,
      number_text=host_number_text_of,
      trig=host_trig(),
    )
  catch {
    e => fail_with(@utf8.encode(e.message()))
  } noraise {
    p => {
      processor.val = Some(p)
      0
    }
  }
}

///|
/// Turns the RGBA input (a `size` x `size` tile of DEM source `source` at zoom
/// `z`) into `TileProcessor::dem_tile`'s output at `output_addr`. Returns its
/// length, or minus an error message's.
#export_name("process_dem")
pub fn process_dem(source : Int32, z : Int32, size : Int32) -> Int32 {
  guard processor.val is Some(p) else {
    return fail_with(@utf8.encode("style not initialized"))
  }
  match p.dem_tile(source, input_bytes()[:], size, z) {
    Some(slopes) => write_output(slopes[:].to_fixedarray()[:])
    None => fail_with(p.error_utf8())
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
  p.out.place_at(output_start())
  if p.process(p.style.sources[source].id, input_bytes()[:], z) {
    p.out.length()
  } else {
    fail_with(p.error_utf8())
  }
}

///|
/// Answers a query: the input holds the tile (`tile_len` bytes, source `source`,
/// zoom `z`), then the request (`TileProcessor::query`). Returns the result's
/// length at `output_addr`, or minus an error message's.
#export_name("query_tile")
pub fn query_tile(source : Int32, z : Int32, tile_len : Int32) -> Int32 {
  guard processor.val is Some(p) else {
    return fail_with(@utf8.encode("style not initialized"))
  }
  let input = input_bytes()
  if source < 0 ||
    source >= p.style.sources.length() ||
    tile_len < 0 ||
    tile_len > input.length() {
    return fail_with(@utf8.encode("bad query"))
  }
  match
    p.query(p.style.sources[source].id, input[:tile_len], z, input[tile_len:]) {
    Some(out) => write_output(out[:].to_fixedarray()[:])
    None => fail_with(p.error_utf8())
  }
}

///|
/// A source layer's features: the input holds the tile (`tile_len` bytes), then
/// the layer's name (a u32 length and UTF-8) and the filter
/// (`@style.write_expr`; `TileProcessor::source_features`). Returns as `query_tile` does.
#export_name("source_features")
pub fn source_features(source : Int32, z : Int32, tile_len : Int32) -> Int32 {
  guard processor.val is Some(p) else {
    return fail_with(@utf8.encode("style not initialized"))
  }
  let input = input_bytes()
  if source < 0 ||
    source >= p.style.sources.length() ||
    tile_len < 0 ||
    tile_len > input.length() {
    return fail_with(@utf8.encode("bad query"))
  }
  let r = @core.ByteReader::new(input[tile_len:])
  let layer = r.utf8()
  let filter = @style.read_expr(r)
  guard r.done() else { return fail_with(@utf8.encode("bad query")) }
  match
    p.source_features(
      p.style.sources[source].id,
      input[:tile_len],
      z,
      layer,
      filter,
    ) {
    Some(out) => write_output(out[:].to_fixedarray()[:])
    None => fail_with(p.error_utf8())
  }
}

///|
/// The feature ranges of the tile `process_tile` packed last
/// (`TileProcessor::feature_ranges`) at `output_addr`; returns their length.
#export_name("feature_ranges")
pub fn feature_ranges() -> Int32 {
  guard processor.val is Some(p) else {
    return fail_with(@utf8.encode("style not initialized"))
  }
  write_output(p.feature_ranges()[:].to_fixedarray()[:])
}
