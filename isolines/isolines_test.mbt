///|
/// A table of Point rows from x, y, z triples, z as `elevation` (NaN: no
/// property).
fn grid(xyz : Array[Double]) -> @geom.Table {
  let b = @geom.TableBuilder::new()
  for i = 0; i < xyz.length(); i = i + 3 {
    b.point(xyz[i], xyz[i + 1])
    b.end_ring()
    b.end_part()
    if !xyz[i + 2].is_nan() {
      b.prop("elevation", Num(xyz[i + 2]))
    }
    b.end_feature(Point)
  }
  b.finish()
}

///|
/// Rows as `kind|property|parts`, parts by `;`, rings by `/`, points `x,y` by
/// spaces, numbers as JavaScript prints them (the generator's format).
fn digest(t : @geom.Table, z : String) -> String {
  let rows = []
  guard t.column(z) is Some(column) else { return "" }
  for f in 0..<t.length() {
    let kind = match t.kinds[f] {
      MultiLineString => "MultiLineString"
      MultiPolygon => "MultiPolygon"
      _ => "none"
    }
    let prop = match column.values[f] {
      Some(Num(v)) => v.to_string()
      Some(Str(s)) => s
      _ => "?"
    }
    let parts = []
    let (p0, p1) = t.parts(f)
    for p in p0..<p1 {
      let rings = []
      let (r0, r1) = t.rings(p)
      for r in r0..<r1 {
        let points = []
        let (i0, i1) = t.points(r)
        for i in i0..<i1 {
          points.push(
            t.coords[i * 2].to_string() + "," + t.coords[i * 2 + 1].to_string(),
          )
        }
        rings.push(points.join(" "))
      }
      parts.push(rings.join("/"))
    }
    rows.push(kind + "|" + prop + "|" + parts.join(";"))
  }
  rows.join("\n")
}

///|
fn fnv(s : String) -> UInt32 {
  let mut h = 0x811c9dc5U
  for i in 0..<s.length() {
    h = (h ^ s.code_unit_at(i).to_uint()) * 0x01000193U
  }
  h
}

///|
/// Asserts the digest's length and FNV-1a hash.
fn check(got : @geom.Table?, length : Int32, hash : UInt32) -> Unit raise {
  let d = digest(got.unwrap(), "elevation")
  assert_eq(d.length(), length)
  assert_eq(fnv(d), hash)
}

///|
/// A `cols` x `rows` grid at integer coordinates with `z` row by row.
fn square(cols : Int32, rows : Int32, z : Array[Double]) -> @geom.Table {
  let xyz = []
  for i in 0..<(cols * rows) {
    xyz.push((i % cols).to_double())
    xyz.push((i / cols).to_double())
    xyz.push(z[i])
  }
  grid(xyz)
}

///|
test "isolines and isobands refuse what Turf throws on" {
  // One row, one column, rows of unequal length, no rows.
  let one_row = square(3, 1, [1.0, 2.0, 3.0])
  let one_col = square(1, 3, [1.0, 2.0, 3.0])
  let uneven = grid([
    0.0, 0.0, 1.0, 1.0, 0.0, 2.0, 0.0, 1.0, 3.0, 1.0, 1.0, 4.0, 2.0, 1.0, 5.0,
  ])
  for t in [one_row, one_col, uneven, @geom.Table::new()] {
    assert_true(@isolines.isolines(t, [1.5], "elevation") is None)
    assert_true(@isolines.isobands(t, [1.0, 2.0], "elevation") is None)
  }
  // A row that is not a Point.
  let b = @geom.TableBuilder::new()
  for i in 0..<4 {
    b.point((i % 2).to_double(), (i / 2).to_double())
    b.end_ring()
    b.end_part()
    b.end_feature(Point)
  }
  b.point(0.0, 0.0)
  b.point(1.0, 1.0)
  b.end_ring()
  b.end_part()
  b.end_feature(LineString)
  assert_true(@isolines.isolines(b.finish(), [0.5], "elevation") is None)
}

