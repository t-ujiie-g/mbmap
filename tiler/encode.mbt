///|
/// Property value tags in an encoded tile (see `encode_tile`).
pub const VALUE_NULL : Int32 = 0

///|
pub const VALUE_FALSE : Int32 = 1

///|
pub const VALUE_TRUE : Int32 = 2

///|
pub const VALUE_NUMBER : Int32 = 3

///|
pub const VALUE_STRING : Int32 = 4

///|
/// The feature lacks the key.
pub const VALUE_ABSENT : Int32 = 5

///|
fn put_u32(out : Array[Byte], v : Int32) -> Unit {
  for i in 0..<4 {
    out.push((v >> (i * 8)).to_byte())
  }
}

///|
fn put_utf8(out : Array[Byte], s : String) -> Unit {
  let bytes = @utf8.encode(s)
  put_u32(out, bytes.length())
  for b in bytes {
    out.push(b)
  }
}

///|
fn pad4(out : Array[Byte]) -> Unit {
  while out.length() % 4 != 0 {
    out.push(b'\x00')
  }
}

///|
/// The tile as bytes for the display worker (worker/column_tile.mbt reads
/// them), little-endian:
///
/// - u32 counts: features F, rings R, points P, property keys K;
/// - F type bytes (1 points, 2 lines, 3 polygons), padded to 4;
/// - F u32 ring ends, R u32 point ends;
/// - P x, y pairs as i16 (clamped), padded to 4;
/// - K keys (u32 byte length, UTF-8);
/// - per key, per feature: a `VALUE_*` tag, then an f64 for numbers or a
///   u32 length and UTF-8 for strings.
///
/// Properties come from `table`'s rows; keys no feature of the tile has are
/// left out.
pub fn encode_tile(d : TileData, table : @geom.Table) -> Bytes {
  let out : Array[Byte] = []
  let f = d.types.length()
  // Keys of the tile's features, in column order.
  let columns = []
  for c in table.columns {
    for row in d.rows {
      if c.values[row] is Some(_) {
        columns.push(c)
        break
      }
    }
  }
  put_u32(out, f)
  put_u32(out, d.point_ends.length())
  put_u32(out, d.xy.length() / 2)
  put_u32(out, columns.length())
  for t in d.types {
    out.push(t.to_byte())
  }
  pad4(out)
  for e in d.ring_ends {
    put_u32(out, e)
  }
  for e in d.point_ends {
    put_u32(out, e)
  }
  for v in d.xy {
    let c = @cmp.maximum(-32768, @cmp.minimum(32767, v))
    out.push(c.to_byte())
    out.push((c >> 8).to_byte())
  }
  pad4(out)
  for c in columns {
    put_utf8(out, c.name)
  }
  for c in columns {
    for row in d.rows {
      match c.values[row] {
        None => out.push(VALUE_ABSENT.to_byte())
        Some(Null) => out.push(VALUE_NULL.to_byte())
        Some(Bool(false)) => out.push(VALUE_FALSE.to_byte())
        Some(Bool(true)) => out.push(VALUE_TRUE.to_byte())
        Some(Num(n)) => {
          out.push(VALUE_NUMBER.to_byte())
          let bits = n.reinterpret_as_uint64()
          for i in 0..<8 {
            out.push((bits >> (i * 8)).to_byte())
          }
        }
        Some(Str(s)) => {
          out.push(VALUE_STRING.to_byte())
          put_utf8(out, s)
        }
      }
    }
  }
  Bytes::from_array(out)
}
