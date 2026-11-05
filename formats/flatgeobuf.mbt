// Ported from flatgeobuf 4.6.1: BSD License, Copyright (c) 2018, Björn Harrtell. See NOTICE.

///|
/// Bytes a FlatGeobuf file starts with; flatgeobuf checks no version byte after them.
let fgb_magic : Bytes = b"fgb"

///|
/// Largest FlatGeobuf header, flatgeobuf's `HEADER_MAX_BUFFER_SIZE`.
const MAX_FGB_HEADER_BYTES : Int32 = 10 * 1024 * 1024

///|
/// Bytes per node of a FlatGeobuf packed R-tree (four f64 and a u64 offset).
const FGB_NODE_BYTES : Int32 = 40

///|
/// Reads a FlatGeobuf file as flatgeobuf 4.6.1's `deserialize` does, collections
/// flattened, Z and M dropped. With `ids` (a feature index each), `bytes` holds the
/// header and only those features; otherwise the whole file, features numbered from 0.
pub fn read_flatgeobuf(
  bytes : BytesView,
  ids? : Array[Int32],
) -> @geom.Table raise ReadError {
  fgb_table(bytes, ids, MAX_POINTS)
}

///|
/// Reading state over one FlatBuffers buffer at a time (the header's, then each
/// feature's); errors are sticky as `Wkb`'s, `base` placing positions in the input.
priv struct Fgb {
  mut b : BytesView
  mut base : Int32
  mut error : (Int32, String)?
  names : Array[String]
  types : Array[Int32]
  shapes : Shapes
  props : Array[(String, @geom.Prop)]
  max_points : Int32
  mut used : Int32
}

///|
fn Fgb::fail(self : Fgb, at : Int32, message : String) -> Unit {
  if self.error is None {
    self.error = Some((self.base + at, message))
  }
}

///|
/// Whether `n` bytes at `at` are in the buffer; fails if not.
fn Fgb::has(self : Fgb, at : Int32, n : Int32) -> Bool {
  if at < 0 || n < 0 || at > self.b.length() - n {
    self.fail(@cmp.maximum(at, 0), "offset past the end of the data")
    return false
  }
  true
}

///|
fn Fgb::u8(self : Fgb, at : Int32) -> Int32 {
  if self.has(at, 1) {
    self.b[at].to_int()
  } else {
    0
  }
}

///|
fn Fgb::u16(self : Fgb, at : Int32) -> Int32 {
  if self.has(at, 2) {
    self.b[at].to_int() | (self.b[at + 1].to_int() << 8)
  } else {
    0
  }
}

///|
fn Fgb::u32(self : Fgb, at : Int32) -> Int32 {
  if !self.has(at, 4) {
    return 0
  }
  let b = self.b
  b[at].to_int() |
  (b[at + 1].to_int() << 8) |
  (b[at + 2].to_int() << 16) |
  (b[at + 3].to_int() << 24)
}

///|
fn Fgb::u64(self : Fgb, at : Int32) -> UInt64 {
  let mut bits = 0UL
  if self.has(at, 8) {
    for i in 0..<8 {
      bits = bits | (self.b[at + i].to_uint64() << (i * 8))
    }
  }
  bits
}

///|
fn Fgb::f64(self : Fgb, at : Int32) -> Double {
  self.u64(at).reinterpret_as_double()
}

///|
/// The position of field `field` of the table at `table`, or -1 if it is absent
/// (FlatBuffers: a vtable of u16 slots before the table, 0 for a field not stored).
fn Fgb::field(self : Fgb, table : Int32, field : Int32) -> Int32 {
  let vtable = table - self.u32(table)
  let size = self.u16(vtable)
  let slot = 4 + field * 2
  if self.error is Some(_) || slot + 2 > size {
    return -1
  }
  let offset = self.u16(vtable + slot)
  if offset == 0 {
    -1
  } else {
    table + offset
  }
}

///|
/// The u8 field `field` of `table`, 0 if absent.
fn Fgb::u8_field(self : Fgb, table : Int32, field : Int32) -> Int32 {
  let at = self.field(table, field)
  if at < 0 {
    0
  } else {
    self.u8(at)
  }
}

