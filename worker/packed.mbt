///|
/// `PackedTile` layer kinds, as the renderer reads them.
pub const KIND_FILL : Int32 = 1

///|
pub const KIND_LINE : Int32 = 2

///|
/// Circles share the line vertex layout: a quad per point whose extrusion
/// is ±`@tess.EXTRUDE_SCALE` (see `@tess.add_points`).
pub const KIND_CIRCLE : Int32 = 3

///|
/// Labels of a symbol layer: the entry's vertex range holds them (docs/FORMATS.md,
/// "Labels"); the worker glue lays them out into glyph quads.
pub const KIND_SYMBOL : Int32 = 4

///|
/// Extruded polygons (`@tess.ExtrusionBuffers`), `EXTRUSION_VERTEX_BYTES` per vertex.
pub const KIND_EXTRUSION : Int32 = 6

///|
/// Bytes per packed fill vertex: x, y as Int16.
pub const FILL_VERTEX_BYTES : Int32 = 4

///|
/// Bytes per packed line vertex: x, y as Int16; extrusion x, y, side and
/// along as Int8 (see `@tess.LINE_VERTEX_STRIDE`).
pub const LINE_VERTEX_BYTES : Int32 = 8

///|
/// Bytes per packed extrusion vertex: x, y, normal x, y, z, wall distance,
/// centroid x, y as Int16 (see `@tess.EXTRUSION_VERTEX_STRIDE`), then base and
/// height at the tile's zoom and one deeper as Uint16 decimeters (0 to 6553.5 m).
pub const EXTRUSION_VERTEX_BYTES : Int32 = 24

///|
/// u32s per layer entry (docs/FORMATS.md, "Packed tile").
pub const LAYER_ENTRY_WORDS : Int32 = 21

///|
/// Largest packed tile; a bigger one is rejected rather than allocated.
pub const MAX_PACKED_BYTES : Int32 = 64 * 1024 * 1024

///|
/// One tile's GPU-ready buffers in one blob (docs/FORMATS.md, "Packed tile").
/// Reused across tiles.
pub struct PackedTile {
  priv store : Store
  priv mut len : Int32
  priv mut layers : Int32
  priv mut overflow : Bool
}

///|
pub fn PackedTile::new() -> PackedTile {
  { store: Store::new(), len: 0, layers: 0, overflow: false, }
}

///|
/// Bytes of the last packed tile (a copy, for tests and debugging).
pub fn PackedTile::to_bytes(self : PackedTile) -> Bytes {
  self.store.copy_out(self.len)
}

///|
/// Length in bytes of the last packed tile.
pub fn PackedTile::length(self : PackedTile) -> Int32 {
  self.len
}

///|
/// Layers written so far.
pub fn PackedTile::layer_count(self : PackedTile) -> Int32 {
  self.layers
}

///|
/// Whether the last tile hit `MAX_PACKED_BYTES`.
fn PackedTile::overflowed(self : PackedTile) -> Bool {
  self.overflow
}

///|
fn PackedTile::reserve(self : PackedTile, extra : Int32) -> Bool {
  let need = self.len + extra
  if need > MAX_PACKED_BYTES || !self.store.ensure(need, self.len) {
    self.overflow = true
    return false
  }
  true
}

///|
fn PackedTile::put_u32(self : PackedTile, at : Int32, v : Int32) -> Unit {
  self.store.set_u32(at, v)
}

