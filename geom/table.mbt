///|
/// A property value. Objects and arrays are kept as their JSON text, as
/// geojson-vt and MVT encoders do, since style expressions cannot reach into them.
pub(all) enum Prop {
  Null
  Bool(Bool)
  Num(Double)
  Str(String)
} derive(Debug, Eq)

///|
/// What a feature's geometry is, as in GeoJSON.
pub(all) enum GeomKind {
  NoGeometry
  Point
  MultiPoint
  LineString
  MultiLineString
  Polygon
  MultiPolygon
} derive(Debug, Eq)

///|
/// A column of property values, one per feature: None where the feature
/// lacks the key (unlike `Some(Null)`, an explicit null).
pub struct Column {
  name : String
  values : Array[Prop?]
}

///|
/// Features in columns with GeoArrow's multipolygon offsets for every kind:
/// feature ends over parts, part ends over rings, ring ends over x, y pairs in
/// `coords`. A line is a part of one ring; a feature's points are one ring.
pub struct Table {
  kinds : Array[GeomKind]
  ids : Array[Prop?]
  part_ends : Array[Int32]
  ring_ends : Array[Int32]
  point_ends : Array[Int32]
  coords : Array[Double]
  columns : Array[Column]
  priv column_index : Map[String, Int32]
}

///|
pub fn Table::new() -> Table {
  {
    kinds: [],
    ids: [],
    part_ends: [],
    ring_ends: [],
    point_ends: [],
    coords: [],
    columns: [],
    column_index: Map([]),
  }
}

///|
pub fn Table::length(self : Table) -> Int32 {
  self.kinds.length()
}

///|
/// The column for `name`, if any feature has that key.
pub fn Table::column(self : Table, name : String) -> Column? {
  self.column_index.get(name).map(i => self.columns[i])
}

///|
fn start_of(ends : Array[Int32], i : Int32) -> Int32 {
  if i == 0 {
    0
  } else {
    ends[i - 1]
  }
}

///|
/// Parts of feature `f` as a range of part indices.
pub fn Table::parts(self : Table, f : Int32) -> (Int32, Int32) {
  (start_of(self.part_ends, f), self.part_ends[f])
}

///|
/// Rings of part `p` as a range of ring indices.
pub fn Table::rings(self : Table, p : Int32) -> (Int32, Int32) {
  (start_of(self.ring_ends, p), self.ring_ends[p])
}

///|
/// Points of ring `r` as a range of point indices.
pub fn Table::points(self : Table, r : Int32) -> (Int32, Int32) {
  (start_of(self.point_ends, r), self.point_ends[r])
}

///|
/// Appends features to a `Table`; empty rings and parts are dropped. Until
/// `finish`, columns may be shorter than the table.
pub struct TableBuilder {
  table : Table
  priv props : Array[(String, Prop)]
}

///|
pub fn TableBuilder::new() -> TableBuilder {
  { table: Table::new(), props: [], }
}

///|
pub fn TableBuilder::point(self : TableBuilder, x : Double, y : Double) -> Unit {
  self.table.coords.push(x)
  self.table.coords.push(y)
}

///|
pub fn TableBuilder::end_ring(self : TableBuilder) -> Unit {
  let t = self.table
  let n = t.coords.length() / 2
  if n > start_of_last(t.point_ends) {
    t.point_ends.push(n)
  }
}

///|
/// Closes a ring at point count `points`, for coordinates appended to
/// `table.coords` directly; nothing if no point was added since the last ring.
pub fn TableBuilder::end_ring_at(self : TableBuilder, points : Int32) -> Unit {
  if points > start_of_last(self.table.point_ends) {
    self.table.point_ends.push(points)
  }
}

///|
pub fn TableBuilder::end_part(self : TableBuilder) -> Unit {
  let t = self.table
  if t.point_ends.length() > start_of_last(t.ring_ends) {
    t.ring_ends.push(t.point_ends.length())
  }
}

///|
fn start_of_last(ends : Array[Int32]) -> Int32 {
  match ends.last() {
    Some(e) => e
    None => 0
  }
}

