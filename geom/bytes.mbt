///|
fn kind_code(k : GeomKind) -> Int32 {
  match k {
    NoGeometry => 0
    Point => 1
    MultiPoint => 2
    LineString => 3
    MultiLineString => 4
    Polygon => 5
    MultiPolygon => 6
  }
}

///|
fn kind_of_code(c : Int32) -> GeomKind? {
  match c {
    0 => Some(NoGeometry)
    1 => Some(Point)
    2 => Some(MultiPoint)
    3 => Some(LineString)
    4 => Some(MultiLineString)
    5 => Some(Polygon)
    6 => Some(MultiPolygon)
    _ => None
  }
}

///|
/// The tag a property value is written with (docs/FORMATS.md, "Property values").
fn prop_tag(v : Prop?) -> Int32 {
  match v {
    None => @core.PROP_ABSENT
    Some(Null) => @core.PROP_NULL
    Some(Bool(false)) => @core.PROP_FALSE
    Some(Bool(true)) => @core.PROP_TRUE
    Some(Num(_)) => @core.PROP_NUMBER
    Some(Str(_)) => @core.PROP_STRING
  }
}

///|
/// Writes a property value (docs/FORMATS.md, "Property values").
pub fn write_prop(w : @core.ByteWriter, v : Prop?) -> Unit {
  w.u8(prop_tag(v))
  match v {
    Some(Num(n)) => w.f64(n)
    Some(Str(s)) => w.utf8(s)
    _ => ()
  }
}

///|
/// Reads a property value; an unknown tag fails the reader.
pub fn read_prop(r : @core.ByteReader) -> Prop? {
  let tag = r.u8()
  if tag == @core.PROP_NULL {
    Some(Null)
  } else if tag == @core.PROP_FALSE {
    Some(Bool(false))
  } else if tag == @core.PROP_TRUE {
    Some(Bool(true))
  } else if tag == @core.PROP_NUMBER {
    Some(Num(r.f64()))
  } else if tag == @core.PROP_STRING {
    Some(Str(r.utf8()))
  } else {
    if tag != @core.PROP_ABSENT {
      r.fail()
    }
    None
  }
}

///|
/// Random access to table bytes (docs/FORMATS.md, "Table"), little-endian: a
/// `BytesView`, or linear memory in the wasm-gc entries. `Table::read_from`
/// checks every offset against the length before it reads.
pub(open) trait TableSource {
  fn u8_at(Self, Int32) -> Int32
  fn u32_at(Self, Int32) -> Int32
  fn f64_at(Self, Int32) -> Double
  fn utf8_at(Self, Int32, Int32) -> String
}

///|
/// Where `Table::write_to` puts table bytes: `room(n)` makes the first `n`
/// bytes writable, or is false if they cannot be.
pub(open) trait TableSink {
  fn room(Self, Int32) -> Bool
  fn set_u8(Self, Int32, Int32) -> Unit
  fn set_u32(Self, Int32, Int32) -> Unit
  fn set_f64(Self, Int32, Double) -> Unit
  fn set_bytes(Self, Int32, BytesView) -> Unit
}

///|
pub impl TableSource for BytesView with fn u8_at(self, at) {
  self[at].to_int()
}

///|
pub impl TableSource for BytesView with fn u32_at(self, at) {
  self[at].to_int() |
  (self[at + 1].to_int() << 8) |
  (self[at + 2].to_int() << 16) |
  (self[at + 3].to_int() << 24)
}

///|
pub impl TableSource for BytesView with fn f64_at(self, at) {
  let lo = TableSource::u32_at(self, at).reinterpret_as_uint().to_uint64()
  let hi = TableSource::u32_at(self, at + 4).reinterpret_as_uint().to_uint64()
  (lo | (hi << 32)).reinterpret_as_double()
}

///|
pub impl TableSource for BytesView with fn utf8_at(self, at, n) {
  @core.utf8_lossy(self[at:at + n])
}

///|
/// The growing buffer `Table::to_bytes` writes into.
priv struct Growing {
  mut buf : FixedArray[Byte]
}

///|
impl TableSink for Growing with fn room(self, n) {
  if n > self.buf.length() {
    let twice = if self.buf.length() < 0x3FFF0000 {
      2 * self.buf.length()
    } else {
      n
    }
    let buf = FixedArray::make(if n > twice { n } else { twice }, b'\x00')
    self.buf.blit_to(buf, len=self.buf.length())
    self.buf = buf
  }
  true
}

///|
impl TableSink for Growing with fn set_u8(self, at, v) {
  self.buf[at] = v.to_byte()
}

