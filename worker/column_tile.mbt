///|
/// A GeoJSON source's tile in columns (docs/FORMATS.md, "Columnar tile");
/// `ids` are the features' GeoJSON ids (None without one).
priv struct ColumnTile {
  types : FixedArray[Int32]
  ring_ends : FixedArray[Int32]
  point_ends : FixedArray[Int32]
  xy : FixedArray[Int32]
  keys : Array[String]
  values : Array[Array[@style.Value?]]
  ids : Array[@style.Value?]
}

///|
/// Reads `b`, checking every count and length against it (AGENTS.md §8.2);
/// None if it is malformed.
fn ColumnTile::parse(b : BytesView) -> ColumnTile? {
  let r = @core.ByteReader::new(b)
  let n = b.length()
  let f = r.u32()
  let rings = r.u32()
  let p = r.u32()
  let k = r.u32()
  // A feature takes at least a byte, a ring four, a point four.
  if !r.ok() ||
    f < 0 ||
    rings < 0 ||
    p < 0 ||
    k < 0 ||
    f > n ||
    rings > n / 4 ||
    p > n / 4 ||
    k > n {
    return None
  }
  let types = FixedArray::makei(f, _ => r.u8())
  r.pad4()
  let ring_ends = ends(r, f, rings)
  let point_ends = ends(r, rings, p)
  let xy = FixedArray::makei(p * 2, _ => r.i16())
  r.pad4()
  let keys = Array::makei(k, _ => r.utf8())
  let values = []
  for _ in 0..<k {
    if !r.ok() {
      return None
    }
    values.push(Array::makei(f, _ => read_value(r)))
  }
  let ids = Array::makei(f, _ => read_value(r))
  guard r.done() else { return None }
  Some({ types, ring_ends, point_ends, xy, keys, values, ids, })
}

///|
/// `count` offsets that must grow and stay within `limit`.
fn ends(
  r : @core.ByteReader,
  count : Int32,
  limit : Int32,
) -> FixedArray[Int32] {
  let out = FixedArray::make(count, 0)
  let mut last = 0
  for i in 0..<count {
    let e = r.u32()
    if e < last || e > limit {
      r.fail()
      break
    }
    out[i] = e
    last = e
  }
  out
}

///|
fn read_value(r : @core.ByteReader) -> @style.Value? {
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
/// Feature `i`'s id: the property `promoted` names, or the tile's feature id;
/// Null without one. Booleans count as numbers, as in MapLibre.
fn Features::id(self : Features, i : Int32, promoted : String?) -> @style.Value {
  let v = match (self, promoted) {
    (Mvt(l), Some(p)) =>
      l.key_index(p).bind(k => l.property(i, k)).map(style_value)
    (Mvt(l), None) => l.id(i).map(id => @style.Value::Num(id.to_double()))
    (Columns(c), Some(p)) =>
      match c.keys.search(p) {
        Some(k) => c.values[k][i]
        None => None
      }
    (Columns(c), None) => c.ids[i]
  }
  match v {
    Some(Bool(b)) => Num(if b { 1.0 } else { 0.0 })
    Some(Num(_) as n) | Some(Str(_) as n) => n
    _ => Null
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
