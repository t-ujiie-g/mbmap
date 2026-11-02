// Memory layout: page 0 is left to MoonBit; input (a tile or the style JSON)
// starts at INPUT_ADDR, output (a packed tile, written in place by its Store,
// or an error message) follows it.

///|
const INPUT_ADDR : Int32 = PAGE

///|
let input_len : Ref[Int32] = Ref(0)

///|
let processor : Ref[TileProcessor?] = Ref(None)

///|
/// The JSON number (ASCII) at `[addr, addr + len)` of linear memory, by the
/// host's `Number()` (worker/js/worker.mjs passes `wasmio/js/host.mjs`'s).
fn host_number(addr : Int32, len : Int32) -> Double = "host" "number"

///|
/// A JSON number's text parsed by the host: placed in the output area first,
/// which keeps core `strconv` out of the module.
fn host_number_of(text : BytesView) -> Double {
  let at = output_start()
  if !ensure_memory(at + text.length()) {
    return @double.not_a_number
  }
  for i, b in text {
    store_u8(at + i, b.to_int())
  }
  host_number(at, text.length())
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
/// Parses the style JSON placed as input. Returns 0, or minus the length of
/// a UTF-8 error message written at `output_addr`.
#export_name("init_style")
pub fn init_style() -> Int32 {
  try TileProcessor::from_utf8(input_bytes()[:], number=host_number_of) catch {
    e => fail_with(@utf8.encode(e.message()))
  } noraise {
    p => {
      processor.val = Some(p)
      0
    }
  }
}

///|
/// Turns the RGBA pixels placed as input (a `size` x `size` tile of the
/// `raster-dem` source with index `source`, at zoom `z`) into what its hillshade
/// layers need (`TileProcessor::dem_tile`) at `output_addr`. Returns their length, or minus the length
/// of a UTF-8 error message there.
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
/// Answers a query of a tile: the input holds the tile (`tile_len` bytes) of
/// the source with index `source` at zoom `z`, then the request
/// (`TileProcessor::query`). Returns the result's length at `output_addr`, or
/// minus the length of a UTF-8 error message there.
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
/// The features of a tile's source layer: the input holds the tile (`tile_len`
/// bytes) of the source with index `source` at zoom `z`, then the source
/// layer's name and a filter's JSON, each a u32 length and UTF-8
/// (`TileProcessor::source_features`). Returns as `query_tile` does.
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
  let filter = r.utf8()
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