///|
impl TableSink for Growing with fn set_u32(self, at, v) {
  let b = self.buf
  b[at] = v.to_byte()
  b[at + 1] = (v >> 8).to_byte()
  b[at + 2] = (v >> 16).to_byte()
  b[at + 3] = (v >> 24).to_byte()
}

///|
impl TableSink for Growing with fn set_f64(self, at, v) {
  let bits = v.reinterpret_as_uint64()
  TableSink::set_u32(self, at, bits.to_int())
  TableSink::set_u32(self, at + 4, (bits >> 32).to_int())
}

///|
impl TableSink for Growing with fn set_bytes(self, at, b) {
  for i, x in b {
    self.buf[at + i] = x
  }
}

///|
/// Writes the table's bytes to `out` from offset 0; returns how many, or -1 if
/// `out` has no room for them.
pub fn[S : TableSink] Table::write_to(self : Table, out : S) -> Int32 {
  let f = self.length()
  let ends = self.part_ends.length() +
    self.ring_ends.length() +
    self.point_ends.length()
  let fixed = 20L +
    ((f + 3) / 4 * 4).to_int64() +
    4L * ends.to_int64() +
    8L * self.coords.length().to_int64()
  guard fixed < 0x7FFF0000L && out.room(fixed.to_int()) else { return -1 }
  out.set_u32(0, f)
  out.set_u32(4, self.ring_ends.length())
  out.set_u32(8, self.point_ends.length())
  out.set_u32(12, self.coords.length() / 2)
  out.set_u32(16, self.columns.length())
  for i, k in self.kinds {
    out.set_u8(20 + i, kind_code(k))
  }
  let mut at = 20 + f
  while at % 4 != 0 {
    out.set_u8(at, 0)
    at += 1
  }
  for ends in [self.part_ends, self.ring_ends, self.point_ends] {
    for e in ends {
      out.set_u32(at, e)
      at += 4
    }
  }
  for c in self.coords {
    out.set_f64(at, c)
    at += 8
  }
  for c in self.columns {
    at = write_text(out, at, c.name)
  }
  for c in self.columns {
    for i in 0..<f {
      let v = c.values[i]
      guard at >= 0 && fits(out, at, 9) else { return -1 }
      out.set_u8(at, prop_tag(v))
      at += 1
      match v {
        Some(Num(x)) => {
          out.set_f64(at, x)
          at += 8
        }
        Some(Str(s)) => at = write_text(out, at, s)
        _ => ()
      }
    }
  }
  at
}

///|
/// Whether `out` has room for `n` more bytes at `at`, the total kept below
/// 2^31 - 2^16 so that sums cannot overflow.
fn[S : TableSink] fits(out : S, at : Int32, n : Int32) -> Bool {
  n >= 0 && n < 0x7FFF0000 - at && out.room(at + n)
}

///|
/// Writes `s` with its u32 byte length at `at` (-1 for none) and returns where
/// it ends, or -1 without room.
fn[S : TableSink] write_text(out : S, at : Int32, s : String) -> Int32 {
  let b = @utf8.encode(s)
  guard at >= 0 && fits(out, at, 4 + b.length()) else { return -1 }
  out.set_u32(at, b.length())
  out.set_bytes(at + 4, b[:])
  at + 4 + b.length()
}

///|
/// The table, without feature ids, as bytes (docs/FORMATS.md, "Table").
pub fn Table::to_bytes(self : Table) -> Bytes {
  let out = Growing::{ buf: FixedArray::make(256, b'\x00'), }
  let n = self.write_to(out)
  Bytes::from_array(out.buf[:n])
}

///|
/// Reads `Table::to_bytes`' form, checking every count, offset and length
/// against the input; None if it is malformed.
pub fn Table::from_bytes(b : BytesView) -> Table? {
  Table::read_from(b, b.length())
}

///|
/// A sticky reader of the first `n` bytes of a `TableSource`: a read past the
/// end gives 0 and fails it.
priv struct Cursor[S] {
  src : S
  n : Int32
  mut at : Int32
  mut failed : Bool
}

///|
fn[S] Cursor::fail(self : Cursor[S]) -> Unit {
  self.failed = true
  self.at = self.n
}

///|
/// Whether `k` more bytes are there; fails the cursor if not.
fn[S] Cursor::has(self : Cursor[S], k : Int32) -> Bool {
  if k < 0 || k > self.n - self.at {
    self.fail()
    return false
  }
  true
}

