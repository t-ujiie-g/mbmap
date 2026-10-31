///|
/// `PackedTile` layer kinds, as the renderer reads them.
pub const KIND_FILL : Int32 = 1

///|
pub const KIND_LINE : Int32 = 2

///|
/// Bytes per packed fill vertex: x, y as Int16.
pub const FILL_VERTEX_BYTES : Int32 = 4

///|
/// Bytes per packed line vertex: x, y as Int16; extrusion x, y, side and
/// along as Int8 (see `@tess.LINE_VERTEX_STRIDE`).
pub const LINE_VERTEX_BYTES : Int32 = 8

///|
/// Ints per layer entry in the header: style layer index, kind, vertex byte
/// offset, vertex byte length, index byte offset, index count, bytes per
/// index (2 when the layer has at most 65536 vertices, else 4).
pub const LAYER_ENTRY_WORDS : Int32 = 7

///|
/// Largest packed tile; a bigger one is rejected rather than allocated.
pub const MAX_PACKED_BYTES : Int32 = 64 * 1024 * 1024

///|
/// One tile's GPU-ready buffers, coordinates in `@core.TILE_EXTENT` units, in a single little-endian byte blob: a u32
/// layer count, `LAYER_ENTRY_WORDS` u32s per layer, then 4-byte aligned vertex
/// and index data at the offsets the entries give. Reused across tiles.
pub struct PackedTile {
  priv mut data : FixedArray[Byte]
  priv mut len : Int32
  priv mut layers : Int32
  priv mut overflow : Bool
}

///|
pub fn PackedTile::new() -> PackedTile {
  {
    data: FixedArray::make(64 * 1024, b'\x00'),
    len: 0,
    layers: 0,
    overflow: false,
  }
}

///|
pub fn PackedTile::bytes(self : PackedTile) -> ArrayView[Byte] {
  self.data[:self.len]
}

///|
/// Layers written so far.
pub fn PackedTile::layer_count(self : PackedTile) -> Int32 {
  self.layers
}

///|
/// Whether the last tile hit `MAX_PACKED_BYTES`.
pub fn PackedTile::overflowed(self : PackedTile) -> Bool {
  self.overflow
}

///|
fn PackedTile::reserve(self : PackedTile, extra : Int32) -> Bool {
  let need = self.len + extra
  if need > MAX_PACKED_BYTES {
    self.overflow = true
    return false
  }
  if need > self.data.length() {
    let cap = @cmp.minimum(
      MAX_PACKED_BYTES,
      @cmp.maximum(need, self.data.length() * 2),
    )
    let grown = FixedArray::make(cap, b'\x00')
    FixedArray::blit_to(self.data, grown, len=self.len)
    self.data = grown
  }
  true
}

///|
fn PackedTile::put_u32(self : PackedTile, at : Int32, v : Int32) -> Unit {
  let d = self.data
  d[at] = v.to_byte()
  d[at + 1] = (v >> 8).to_byte()
  d[at + 2] = (v >> 16).to_byte()
  d[at + 3] = (v >> 24).to_byte()
}

///|
fn PackedTile::put_i16(self : PackedTile, at : Int32, v : Int32) -> Unit {
  let v = @cmp.maximum(-32768, @cmp.minimum(32767, v))
  self.data[at] = v.to_byte()
  self.data[at + 1] = (v >> 8).to_byte()
}

///|
/// Converts a coordinate of a layer with `extent` units to `TILE_EXTENT` units.
fn rescale(v : Int32, extent : Int32) -> Int32 {
  if extent == @core.TILE_EXTENT || extent <= 0 {
    v
  } else {
    (v.to_double() * @core.TILE_EXTENT.to_double() / extent.to_double())
    .round()
    .to_int()
  }
}

///|
/// Starts a tile that will hold at most `max_layers` layers.
pub fn PackedTile::begin(self : PackedTile, max_layers : Int32) -> Unit {
  self.len = 0
  self.layers = 0
  self.overflow = false
  let header = 4 + max_layers * LAYER_ENTRY_WORDS * 4
  if self.reserve(header) {
    self.data.fill(b'\x00', start=0, end=header)
    self.len = header
  }
}

