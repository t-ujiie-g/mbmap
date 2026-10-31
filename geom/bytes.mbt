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
/// Writes a property value (docs/FORMATS.md, "Property values").
pub fn write_prop(w : @core.ByteWriter, v : Prop?) -> Unit {
  match v {
    None => w.u8(@core.PROP_ABSENT)
    Some(Null) => w.u8(@core.PROP_NULL)
    Some(Bool(false)) => w.u8(@core.PROP_FALSE)
    Some(Bool(true)) => w.u8(@core.PROP_TRUE)
    Some(Num(n)) => {
      w.u8(@core.PROP_NUMBER)
      w.f64(n)
    }
    Some(Str(s)) => {
      w.u8(@core.PROP_STRING)
      w.utf8(s)
    }
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
/// The table, without feature ids, as bytes (docs/FORMATS.md, "Table").
pub fn Table::to_bytes(self : Table) -> Bytes {
  let w = @core.ByteWriter::new()
  let f = self.length()
  w.u32(f)
  w.u32(self.ring_ends.length())
  w.u32(self.point_ends.length())
  w.u32(self.coords.length() / 2)
  w.u32(self.columns.length())
  for k in self.kinds {
    w.u8(kind_code(k))
  }
  w.pad4()
  for ends in [self.part_ends, self.ring_ends, self.point_ends] {
    for e in ends {
      w.u32(e)
    }
  }
  for c in self.coords {
    w.f64(c)
  }
  for c in self.columns {
    w.utf8(c.name)
  }
  for c in self.columns {
    for i in 0..<f {
      write_prop(w, c.values[i])
    }
  }
  w.to_bytes()
}

///|
/// Reads `Table::to_bytes`' form, checking every count, offset and length
/// against the input; None if it is malformed.
pub fn Table::from_bytes(b : BytesView) -> Table? {
  let r = @core.ByteReader::new(b)
  let n = b.length()
  let f = r.u32()
  let p = r.u32()
  let rings = r.u32()
  let pts = r.u32()
  let k = r.u32()
  // A feature takes at least a byte, an end four, a point sixteen.
  if !r.ok() ||
    f < 0 ||
    p < 0 ||
    rings < 0 ||
    pts < 0 ||
    k < 0 ||
    f > n ||
    p > n / 4 ||
    rings > n / 4 ||
    pts > n / 16 ||
    k > n {
    return None
  }
  let t = Table::new()
  for _ in 0..<f {
    guard kind_of_code(r.u8()) is Some(kind) else { return None }
    t.kinds.push(kind)
    t.ids.push(None)
  }
  r.pad4()
  // Ends must grow and stay within the next level's count.
  let ends = (count : Int32, limit : Int32, into : Array[Int32]) => {
    let mut last = 0
    for _ in 0..<count {
      let e = r.u32()
      if e < last || e > limit {
        r.fail()
      }
      last = e
      into.push(e)
    }
  }
  ends(f, p, t.part_ends)
  ends(p, rings, t.ring_ends)
  ends(rings, pts, t.point_ends)
  if !r.ok() {
    return None
  }
  for _ in 0..<(pts * 2) {
    t.coords.push(r.f64())
  }
  let names = Array::makei(k, _ => r.utf8())
  for name in names {
    let values = []
    for _ in 0..<f {
      if !r.ok() {
        return None
      }
      values.push(read_prop(r))
    }
    t.column_index[name] = t.columns.length()
    t.columns.push({ name, values, })
  }
  if r.done() {
    Some(t)
  } else {
    None
  }
}