///|
test "grid values Turf reads as 0 and values it keeps as non-numbers" {
  fn with_values(values : Array[@geom.Prop?]) -> @geom.Table {
    let b = @geom.TableBuilder::new()
    for i, v in values {
      b.point((i % 2).to_double(), (i / 2).to_double())
      b.end_ring()
      b.end_part()
      if v is Some(p) {
        b.prop("z", p)
      }
      b.end_feature(Point)
    }
    b.finish()
  }

  let zeros = with_values([
    Some(Num(0.0)),
    Some(Num(0.0)),
    Some(Num(0.0)),
    Some(Num(4.0)),
  ])
  let falsy = with_values([
    Some(Null),
    Some(Bool(false)),
    Some(Str("")),
    Some(Num(4.0)),
  ])
  let missing = with_values([
    None,
    Some(Num(@double.not_a_number)),
    None,
    Some(Num(4.0)),
  ])
  let expected = @isolines.isolines(zeros, [1.0], "z").unwrap()
  assert_eq(digest(expected, "z"), "MultiLineString|1|0.25,1 1,0.25")
  assert_eq(
    digest(@isolines.isolines(falsy, [1.0], "z").unwrap(), "z"),
    digest(expected, "z"),
  )
  assert_eq(
    digest(@isolines.isolines(missing, [1.0], "z").unwrap(), "z"),
    digest(expected, "z"),
  )
  let truthy = with_values([
    Some(Bool(true)),
    Some(Num(1.0)),
    Some(Num(1.0)),
    Some(Num(4.0)),
  ])
  let text = with_values([
    Some(Str("3")),
    Some(Num(1.0)),
    Some(Num(1.0)),
    Some(Num(4.0)),
  ])
  let huge = with_values([
    Some(Num(1.0e301)),
    Some(Num(1.0)),
    Some(Num(1.0)),
    Some(Num(4.0)),
  ])
  let infinite = with_values([
    Some(Num(@double.infinity)),
    Some(Num(1.0)),
    Some(Num(1.0)),
    Some(Num(4.0)),
  ])
  for t in [truthy, text, huge, infinite] {
    assert_true(@isolines.isolines(t, [1.0], "z") is None)
    assert_true(@isolines.isobands(t, [1.0, 2.0], "z") is None)
  }
}

///|
test "isolines and isobands caps" {
  let t = square(2, 2, [0.0, 1.0, 2.0, 3.0])
  assert_true(@isolines.isolines(t, [1.0e301], "elevation") is None)
  assert_true(@isolines.isobands(t, [0.0, -1.0e301], "elevation") is None)
  let many = Array::makei(@isolines.MAX_BREAKS + 1, i => i.to_double())
  assert_true(@isolines.isolines(t, many, "elevation") is None)
  assert_true(@isolines.isobands(t, many, "elevation") is None)
  let fine = Array::makei(@isolines.MAX_BREAKS, i => i.to_double() / 1000.0)
  assert_eq(@isolines.isolines(t, fine, "elevation").unwrap().length(), 4096)
  // A NaN coordinate.
  let nan = grid([
    0.0, 0.0, 1.0, 1.0, 0.0, 2.0, @double.not_a_number, 1.0, 3.0, 1.0, 1.0, 4.0,
  ])
  assert_true(@isolines.isolines(nan, [1.5], "elevation") is None)
}

///|
test "isobands label numbers by number_text" {
  let t = square(2, 2, [0.0, 1.0, 2.0, 3.0])
  let got = @isolines.isobands(
    t,
    [0.5, 1.5],
    "elevation",
    trig=@core.Trig::moonbit(),
    number_text=x => (x * 10.0).to_int().to_string(),
  ).unwrap()
  assert_eq(got.column("elevation").unwrap().values[0], Some(Str("5-15")))
}

///|
test "isolines and isobands refuse past MAX_GRID_POINTS and MAX_CELL_BREAKS" {
  let b = @geom.TableBuilder::new()
  for _ in 0..<=@isolines.MAX_GRID_POINTS {
    b.end_feature(NoGeometry)
  }
  let big = b.finish()
  assert_true(@isolines.isolines(big, [1.0], "elevation") is None)
  assert_true(@isolines.isobands(big, [0.0, 1.0], "elevation") is None)
  let cols = 16386
  let wide = square(cols, 2, Array::make(cols * 2, 0.0))
  let breaks = Array::makei(@isolines.MAX_BREAKS, i => i.to_double())
  assert_true(
    (cols - 1).to_int64() * breaks.length().to_int64() >
    @isolines.MAX_CELL_BREAKS,
  )
  assert_true(@isolines.isolines(wide, breaks, "elevation") is None)
  assert_true(@isolines.isobands(wide, breaks, "elevation") is None)
  assert_true(@isolines.isolines(wide, [0.5], "elevation") is Some(_))
}

///|
test "the segment and nesting caps isolines and isobands stop at" {
  assert_eq(@isolines.MAX_SEGMENTS, 4_000_000)
  assert_eq(@isolines.MAX_NESTING_TESTS, 100_000_000L)
}