///|
/// The position a u32 offset at `at` points to, -1 (failed) past the end.
fn Fgb::indirect(self : Fgb, at : Int32) -> Int32 {
  let offset = self.u32(at)
  if offset < 0 || !self.has(at + offset, 0) {
    self.fail(at, "offset past the end of the data")
    return -1
  }
  at + offset
}

///|
/// The table field `field` of `table` points to, or -1.
fn Fgb::table(self : Fgb, table : Int32, field : Int32) -> Int32 {
  let at = self.field(table, field)
  if at < 0 {
    -1
  } else {
    self.indirect(at)
  }
}

///|
/// Where the elements of vector field `field` of `table` start and how many of
/// `size` bytes it has; (0, 0) if absent or past the end (failed).
fn Fgb::vector(
  self : Fgb,
  table : Int32,
  field : Int32,
  size : Int32,
) -> (Int32, Int32) {
  let at = self.table(table, field)
  if at < 0 {
    return (0, 0)
  }
  let n = self.u32(at)
  if n < 0 || n > (self.b.length() - at - 4) / size {
    self.fail(at, "vector past the end of the data")
    return (0, 0)
  }
  (at + 4, n)
}

///|
/// UTF-8 at `at`, `n` bytes, as `TextDecoder` reads it (a leading BOM dropped).
fn Fgb::text(self : Fgb, at : Int32, n : Int32) -> String {
  if !self.has(at, n) {
    return ""
  }
  let bom = n >= 3 &&
    self.b[at] == b'\xef' &&
    self.b[at + 1] == b'\xbb' &&
    self.b[at + 2] == b'\xbf'
  let start = if bom { at + 3 } else { at }
  @core.utf8_lossy(self.b[start:at + n])
}

///|
/// The string field `field` of `table`, or None if absent.
fn Fgb::string(self : Fgb, table : Int32, field : Int32) -> String? {
  let (at, n) = self.vector(table, field, 1)
  if self.field(table, field) < 0 {
    None
  } else {
    Some(self.text(at, n))
  }
}

///|
/// The root table of a size-prefixed buffer.
fn Fgb::root(self : Fgb) -> Int32 {
  self.indirect(4)
}

///|
/// Bytes of a packed R-tree over `count` items of `node_size` children per node,
/// as flatgeobuf's `calcTreeSize` counts them; -1 past `limit`.
fn fgb_tree_bytes(count : Int64, node_size : Int32, limit : Int32) -> Int32 {
  let size = @cmp.minimum(@cmp.maximum(node_size, 2), 65535).to_int64()
  let mut n = count
  let mut nodes = count
  while n > 1L {
    n = (n + size - 1L) / size
    nodes += n
    if nodes * FGB_NODE_BYTES.to_int64() > limit.to_int64() {
      return -1
    }
  }
  if count == 1L {
    nodes += 1L
  }
  if nodes * FGB_NODE_BYTES.to_int64() > limit.to_int64() {
    -1
  } else {
    (nodes * FGB_NODE_BYTES.to_int64()).to_int()
  }
}

