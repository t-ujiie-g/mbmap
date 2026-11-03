///|
extern "wasm" fn load_u8(addr : Int32) -> Int32 =
  #|(func (param i32) (result i32) (i32.load8_u (local.get 0)))

///|
extern "wasm" fn load_i32(addr : Int32) -> Int32 =
  #|(func (param i32) (result i32) (i32.load align=1 (local.get 0)))

///|
extern "wasm" fn memory_grow(pages : Int32) -> Int32 =
  #|(func (param i32) (result i32) (memory.grow (local.get 0)))

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

///|
/// `tessellate_tile` on the tile at `addr`, after copying it into wasm.
#export_name("tess_mem")
pub fn tess_mem(addr : Int32, len : Int32, mode : Int32) -> Int32 {
  tessellate_tile(bytes_from_mem(addr, len)[:], mode)
}

///|
/// Hash over all features' fills (see `fill_hash`) of the tile at `addr`.
#export_name("fill_hash_mem")
pub fn fill_hash_mem(addr : Int32, len : Int32) -> Int32 {
  fill_hash(bytes_from_mem(addr, len)[:], [])
}

///|
/// `build_tiler` on GeoJSON at `[addr, addr + len)`; `wrap` is 0 or 1.
#export_name("geojson_tiler_mem")
pub fn geojson_tiler_mem(
  addr : Int32,
  len : Int32,
  max_zoom : Int32,
  index_max_zoom : Int32,
  index_max_points : Int32,
  tolerance : Double,
  extent : Int32,
  buffer : Int32,
  wrap : Int32,
) -> Int32 {
  build_tiler(
    bytes_from_mem(addr, len)[:],
    max_zoom,
    index_max_zoom,
    index_max_points,
    tolerance,
    extent,
    buffer,
    wrap != 0,
    host_trig(),
    slow_number=host_slow_number(addr),
  )
}

///|
/// `read_only` on GeoJSON at `[addr, addr + len)`.
#export_name("geojson_read_mem")
pub fn geojson_read_mem(addr : Int32, len : Int32) -> Int32 {
  read_only(bytes_from_mem(addr, len)[:], slow_number=host_slow_number(addr))
}

///|
extern "wasm" fn store_i32(addr : Int32, v : Int32) =
  #|(func (param i32) (param i32) (i32.store align=1 (local.get 0) (local.get 1)))

///|
/// Writes `geojson_tile(z, x, y)` as i32s at `addr` (growing memory as
/// needed) and returns its length.
#export_name("geojson_tile_mem")
pub fn geojson_tile_mem(z : Int32, x : Int32, y : Int32, addr : Int32) -> Int32 {
  let flat = geojson_tile(z, x, y)
  let need = addr + flat.length() * 4
  let have = memory_grow(0) * 65536
  if need > have {
    memory_grow((need - have + 65535) / 65536) |> ignore
  }
  for i, v in flat {
    store_i32(addr + i * 4, v)
  }
  flat.length()
}

///|
/// `table_tiler` on a table in `@geom.Table::to_bytes` form at
/// `[addr, addr + len)` (pipeline B of the GeoJSON bench).
#export_name("geojson_tiler_table_mem")
pub fn geojson_tiler_table_mem(
  addr : Int32,
  len : Int32,
  max_zoom : Int32,
  index_max_zoom : Int32,
  index_max_points : Int32,
  tolerance : Double,
  extent : Int32,
  buffer : Int32,
  wrap : Int32,
) -> Int32 {
  table_tiler(
    bytes_from_mem(addr, len)[:],
    {
      max_zoom,
      index_max_zoom,
      index_max_points,
      tolerance,
      extent,
      buffer,
      wrap: wrap != 0,
    },
    host_trig(),
  )
}

///|
/// `words_hash` of `clip_words` on input i32s at `[addr, addr + len)`.
#export_name("clip_hash_mem")
pub fn clip_hash_mem(
  addr : Int32,
  len : Int32,
  op : Int32,
  fill : Int32,
  tree : Int32,
) -> Int32 {
  words_hash(
    clip_words(words_of(bytes_from_mem(addr, len)[:]), op, fill, tree=tree != 0),
  )
}

///|
/// `words_hash` of `offset_words` on input i32s at `[addr, addr + len)`.
#export_name("offset_hash_mem")
pub fn offset_hash_mem(
  addr : Int32,
  len : Int32,
  delta : Double,
  join : Int32,
  end : Int32,
  miter_limit : Double,
  arc_tolerance : Double,
) -> Int32 {
  words_hash(
    offset_words(
      words_of(bytes_from_mem(addr, len)[:]),
      delta,
      join,
      end,
      miter_limit,
      arc_tolerance,
    ),
  )
}

///|
/// FNV-1a over 32-bit words.
fn words_hash(words : Array[Int32]) -> Int32 {
  let mut h = 0x811c9dc5
  for v in words {
    h = (h ^ v) * 0x01000193
  }
  h
}

///|
extern "wasm" fn store_f64(addr : Int32, v : Double) =
  #|(func (param i32) (param f64) (f64.store align=1 (local.get 0) (local.get 1)))

///|
/// Writes `proj_coords` (with the host's `Math`) on `[addr, addr + len)` as f64s at `out`
/// (growing memory as needed); returns how many.
#export_name("proj_mem")
pub fn proj_mem(
  addr : Int32,
  len : Int32,
  from : Int32,
  to : Int32,
  out : Int32,
) -> Int32 {
  let values = proj_coords(
    bytes_from_mem(addr, len)[:],
    from,
    to,
    trig=host_trig(),
  )
  let need = out + values.length() * 8
  let have = memory_grow(0) * 65536
  if need > have {
    memory_grow((need - have + 65535) / 65536) |> ignore
  }
  for i, v in values {
    store_f64(out + i * 8, v)
  }
  values.length()
}