///|
fn[S : TableSource] Cursor::u8(self : Cursor[S]) -> Int32 {
  if !self.has(1) {
    return 0
  }
  self.at += 1
  self.src.u8_at(self.at - 1)
}

///|
fn[S : TableSource] Cursor::u32(self : Cursor[S]) -> Int32 {
  if !self.has(4) {
    return 0
  }
  self.at += 4
  self.src.u32_at(self.at - 4)
}

///|
fn[S : TableSource] Cursor::f64(self : Cursor[S]) -> Double {
  if !self.has(8) {
    return 0.0
  }
  self.at += 8
  self.src.f64_at(self.at - 8)
}

///|
fn[S : TableSource] Cursor::utf8(self : Cursor[S]) -> String {
  let k = self.u32()
  if !self.has(k) {
    return ""
  }
  self.at += k
  self.src.utf8_at(self.at - k, k)
}

///|
/// `read_prop` through the cursor.
fn[S : TableSource] Cursor::prop(self : Cursor[S]) -> Prop? {
  let tag = self.u8()
  if tag == @core.PROP_NULL {
    Some(Null)
  } else if tag == @core.PROP_FALSE {
    Some(Bool(false))
  } else if tag == @core.PROP_TRUE {
    Some(Bool(true))
  } else if tag == @core.PROP_NUMBER {
    Some(Num(self.f64()))
  } else if tag == @core.PROP_STRING {
    Some(Str(self.utf8()))
  } else {
    if tag != @core.PROP_ABSENT {
      self.fail()
    }
    None
  }
}

///|
/// The `count` ends of one level, which must grow and stay within `limit`, the
/// next level's count; equal ends (an empty item) only where `empty`.
fn[S : TableSource] Cursor::ends(
  self : Cursor[S],
  count : Int32,
  limit : Int32,
  empty : Bool,
) -> Array[Int32] {
  let into = Array::make(count, 0)
  guard self.has(count * 4) else { return into }
  let mut last = 0
  for i in 0..<count {
    let e = self.src.u32_at(self.at + i * 4)
    if e < last || (e == last && !empty) || e > limit {
      self.fail()
      return into
    }
    last = e
    into[i] = e
  }
  self.at += count * 4
  into
}

///|
/// `Table::from_bytes` of the first `n` bytes of `src`.
pub fn[S : TableSource] Table::read_from(src : S, n : Int32) -> Table? {
  let r = { src, n, at: 0, failed: false, }
  let f = r.u32()
  let p = r.u32()
  let rings = r.u32()
  let pts = r.u32()
  let k = r.u32()
  // A feature takes at least five bytes (its kind and end), a part or ring an
  // end, a point sixteen, a key its length.
  if r.failed ||
    f < 0 ||
    p < 0 ||
    rings < 0 ||
    pts < 0 ||
    k < 0 ||
    f > n / 5 ||
    p > n / 4 ||
    rings > n / 4 ||
    pts > n / 16 ||
    k > n / 4 {
    return None
  }
  let kinds = Array::make(f, NoGeometry)
  for i in 0..<f {
    guard kind_of_code(r.u8()) is Some(kind) else { return None }
    kinds[i] = kind
  }
  guard r.has((4 - r.at % 4) % 4) else { return None }
  r.at = (r.at + 3) / 4 * 4
  // Parts and rings are never empty (`TableBuilder` drops empty ones, and
  // readers index their first).
  let part_ends = r.ends(f, p, true)
  let ring_ends = r.ends(p, rings, false)
  let point_ends = r.ends(rings, pts, false)
  if r.failed {
    return None
  }
  // Only `NoGeometry` has no parts, as `end_feature` makes it: readers index a
  // feature's first part by its kind.
  for i in 0..<f {
    if (kinds[i] is NoGeometry) != (part_ends[i] == start_of(part_ends, i)) {
      return None
    }
  }
  guard r.has(pts * 16) else { return None }
  let at = r.at
  let coords = Array::makei(pts * 2, i => src.f64_at(at + i * 8))
  r.at += pts * 16
  let t = {
    kinds,
    ids: Array::make(f, None),
    part_ends,
    ring_ends,
    point_ends,
    coords,
    columns: [],
    column_index: Map([]),
  }
  let names = Array::makei(k, _ => r.utf8())
  for name in names {
    let values = Array::make(f, None)
    for i in 0..<f {
      if r.failed {
        return None
      }
      values[i] = r.prop()
    }
    t.column_index[name] = t.columns.length()
    t.columns.push({ name, values, })
  }
  if !r.failed && r.at == n {
    Some(t)
  } else {
    None
  }
}