///|
fn PackedTile::entry(
  self : PackedTile,
  style_layer : Int32,
  kind : Int32,
  vertex_bytes : Int32,
  vertices : Int32,
  index_count : Int32,
) -> (Int32, Int32, Int32)? {
  let vertex_bytes = (vertex_bytes + 3) / 4 * 4
  let index_bytes = if vertices <= 65536 { 2 } else { 4 }
  if !self.reserve(vertex_bytes + (index_count * index_bytes + 3) / 4 * 4) {
    return None
  }
  let vstart = self.len
  let istart = vstart + vertex_bytes
  let e = 4 + self.layers * LAYER_ENTRY_WORDS * 4
  self.put_u32(e, style_layer)
  self.put_u32(e + 4, kind)
  self.put_u32(e + 8, vstart)
  self.put_u32(e + 12, vertex_bytes)
  self.put_u32(e + 16, istart)
  self.put_u32(e + 20, index_count)
  self.put_u32(e + 24, index_bytes)
  self.layers += 1
  self.put_u32(0, self.layers)
  self.len = istart + (index_count * index_bytes + 3) / 4 * 4
  Some((vstart, istart, index_bytes))
}

///|
fn PackedTile::put_indices(
  self : PackedTile,
  at : Int32,
  indices : Array[Int32],
  index_bytes : Int32,
) -> Unit {
  if index_bytes == 2 {
    let d = self.data
    for i, v in indices {
      d[at + i * 2] = v.to_byte()
      d[at + i * 2 + 1] = (v >> 8).to_byte()
    }
  } else {
    for i, v in indices {
      self.put_u32(at + i * 4, v)
    }
  }
}

///|
/// Appends a fill layer; returns false if the tile would exceed `MAX_PACKED_BYTES`.
pub fn PackedTile::add_fill(
  self : PackedTile,
  style_layer : Int32,
  fills : @tess.FillBuffers,
  extent~ : Int32 = @core.TILE_EXTENT,
) -> Bool {
  let n = fills.num_vertices()
  guard self.entry(
      style_layer,
      KIND_FILL,
      n * FILL_VERTEX_BYTES,
      n,
      fills.indices.length(),
    )
    is Some((vstart, istart, index_bytes)) else {
    return false
  }
  let v = fills.vertices
  for i in 0..<n {
    self.put_i16(vstart + i * 4, rescale(v[i * 2], extent))
    self.put_i16(vstart + i * 4 + 2, rescale(v[i * 2 + 1], extent))
  }
  self.put_indices(istart, fills.indices, index_bytes)
  true
}

///|
/// Appends a line layer; returns false if the tile would exceed `MAX_PACKED_BYTES`.
pub fn PackedTile::add_line(
  self : PackedTile,
  style_layer : Int32,
  lines : @tess.LineBuffers,
  extent~ : Int32 = @core.TILE_EXTENT,
) -> Bool {
  let n = lines.num_vertices()
  guard self.entry(
      style_layer,
      KIND_LINE,
      n * LINE_VERTEX_BYTES,
      n,
      lines.indices.length(),
    )
    is Some((vstart, istart, index_bytes)) else {
    return false
  }
  let v = lines.vertices
  let s = @tess.LINE_VERTEX_STRIDE
  let d = self.data
  for i in 0..<n {
    let at = vstart + i * LINE_VERTEX_BYTES
    self.put_i16(at, rescale(v[i * s], extent))
    self.put_i16(at + 2, rescale(v[i * s + 1], extent))
    d[at + 4] = v[i * s + 2].to_byte()
    d[at + 5] = v[i * s + 3].to_byte()
    d[at + 6] = v[i * s + 4].to_byte()
    d[at + 7] = v[i * s + 5].to_byte()
  }
  self.put_indices(istart, lines.indices, index_bytes)
  true
}