///|
/// `read_flatgeobuf` taking at most `max_points` points.
fn fgb_table(
  bytes : BytesView,
  ids : Array[Int32]?,
  max_points : Int32,
) -> @geom.Table raise ReadError {
  let p : Fgb = {
    b: bytes,
    base: 0,
    error: None,
    names: [],
    types: [],
    shapes: Shapes::new(),
    props: [],
    max_points,
    used: 0,
  }
  let fail = (pos, m) => raise Invalid(format="FlatGeobuf", pos~, m)
  if bytes.length() < 12 || bytes[:3] != fgb_magic[:] {
    fail(0, "not a FlatGeobuf file")
  }
  let length = p.u32(8)
  if length < 8 || length > MAX_FGB_HEADER_BYTES || length > bytes.length() - 12 {
    fail(8, "invalid header size")
  }
  p.b = bytes[8:12 + length]
  p.base = 8
  let header = p.root()
  let geometry_type = p.u8_field(header, 2)
  let (columns, n) = p.vector(header, 7, 4)
  for i in 0..<n {
    let column = p.indirect(columns + i * 4)
    match p.string(column, 0) {
      Some(name) => p.names.push(name)
      None => p.fail(column, "a column without a name")
    }
    p.types.push(p.u8_field(column, 1))
  }
  let count_at = p.field(header, 8)
  let count = if count_at < 0 { 0UL } else { p.u64(count_at) }
  let size_at = p.field(header, 9)
  let node_size = if size_at < 0 { 16 } else { p.u16(size_at) }
  if p.error is Some((pos, m)) {
    fail(pos, m)
  }
  let mut at = 12 + length
  if ids is None && node_size > 0 {
    let tree = fgb_tree_bytes(
      count.reinterpret_as_int64(),
      node_size,
      bytes.length() - at,
    )
    if count > 0x7fffffffUL || tree < 0 {
      fail(at, "index past the end of the data")
    }
    at += tree
  }
  let out = @geom.TableBuilder::new()
  let mut index = 0
  while at < bytes.length() {
    p.b = bytes
    p.base = 0
    let n = p.u32(at)
    if n < 0 || n > bytes.length() - at - 4 {
      fail(at, "feature past the end of the data")
    }
    p.b = bytes[at:at + 4 + n]
    p.base = at
    let id = match ids {
      Some(ids) if index < ids.length() => ids[index]
      Some(_) => {
        fail(at, "more features than ids")
        0
      }
      None => index
    }
    p.feature(geometry_type)
    if p.error is Some((pos, m)) {
      fail(pos, m)
    }
    p.used += p.shapes.points()
    p.shapes.emit(out, p.props, None, id=Some(@geom.Num(id.to_double())))
    at += 4 + n
    index += 1
  }
  out.finish()
}

///|
/// Reads the feature in `b` into `shapes` and `props`.
fn Fgb::feature(self : Fgb, geometry_type : Int32) -> Unit {
  self.shapes.clear()
  self.props.clear()
  let feature = self.root()
  let geometry = self.table(feature, 0)
  if geometry >= 0 {
    self.geometry(geometry, geometry_type, 0)
  }
  let (at, n) = self.vector(feature, 1, 1)
  if self.names.length() > 0 {
    self.properties(at, at + n)
  }
}

///|
/// Reads the geometry table at `g` as flatgeobuf's `fromGeometry` does, `kind` the
/// header's geometry type (0 for each geometry's own).
fn Fgb::geometry(self : Fgb, g : Int32, kind : Int32, depth : Int32) -> Unit {
  if depth > MAX_GEOMETRY_DEPTH {
    self.fail(g, "collections nested too deep")
    return
  }
  let kind = if kind == 0 { self.u8_field(g, 6) } else { kind }
  match kind {
    6 | 7 => {
      let (parts, n) = self.vector(g, 7, 4)
      for i in 0..<n {
        let part = self.indirect(parts + i * 4)
        if self.error is Some(_) {
          return
        }
        if kind == 6 {
          self.rings(part, false)
          self.shapes.end_part()
        } else {
          self.geometry(part, 0, depth + 1)
        }
      }
      if kind == 6 {
        self.shapes.end_member(MultiPolygon)
      }
    }
    1 => {
      let (xy, n) = self.vector(g, 1, 8)
      if n >= 2 {
        self.position(xy)
      }
      self.shapes.end_ring()
      self.shapes.end_part()
      self.shapes.end_member(Point)
    }
    2 | 4 => {
      let (xy, n) = self.vector(g, 1, 8)
      for i in 0..<(n / 2) {
        self.position(xy + i * 16)
      }
      self.shapes.end_ring()
      self.shapes.end_part()
      self.shapes.end_member(if kind == 2 { LineString } else { MultiPoint })
    }
    3 => {
      self.rings(g, false)
      self.shapes.end_part()
      self.shapes.end_member(Polygon)
    }
    5 => {
      self.rings(g, true)
      self.shapes.end_member(MultiLineString)
    }
    _ => self.fail(g, "unsupported geometry type \{kind}")
  }
}