///|
/// Sets a property of the feature being built (the last value of a repeated
/// key wins, as in JSON).
pub fn TableBuilder::prop(
  self : TableBuilder,
  key : String,
  value : Prop,
) -> Unit {
  self.props.push((key, value))
}

///|
/// Closes the feature being built. A feature whose geometry came out empty
/// is kept with `NoGeometry`, so rows stay aligned with the input.
pub fn TableBuilder::end_feature(
  self : TableBuilder,
  kind : GeomKind,
  id~ : Prop? = None,
) -> Unit {
  let t = self.table
  let row = t.kinds.length()
  let parts = t.ring_ends.length()
  t.kinds.push(
    if parts > start_of_last(t.part_ends) {
      kind
    } else {
      NoGeometry
    },
  )
  t.part_ends.push(parts)
  t.ids.push(id)
  // Columns are padded with None only when they get a value (and by
  // `finish`), so a feature costs its own properties, not every column.
  for p in self.props {
    let i = match t.column_index.get(p.0) {
      Some(i) => i
      None => {
        t.columns.push({ name: p.0, values: [], })
        t.column_index[p.0] = t.columns.length() - 1
        t.columns.length() - 1
      }
    }
    let values = t.columns[i].values
    while values.length() < row {
      values.push(None)
    }
    if values.length() == row {
      values.push(Some(p.1))
    } else {
      values[row] = Some(p.1)
    }
  }
  self.props.clear()
}

///|
/// The table, with every column as long as the table.
pub fn TableBuilder::finish(self : TableBuilder) -> Table {
  let n = self.table.length()
  for c in self.table.columns {
    while c.values.length() < n {
      c.values.push(None)
    }
  }
  self.table
}

///|
/// Drops the geometry and properties of the feature being built, keeping
/// what earlier features added (for input that turns out to be invalid).
pub fn TableBuilder::discard_feature(self : TableBuilder) -> Unit {
  let t = self.table
  let parts = start_of_last(t.part_ends)
  t.ring_ends.truncate(parts)
  let rings = start_of_last(t.ring_ends)
  t.point_ends.truncate(rings)
  t.coords.truncate(start_of_last(t.point_ends) * 2)
  self.props.clear()
}

///|
/// The table with every x, y pair mapped by `f`, called once on each pair in
/// order; a feature with a pair `f` rejects keeps its row, id and properties
/// with no geometry.
pub fn Table::map_coords(
  self : Table,
  f : (Double, Double) -> (Double, Double)?,
) -> Table {
  let b = TableBuilder::new()
  let mapped = []
  for i in 0..<self.length() {
    let (p0, p1) = self.parts(i)
    let (r0, _) = if p0 < p1 { self.rings(p0) } else { (0, 0) }
    let (_, r1) = if p0 < p1 { self.rings(p1 - 1) } else { (0, 0) }
    let (c0, _) = if r0 < r1 { self.points(r0) } else { (0, 0) }
    let (_, c1) = if r0 < r1 { self.points(r1 - 1) } else { (0, 0) }
    mapped.clear()
    let mut ok = true
    for c in c0..<c1 {
      match f(self.coords[c * 2], self.coords[c * 2 + 1]) {
        Some((x, y)) => {
          mapped.push(x)
          mapped.push(y)
        }
        None => ok = false
      }
    }
    let kind = if ok {
      for p in p0..<p1 {
        let (r0, r1) = self.rings(p)
        for r in r0..<r1 {
          let (i0, i1) = self.points(r)
          for c in i0..<i1 {
            b.point(mapped[(c - c0) * 2], mapped[(c - c0) * 2 + 1])
          }
          b.end_ring()
        }
        b.end_part()
      }
      self.kinds[i]
    } else {
      NoGeometry
    }
    for c in self.columns {
      if c.values[i] is Some(v) {
        b.prop(c.name, v)
      }
    }
    b.end_feature(kind, id=self.ids[i])
  }
  b.finish()
}
