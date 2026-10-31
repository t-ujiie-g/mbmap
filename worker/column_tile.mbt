///|
/// A GeoJSON tile in columns, as `@tiler.encode_tile` writes it (tags
/// mirror its `VALUE_*`): types (1 points, 2 lines, 3 polygons), feature
/// ring ends, ring point ends, coordinates and one value column per key.
priv struct ColumnTile {
  types : FixedArray[Int32]
  ring_ends : FixedArray[Int32]
  point_ends : FixedArray[Int32]
  xy : FixedArray[Int32]
  keys : Array[String]
  values : Array[Array[@style.Value?]]
}

///|
/// Reads `b`, checking every count and length against it (AGENTS.md §8.2);
/// None if it is malformed.
fn ColumnTile::parse(b : BytesView) -> ColumnTile? {
  let mut at = 0
  let n = b.length()
  let u32 = () => {
    if at + 4 > n {
      at = n + 1
      return 0
    }
    let v = b[at].to_int() |
      (b[at + 1].to_int() << 8) |
      (b[at + 2].to_int() << 16) |
      (b[at + 3].to_int() << 24)
    at += 4
    v
  }
  let f = u32()
  let r = u32()
  let p = u32()
  let k = u32()
  // Each feature, ring and point takes at least a byte, four and four.
  if f < 0 ||
    r < 0 ||
    p < 0 ||
    k < 0 ||
    f > n ||
    r > n / 4 ||
    p > n / 4 ||
    k > n {
    return None
  }
  let types = FixedArray::makei(f, i => b[at + i].to_int())
  at += (f + 3) / 4 * 4
  let ring_ends = FixedArray::makei(f, _ => u32())
  let point_ends = FixedArray::makei(r, _ => u32())
  if at + p * 4 > n {
    return None
  }
  let xy = FixedArray::makei(p * 2, i => {
    let v = b[at + i * 2].to_int() | (b[at + i * 2 + 1].to_int() << 8)
    if v >= 0x8000 {
      v - 0x10000
    } else {
      v
    }
  })
  at += (p * 4 + 3) / 4 * 4
  // Offsets must grow and stay within the counts.
  let mut last = 0
  for e in ring_ends {
    if e < last || e > r {
      return None
    }
    last = e
  }
  last = 0
  for e in point_ends {
    if e < last || e > p {
      return None
    }
    last = e
  }
  let text = () => {
    let len = u32()
    if len < 0 || at + len > n {
      at = n + 1
      return ""
    }
    let s = @utf8.decode_lossy(b[at:at + len])
    at += len
    s
  }
  let keys = Array::makei(k, _ => text())
  let values = []
  for _ in 0..<k {
    let column = []
    for _ in 0..<f {
      if at >= n {
        return None
      }
      let tag = b[at].to_int()
      at += 1
      column.push(
        match tag {
          0 => Some(@style.Value::Null)
          1 => Some(Bool(false))
          2 => Some(Bool(true))
          3 => {
            if at + 8 > n {
              return None
            }
            let mut bits = 0UL
            for i in 0..<8 {
              bits = bits | (b[at + i].to_uint64() << (i * 8))
            }
            at += 8
            Some(Num(bits.reinterpret_as_double()))
          }
          4 => Some(Str(text()))
          _ => None
        },
      )
    }
    values.push(column)
  }
  if at > n {
    return None
  }
  Some({ types, ring_ends, point_ends, xy, keys, values, })
}

///|
/// The features a style layer draws from: a layer of a vector tile, or a
/// GeoJSON source's tile (which has a single layer).
priv enum Features {
  Mvt(@mvt.Layer)
  Columns(ColumnTile)
}

///|
fn Features::length(self : Features) -> Int32 {
  match self {
    Mvt(l) => l.length()
    Columns(c) => c.types.length()
  }
}

///|
fn Features::geom_type(self : Features, i : Int32) -> @mvt.GeomType {
  match self {
    Mvt(l) => l.geom_type(i)
    Columns(c) =>
      match c.types[i] {
        1 => Point
        2 => LineString
        3 => Polygon
        _ => Unknown
      }
  }
}

///|
/// Tile units per edge.
fn Features::extent(self : Features) -> Int32 {
  match self {
    Mvt(l) => l.extent
    Columns(_) => @core.TILE_EXTENT
  }
}

///|
/// Loads feature `i`'s geometry into `out`; the reason if it fails.
fn Features::load(self : Features, i : Int32, out : @mvt.Geometry) -> String? {
  match self {
    Mvt(l) => {
      if l.decode_geometry(i, out) {
        return None
      }
      let why = match out.error() {
        Some(e) => e.message()
        None => "unknown"
      }
      Some("malformed geometry in \{l.name}[\{i}]: \{why}")
    }
    Columns(c) => {
      out.coords.clear()
      out.ring_ends.clear()
      let r0 = if i == 0 { 0 } else { c.ring_ends[i - 1] }
      if c.ring_ends[i] == r0 {
        return None
      }
      let p0 = if r0 == 0 { 0 } else { c.point_ends[r0 - 1] }
      for v in c.xy[p0 * 2:c.point_ends[c.ring_ends[i] - 1] * 2] {
        out.coords.push(v)
      }
      for r in r0..<c.ring_ends[i] {
        out.ring_ends.push(c.point_ends[r] - p0)
      }
      None
    }
  }
}