///|
fn PackedTile::put_i16(self : PackedTile, at : Int32, v : Int32) -> Unit {
  self.store.set_u16(at, @cmp.maximum(-32768, @cmp.minimum(32767, v)))
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
/// Starts a tile that will hold at most `max_layers` layer entries.
fn PackedTile::begin(self : PackedTile, max_layers : Int32) -> Unit {
  self.len = 0
  self.layers = 0
  self.overflow = false
  let header = 4 + max_layers * LAYER_ENTRY_WORDS * 4
  if self.reserve(header) {
    self.store.zero(0, header)
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
    for i, v in indices {
      self.store.set_u16(at + i * 2, v)
    }
  } else {
    for i, v in indices {
      self.put_u32(at + i * 4, v)
    }
  }
}

///|
/// Appends a fill layer; returns false if the tile would exceed `MAX_PACKED_BYTES`.
fn PackedTile::add_fill(
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
  // The outline's line list, in the same index size.
  let lines = fills.outline
  if !self.reserve((lines.length() * index_bytes + 3) / 4 * 4) {
    return false
  }
  let at = self.len
  self.put_indices(at, lines, index_bytes)
  let e = 4 + (self.layers - 1) * LAYER_ENTRY_WORDS * 4
  self.put_u32(e + 44, at)
  self.put_u32(e + 48, lines.length())
  self.len = at + (lines.length() * index_bytes + 3) / 4 * 4
  true
}

///|
/// Meters as the Uint16 decimeters of an extrusion vertex, clamped.
fn decimeters(m : Double) -> Int32 {
  if m.is_nan() {
    0
  } else {
    (@cmp.maximum(0.0, @cmp.minimum(6553.5, m)) * 10.0).round().to_int()
  }
}

///|
/// Appends a fill-extrusion layer; returns false if the tile would exceed
/// `MAX_PACKED_BYTES`.
fn PackedTile::add_extrusion(
  self : PackedTile,
  style_layer : Int32,
  b : @tess.ExtrusionBuffers,
  extent~ : Int32 = @core.TILE_EXTENT,
) -> Bool {
  let n = b.num_vertices()
  guard self.entry(
      style_layer,
      KIND_EXTRUSION,
      n * EXTRUSION_VERTEX_BYTES,
      n,
      b.indices.length(),
    )
    is Some((vstart, istart, index_bytes)) else {
    return false
  }
  let v = b.vertices
  let s = @tess.EXTRUSION_VERTEX_STRIDE
  let h = @tess.EXTRUSION_HEIGHTS
  for i in 0..<n {
    let at = vstart + i * EXTRUSION_VERTEX_BYTES
    self.put_i16(at, rescale(v[i * s], extent))
    self.put_i16(at + 2, rescale(v[i * s + 1], extent))
    self.put_i16(at + 4, v[i * s + 2])
    self.put_i16(at + 6, v[i * s + 3])
    self.put_i16(at + 8, v[i * s + 4])
    self.put_i16(at + 10, v[i * s + 5])
    self.put_i16(at + 12, rescale(v[i * s + 6], extent))
    self.put_i16(at + 14, rescale(v[i * s + 7], extent))
    for k in 0..<h {
      self.store.set_u16(at + 16 + k * 2, decimeters(b.heights[i * h + k]))
    }
  }
  self.put_indices(istart, b.indices, index_bytes)
  true
}

///|
/// Appends a line layer; returns false if the tile would exceed `MAX_PACKED_BYTES`.
fn PackedTile::add_line(
  self : PackedTile,
  style_layer : Int32,
  lines : @tess.LineBuffers,
  extent~ : Int32 = @core.TILE_EXTENT,
) -> Bool {
  self.add_extruded(style_layer, KIND_LINE, lines, extent)
}

///|
/// Appends a circle layer (quads from `@tess.add_points`); returns false if
/// the tile would exceed `MAX_PACKED_BYTES`.
fn PackedTile::add_circles(
  self : PackedTile,
  style_layer : Int32,
  points : @tess.LineBuffers,
  extent~ : Int32 = @core.TILE_EXTENT,
) -> Bool {
  self.add_extruded(style_layer, KIND_CIRCLE, points, extent)
}

///|
fn PackedTile::add_extruded(
  self : PackedTile,
  style_layer : Int32,
  kind : Int32,
  lines : @tess.LineBuffers,
  extent : Int32,
) -> Bool {
  let n = lines.num_vertices()
  guard self.entry(
      style_layer,
      kind,
      n * LINE_VERTEX_BYTES,
      n,
      lines.indices.length(),
    )
    is Some((vstart, istart, index_bytes)) else {
    return false
  }
  let v = lines.vertices
  let s = @tess.LINE_VERTEX_STRIDE
  for i in 0..<n {
    let at = vstart + i * LINE_VERTEX_BYTES
    self.put_i16(at, rescale(v[i * s], extent))
    self.put_i16(at + 2, rescale(v[i * s + 1], extent))
    // Four Int8s, little-endian: extrusion x, y, side, along.
    self.store.set_u32(
      at + 4,
      (v[i * s + 2] & 0xff) |
      ((v[i * s + 3] & 0xff) << 8) |
      ((v[i * s + 4] & 0xff) << 16) |
      ((v[i * s + 5] & 0xff) << 24),
    )
  }
  self.put_indices(istart, lines.indices, index_bytes)
  self.put_distances(lines.distances) && self.put_offsets(lines.offsets)
}

///|
/// Writes a circle layer's runs of equal sort keys for the last entry: per run
/// its key (f64), first index and index count (u32s), up to `end` indices; false
/// without room.
fn PackedTile::put_key_runs(
  self : PackedTile,
  runs : Array[(Double, Int32)],
  end : Int32,
) -> Bool {
  if runs.is_empty() {
    return true
  }
  if !self.reserve(runs.length() * 16 + 4) {
    return false
  }
  let at = (self.len + 7) / 8 * 8
  for k, r in runs {
    let next = if k + 1 < runs.length() { runs[k + 1].1 } else { end }
    let bits = r.0.reinterpret_as_uint64()
    self.store.set_u32(at + k * 16, bits.to_int())
    self.store.set_u32(at + k * 16 + 4, (bits >> 32).to_int())
    self.store.set_u32(at + k * 16 + 8, r.1)
    self.store.set_u32(at + k * 16 + 12, next - r.1)
  }
  let e = 4 + (self.layers - 1) * LAYER_ENTRY_WORDS * 4
  self.put_u32(e + 76, at)
  self.put_u32(e + 80, runs.length())
  self.len = at + runs.length() * 16
  true
}

///|
/// Writes an offset line's offset normals as two Int8s per vertex for the last
/// entry; false without room.
fn PackedTile::put_offsets(self : PackedTile, o : Array[Int32]) -> Bool {
  if o.is_empty() {
    return true
  }
  let bytes = (o.length() + 3) / 4 * 4
  if !self.reserve(bytes) {
    return false
  }
  let at = self.len
  for i in 0..<(o.length() / 2) {
    self.store.set_u16(
      at + i * 2,
      (o[i * 2] & 0xff) | ((o[i * 2 + 1] & 0xff) << 8),
    )
  }
  let e = 4 + (self.layers - 1) * LAYER_ENTRY_WORDS * 4
  self.put_u32(e + 68, at)
  self.put_u32(e + 72, o.length() / 2)
  self.len = at + bytes
  true
}

///|
/// Writes a dashed line's distances along it as Uint16s for the last entry;
/// false without room.
fn PackedTile::put_distances(self : PackedTile, d : Array[Int32]) -> Bool {
  if d.is_empty() {
    return true
  }
  let bytes = (d.length() * 2 + 3) / 4 * 4
  if !self.reserve(bytes) {
    return false
  }
  let at = self.len
  for i, v in d {
    self.store.set_u16(at + i * 2, v)
  }
  let e = 4 + (self.layers - 1) * LAYER_ENTRY_WORDS * 4
  self.put_u32(e + 52, at)
  self.put_u32(e + 56, d.length())
  self.len = at + bytes
  true
}

///|
/// Appends a symbol layer's labels (`Labels::bytes`); returns false if the tile
/// would exceed `MAX_PACKED_BYTES`.
fn PackedTile::add_labels(
  self : PackedTile,
  style_layer : Int32,
  labels : Bytes,
) -> Bool {
  guard self.entry(style_layer, KIND_SYMBOL, labels.length(), 0, 0)
    is Some((vstart, _, _)) else {
    return false
  }
  for i, b in labels {
    self.store.set_u8(vstart + i, b.to_int())
  }
  true
}

///|
/// Appends an entry for `style_layer` that points at entry `of`'s buffers.
fn PackedTile::add_alias(
  self : PackedTile,
  style_layer : Int32,
  of : Int32,
) -> Unit {
  let src = 4 + of * LAYER_ENTRY_WORDS * 4
  let dst = 4 + self.layers * LAYER_ENTRY_WORDS * 4
  self.put_u32(dst, style_layer)
  // The geometry, its group's properties, outline, distances and offset
  // normals; per-vertex paint is each layer's own.
  for w in 1..<LAYER_ENTRY_WORDS {
    self.put_u32(dst + w * 4, self.store.get_u32(src + w * 4))
  }
  self.put_u32(dst + 36, 0)
  self.put_u32(dst + 40, 0)
  self.layers += 1
  self.put_u32(0, self.layers)
}

///|
/// Attaches `props` (docs/FORMATS.md, "Packed tile"), the properties shared by the last
/// entry's features, to it.
fn PackedTile::set_props(self : PackedTile, props : Bytes) -> Unit {
  if self.layers == 0 || !self.reserve(props.length() + 3) {
    // Without room the entry keeps length 0; reserve() has flagged overflow.
    return
  }
  let at = self.len
  for i, b in props {
    self.store.set_u8(at + i, b.to_int())
  }
  let e = 4 + (self.layers - 1) * LAYER_ENTRY_WORDS * 4
  self.put_u32(e + 28, at)
  self.put_u32(e + 32, props.length())
  self.len = (at + props.length() + 3) / 4 * 4
}

///|
/// Makes room for the last entry's per-vertex paint, `words` u32s, and returns
/// where to write them; None without room (overflow is flagged).
fn PackedTile::begin_paint(self : PackedTile, words : Int32) -> Int32? {
  if self.layers == 0 ||
    words > MAX_PACKED_BYTES / 4 ||
    !self.reserve(words * 4) {
    return None
  }
  let at = self.len
  let e = 4 + (self.layers - 1) * LAYER_ENTRY_WORDS * 4
  self.put_u32(e + 36, at)
  self.put_u32(e + 40, words * 4)
  self.len = at + words * 4
  Some(at)
}

///|
/// Writes a gradient line's progress for the last entry (docs/FORMATS.md,
/// "Packed tile"); false without room.
fn PackedTile::put_progress(
  self : PackedTile,
  lines : @tess.LineBuffers,
  g : GradientRows,
) -> Bool {
  let n = lines.progress.length()
  let rows = g.clips.length() / 2
  let bytes = n * 8 + rows * 16 + 8
  if self.layers == 0 || n != g.rows.length() || !self.reserve(bytes + 4) {
    return false
  }
  let at = (self.len + 7) / 8 * 8
  for i in 0..<n {
    self.store.set_u32(
      at + i * 8,
      Float::from_double(lines.progress[i]).reinterpret_as_int(),
    )
    self.store.set_u32(
      at + i * 8 + 4,
      Float::from_double(g.rows[i].to_double()).reinterpret_as_int(),
    )
  }
  let put_f64 = (o : Int32, v : Double) => {
    let b = v.reinterpret_as_int64()
    self.store.set_u32(o, b.to_int())
    self.store.set_u32(o + 4, (b >> 32).to_int())
  }
  for i, v in g.clips {
    put_f64(at + n * 8 + i * 8, v)
  }
  put_f64(at + n * 8 + rows * 16, g.longest)
  let e = 4 + (self.layers - 1) * LAYER_ENTRY_WORDS * 4
  self.put_u32(e + 60, at)
  self.put_u32(e + 64, rows)
  self.len = at + bytes
  true
}
