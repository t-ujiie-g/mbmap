///|
/// Property value tags of `Table::to_bytes` (the same as `@tiler.encode_tile`'s).
const TAG_NULL : Int32 = 0

///|
const TAG_FALSE : Int32 = 1

///|
const TAG_TRUE : Int32 = 2

///|
const TAG_NUMBER : Int32 = 3

///|
const TAG_STRING : Int32 = 4

///|
const TAG_ABSENT : Int32 = 5

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
/// The table (without feature ids) as bytes, little-endian:
///
/// - u32 counts: features F, parts P, rings R, points N, keys K;
/// - F kind bytes (0 none, 1 Point ... 6 MultiPolygon in `GeomKind` order),
///   padded to 4;
/// - u32 ends: F part ends, P ring ends, R point ends;
/// - 2N f64 coordinates;
/// - K keys (u32 byte length, UTF-8);
/// - per key, per feature: a tag (0 null, 1 false, 2 true, 3 number, 4
///   string, 5 absent), then an f64 or a u32 length and UTF-8.
///
/// A worker can hand a table to another this way, or JS build one.
pub fn Table::to_bytes(self : Table) -> Bytes {
  let out : Array[Byte] = []
  let u32 = (v : Int32) => {
    for i in 0..<4 {
      out.push((v >> (i * 8)).to_byte())
    }
  }
  let f64 = (v : Double) => {
    let bits = v.reinterpret_as_uint64()
    for i in 0..<8 {
      out.push((bits >> (i * 8)).to_byte())
    }
  }
  let utf8 = (s : String) => {
    let b = @utf8.encode(s)
    u32(b.length())
    for x in b {
      out.push(x)
    }
  }
  let f = self.length()
  u32(f)
  u32(self.ring_ends.length())
  u32(self.point_ends.length())
  u32(self.coords.length() / 2)
  u32(self.columns.length())
  for k in self.kinds {
    out.push(kind_code(k).to_byte())
  }
  while out.length() % 4 != 0 {
    out.push(b'\x00')
  }
  for e in self.part_ends {
    u32(e)
  }
  for e in self.ring_ends {
    u32(e)
  }
  for e in self.point_ends {
    u32(e)
  }
  for c in self.coords {
    f64(c)
  }
  for c in self.columns {
    utf8(c.name)
  }
  for c in self.columns {
    for i in 0..<f {
      match c.values[i] {
        None => out.push(TAG_ABSENT.to_byte())
        Some(Null) => out.push(TAG_NULL.to_byte())
        Some(Bool(false)) => out.push(TAG_FALSE.to_byte())
        Some(Bool(true)) => out.push(TAG_TRUE.to_byte())
        Some(Num(n)) => {
          out.push(TAG_NUMBER.to_byte())
          f64(n)
        }
        Some(Str(s)) => {
          out.push(TAG_STRING.to_byte())
          utf8(s)
        }
      }
    }
  }
  Bytes::from_array(out)
}

///|
/// Reads `Table::to_bytes`' form, checking every count, offset and length
/// against the input; None if it is malformed.
pub fn Table::from_bytes(b : BytesView) -> Table? {
  let n = b.length()
  let mut at = 0
  let mut bad = false
  let u32 = () => {
    if at + 4 > n {
      bad = true
      at = n
      return 0
    }
    let v = b[at].to_int() |
      (b[at + 1].to_int() << 8) |
      (b[at + 2].to_int() << 16) |
      (b[at + 3].to_int() << 24)
    at += 4
    v
  }
  let f64 = () => {
    if at + 8 > n {
      bad = true
      at = n
      return 0.0
    }
    let mut bits = 0UL
    for i in 0..<8 {
      bits = bits | (b[at + i].to_uint64() << (i * 8))
    }
    at += 8
    bits.reinterpret_as_double()
  }
  let utf8 = () => {
    let len = u32()
    if len < 0 || at + len > n {
      bad = true
      at = n
      return ""
    }
    let s = @utf8.decode_lossy(b[at:at + len])
    at += len
    s
  }
  let f = u32()
  let p = u32()
  let r = u32()
  let pts = u32()
  let k = u32()
  // Every feature takes at least a byte, every end four bytes, every point 16.
  if bad ||
    f < 0 ||
    p < 0 ||
    r < 0 ||
    pts < 0 ||
    k < 0 ||
    f > n ||
    p > n / 4 ||
    r > n / 4 ||
    pts > n / 16 ||
    k > n {
    return None
  }
  let t = Table::new()
  for i in 0..<f {
    guard kind_of_code(b[at + i].to_int()) is Some(kind) else { return None }
    t.kinds.push(kind)
    t.ids.push(None)
  }
  at += (f + 3) / 4 * 4
  // Ends must grow and stay within the next level's count.
  let ends = (count : Int32, limit : Int32, into : Array[Int32]) => {
    let mut last = 0
    for _ in 0..<count {
      let e = u32()
      if e < last || e > limit {
        bad = true
      }
      last = e
      into.push(e)
    }
  }
  ends(f, p, t.part_ends)
  ends(p, r, t.ring_ends)
  ends(r, pts, t.point_ends)
  if bad {
    return None
  }
  for _ in 0..<(pts * 2) {
    t.coords.push(f64())
  }
  let names = Array::makei(k, _ => utf8())
  for name in names {
    let values = []
    for _ in 0..<f {
      if at >= n {
        return None
      }
      let tag = b[at].to_int()
      at += 1
      values.push(
        match tag {
          0 => Some(Prop::Null)
          1 => Some(Bool(false))
          2 => Some(Bool(true))
          3 => Some(Num(f64()))
          4 => Some(Str(utf8()))
          5 => None
          _ => {
            bad = true
            None
          }
        },
      )
    }
    t.column_index[name] = t.columns.length()
    t.columns.push({ name, values, })
  }
  if bad || at != n {
    None
  } else {
    Some(t)
  }
}