///|
/// The rings (or lines) of the geometry at `g`: its points cut at its `ends`, as
/// flatgeobuf's `extractParts` slices them (all one ring without ends); `lines`
/// makes each a part of its own, as `Wkb::body` makes a line.
fn Fgb::rings(self : Fgb, g : Int32, lines : Bool) -> Unit {
  let (xy, doubles) = self.vector(g, 1, 8)
  let n = doubles / 2
  let (ends, e) = self.vector(g, 0, 4)
  let mut start = 0
  for k in 0..<@cmp.maximum(e, 1) {
    let end = if e == 0 { n } else { self.u32(ends + k * 4) }
    let stop = if end < 0 { n } else { @cmp.minimum(end, n) }
    for i in start..<stop {
      self.position(xy + i * 16)
    }
    self.shapes.end_ring()
    if lines {
      self.shapes.end_part()
    }
    start = if end < 0 { n } else { end }
  }
}

///|
/// The x, y pair at `at`; NaN for both is an empty point, other non-finite values are refused.
fn Fgb::position(self : Fgb, at : Int32) -> Unit {
  let x = self.f64(at)
  let y = self.f64(at + 8)
  if x.is_nan() && y.is_nan() {
    return
  }
  if x.is_nan() || x.is_inf() || y.is_nan() || y.is_inf() {
    self.fail(at, "non-finite coordinate")
    return
  }
  if self.used + self.shapes.points() >= self.max_points {
    self.fail(at, "too many points")
    return
  }
  self.shapes.point(x, y)
}

///|
/// The properties in bytes `at..<end`: a u16 column index and its value each, as
/// flatgeobuf's `parseProperties` reads them (Json kept as its text, Binary as base64).
fn Fgb::properties(self : Fgb, at : Int32, end : Int32) -> Unit {
  let mut at = at
  while at < end && self.error is None {
    let i = self.u16(at)
    if i >= self.names.length() {
      self.fail(at, "a property of no column")
      return
    }
    at += 2
    let (value, size) = match self.types[i] {
      0 => {
        let v = self.u8(at)
        (@geom.Num((if v >= 128 { v - 256 } else { v }).to_double()), 1)
      }
      1 => (@geom.Num(self.u8(at).to_double()), 1)
      2 => (@geom.Bool(self.u8(at) != 0), 1)
      3 => {
        let v = self.u16(at)
        (@geom.Num((if v >= 0x8000 { v - 0x10000 } else { v }).to_double()), 2)
      }
      4 => (@geom.Num(self.u16(at).to_double()), 2)
      5 => (@geom.Num(self.u32(at).to_double()), 4)
      6 => (@geom.Num(self.u32(at).reinterpret_as_uint().to_double()), 4)
      7 => (@geom.Num(self.u64(at).reinterpret_as_int64().to_double()), 8)
      8 => (@geom.Num(self.u64(at).to_double()), 8)
      9 =>
        (
          @geom.Num(
            Float::reinterpret_from_uint(self.u32(at).reinterpret_as_uint()).to_double(),
          ),
          4,
        )
      10 => (@geom.Num(self.f64(at)), 8)
      11 | 12 | 13 | 14 => {
        let n = self.u32(at)
        if n < 0 || n > self.b.length() - at - 4 {
          self.fail(at, "a value past the end of the data")
          return
        }
        let v = if self.types[i] == 14 {
          base64(self.b[at + 4:at + 4 + n])
        } else {
          self.text(at + 4, n)
        }
        (@geom.Str(v), 4 + n)
      }
      t => {
        self.fail(at, "unknown column type \{t}")
        return
      }
    }
    if !self.has(at, size) || at + size > end {
      self.fail(at, "a value past the end of the data")
      return
    }
    self.props.push((self.names[i], value))
    at += size
  }
}

///|
/// `b` in base64 with padding (RFC 4648 §4).
fn base64(b : BytesView) -> String {
  let digits = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  let sb = StringBuilder()
  let mut i = 0
  while i < b.length() {
    let n = @cmp.minimum(3, b.length() - i)
    let mut v = 0
    for k in 0..<3 {
      v = (v << 8) | (if k < n { b[i + k].to_int() } else { 0 })
    }
    for k in 0..<4 {
      sb.write_char(
        if k <= n {
          digits[(v >> (18 - k * 6)) & 63].to_int().unsafe_to_char()
        } else {
          '='
        },
      )
    }
    i += 3
  }
  sb.to_string()
}
