///|
/// A table of points at `coords`, ids `ids` and property `n` its index.
fn point_table(
  coords : Array[(Double, Double)],
  ids : Array[@geom.Prop?],
) -> @geom.Table {
  let b = @geom.TableBuilder::new()
  for i, c in coords {
    b.point(c.0, c.1)
    b.end_ring()
    b.end_part()
    b.prop("n", Num(i.to_double()))
    b.end_feature(Point, id=ids[i])
  }
  b.finish()
}

///|
/// A diff adding the points of `added` (one feature each) and making `update`'s changes.
fn diff(
  remove_all~ : Bool = false,
  remove~ : Array[@geom.Prop?] = [],
  added~ : @geom.Table = @geom.Table::new(),
  update~ : Array[@tiler.FeatureDiff] = [],
) -> @tiler.Diff {
  {
    remove_all,
    remove,
    table: added,
    add: Array::makei(added.length(), i => i + 1),
    update,
  }
}

///|
fn change(
  id : @geom.Prop,
  geometry~ : (Int32, Int32)? = None,
  remove_all_properties~ : Bool = false,
  remove_properties~ : Array[String] = [],
  add_properties~ : Array[(String, @geom.Prop?)] = [],
) -> @tiler.FeatureDiff {
  {
    id: Some(id),
    geometry,
    remove_all_properties,
    remove_properties,
    add_properties,
  }
}

///|
/// The (id, n) of each feature of the top tile.
fn top(
  t : @tiler.Tiler,
  table : @geom.Table,
) -> Array[(@geom.Prop?, @geom.Prop?)] {
  match t.tile(0, 0, 0) {
    None => []
    Some(d) =>
      d.rows.map(r => (table.ids[r], table.column("n").bind(c => c.values[r])))
  }
}

///|
test "update adds, replaces and removes features by id, updated ones last" {
  let table = point_table([(0.0, 0.0), (10.0, 10.0)], [
    Some(Num(1.0)),
    Some(Str("b")),
  ])
  let t = @tiler.Tiler::new(table)
  assert_eq(top(t, table), [
    (Some(Num(1.0)), Some(Num(0.0))),
    (Some(Str("b")), Some(Num(1.0))),
  ])
  let added = point_table([(20.0, 0.0), (30.0, 0.0)], [
    Some(Num(1.0)),
    Some(Num(3.0)),
  ])
  assert_true(t.update(diff(added~)))
  assert_eq(top(t, table), [
    (Some(Str("b")), Some(Num(1.0))),
    (Some(Num(1.0)), Some(Num(0.0))),
    (Some(Num(3.0)), Some(Num(1.0))),
  ])
  assert_true(t.update(diff(remove=[Some(Num(1.0)), Some(Str("x"))])))
  assert_eq(top(t, table).map(f => f.0), [Some(Str("b")), Some(Num(3.0))])
  assert_false(t.update(diff(remove=[Some(Str("x"))])))
  assert_true(t.update(diff(remove_all=true)))
  assert_eq(top(t, table), [])
  assert_false(t.update(diff(remove_all=true)))
}

///|
test "features without an id are kept under null, which no id in a diff names" {
  let table = point_table([(0.0, 0.0)], [None])
  let t = @tiler.Tiler::new(table)
  let added = point_table([(10.0, 0.0)], [None])
  assert_true(t.update(diff(added~, remove=[None])))
  assert_eq(top(t, table).length(), 2)
  assert_false(
    t.update(
      diff(update=[
        { ..change(Num(0.0), remove_all_properties=true), id: None, },
      ]),
    ),
  )
}

///|
test "update changes properties in a copy and moves the feature to the end" {
  let table = point_table([(0.0, 0.0), (10.0, 10.0)], [
    Some(Num(1.0)),
    Some(Num(2.0)),
  ])
  let t = @tiler.Tiler::new(table)
  let u = change(Num(1.0), remove_properties=["n"], add_properties=[
    ("k", Some(Str("v"))),
    ("k", Some(Bool(true))),
    ("j", Some(Null)),
    ("j", None),
  ])
  assert_true(t.update(diff(update=[u])))
  let d = t.tile(0, 0, 0).unwrap()
  let row = d.rows[1]
  assert_eq(table.ids[row], Some(Num(1.0)))
  assert_eq(table.column("n").unwrap().values[row], None)
  assert_eq(table.column("k").unwrap().values[row], Some(Bool(true)))
  assert_eq(table.column("j").bind(c => c.values[row]), None)
  assert_eq(d.xy[2:4].to_owned(), [@core.TILE_EXTENT / 2, @core.TILE_EXTENT / 2])
  // Removing all properties ignores the rest, as geojson-vt does.
  let all = change(Num(2.0), remove_all_properties=true, add_properties=[
    ("k", Some(Num(1.0))),
  ])
  assert_true(t.update(diff(update=[all])))
  let row = t.tile(0, 0, 0).unwrap().rows[1]
  assert_eq(table.column("k").unwrap().values[row], None)
  assert_eq(table.column("n").unwrap().values[row], None)
  // An update without changes still affects its feature, one of a missing id nothing.
  assert_true(t.update(diff(update=[change(Num(2.0))])))
  assert_false(
    t.update(diff(update=[change(Num(9.0), remove_all_properties=true)])),
  )
}

///|
test "update moves a feature to a new geometry and keeps those without coordinates" {
  let b = @geom.TableBuilder::new()
  b.point(0.0, 0.0)
  b.end_ring()
  b.end_part()
  b.end_feature(Point, id=Some(Num(1.0)))
  b.prop("n", Num(5.0))
  b.end_feature(NoGeometry, id=Some(Num(2.0)))
  let table = b.finish()
  let t = @tiler.Tiler::new(table)
  assert_eq(top(t, table).length(), 1)
  // The geometry of the diff's first row: a point at 90° east.
  let g = point_table([(90.0, 0.0)], [None])
  let to_east = (id : Double) => {
    ..diff(update=[change(Num(id), geometry=Some((0, 1)))]),
    table: g,
    add: [],
  }
  // Feature 2 had no coordinates: it gets some, with its properties.
  assert_true(t.update(to_east(2.0)))
  assert_eq(top(t, table), [
    (Some(Num(1.0)), None),
    (Some(Num(2.0)), Some(Num(5.0))),
  ])
  assert_eq(t.tile(0, 0, 0).unwrap().xy[2], @core.TILE_EXTENT * 3 / 4)
  // A new geometry without coordinates takes feature 1 out, and a later one brings it back.
  let empty = {
    ..diff(update=[change(Num(1.0), geometry=Some((0, 1)))]),
    table: table_of_nothing(),
    add: [],
  }
  assert_true(t.update(empty))
  assert_eq(top(t, table).map(f => f.0), [Some(Num(2.0))])
  assert_true(t.update(to_east(1.0)))
  assert_eq(top(t, table).map(f => f.0), [Some(Num(2.0)), Some(Num(1.0))])
  // Unknown ids stay unknown.
  assert_false(t.update(to_east(7.0)))
}

///|
fn table_of_nothing() -> @geom.Table {
  let b = @geom.TableBuilder::new()
  b.end_feature(Point)
  b.finish()
}

///|
test "promote_id finds features by a property, kept when the property changes" {
  let table = point_table([(0.0, 0.0), (10.0, 0.0)], [None, None])
  let t = @tiler.Tiler::new(table, promote_id="n")
  assert_eq(table.ids, [Some(Num(0.0)), Some(Num(1.0))])
  let u = change(Num(0.0), add_properties=[("n", Some(Num(7.0)))])
  assert_true(t.update(diff(update=[u])))
  assert_eq(top(t, table), [
    (Some(Num(1.0)), Some(Num(1.0))),
    (Some(Num(0.0)), Some(Num(7.0))),
  ])
  assert_true(t.update(diff(remove=[Some(Num(0.0))])))
  assert_eq(top(t, table).length(), 1)
}

///|
test "updates drop the tiles they reach and leave the rest" {
  let table = point_table([(-170.0, 80.0), (170.0, -80.0)], [
    Some(Num(1.0)),
    Some(Num(2.0)),
  ])
  let t = @tiler.Tiler::new(table, options={
    ..@tiler.TilerOptions::default(),
    index_max_points: 0,
  })
  let far = t.tile(5, 31, 28).unwrap()
  let u = change(Num(1.0), add_properties=[("k", Some(Num(1.0)))])
  assert_true(t.update(diff(update=[u])))
  // The tile around feature 2 is the one cut before; feature 1's is cut again.
  assert_true(physical_equal(t.tile(5, 31, 28).unwrap(), far))
  let near = t.tile(5, 0, 3).unwrap()
  assert_eq(table.column("k").unwrap().values[near.rows[0]], Some(Num(1.0)))
}

///|
test "many updates compact the table and keep every tile" {
  let n = 50
  let coords = Array::makei(n, i => (i.to_double() * 3.0 - 70.0, 10.0))
  let table = point_table(
    coords,
    Array::makei(n, i => Some(Num(i.to_double()))),
  )
  let t = @tiler.Tiler::new(table)
  for step in 0..<200 {
    let updates = Array::makei(n, i => {
      change(Num(i.to_double()), add_properties=[
        ("s", Some(Num(step.to_double()))),
      ])
    })
    assert_true(t.update(diff(update=updates)))
    t.tile(4, 5, 7) |> ignore
  }
  assert_true(table.length() < 4 * n + 2048)
  let d = t.tile(0, 0, 0).unwrap()
  assert_eq(d.rows.length(), n)
  assert_true(
    d.rows
    .iter()
    .all(r => table.column("s").unwrap().values[r] == Some(Num(199.0))),
  )
  assert_eq(
    d.rows.map(r => table.ids[r]),
    Array::makei(n, i => Some(Num(i.to_double()))),
  )
}

///|
test "ClusterIndex::update clusters the points again" {
  let table = point_table([(0.0, 0.0), (0.001, 0.0)], [
    Some(Num(1.0)),
    Some(Num(2.0)),
  ])
  let c = @tiler.ClusterIndex::new(table)
  assert_eq(c.tile(0, 0, 0).unwrap().map(f => f.count), [2])
  let added = point_table([(0.0, 0.001)], [Some(Num(3.0))])
  assert_true(c.update(diff(added~)))
  assert_eq(c.tile(0, 0, 0).unwrap().map(f => f.count), [3])
  assert_true(c.update(diff(remove=[Some(Num(1.0)), Some(Num(2.0))])))
  let fs = c.tile(0, 0, 0).unwrap()
  assert_eq(fs.map(f => (f.count, table.ids[f.row])), [(1, Some(Num(3.0)))])
  assert_false(c.update(diff(remove=[Some(Num(1.0))])))
}

///|
test "Diff::read reads docs/FORMATS.md's GeoJSON diff after its features" {
  let w = @core.ByteWriter::new()
  w.u8(1)
  w.u32(2)
  @geom.write_prop(w, Some(Num(1.0)))
  @geom.write_prop(w, None)
  w.u32(1)
  w.u32(2)
  @geom.write_prop(w, Some(Str("a")))
  w.u8(3)
  w.u32(1)
  w.utf8("x")
  w.u32(1)
  w.utf8("y")
  @geom.write_prop(w, None)
  @geom.write_prop(w, Some(Bool(true)))
  w.u8(0)
  w.u32(0)
  w.u32(0)
  let added = point_table([(0.0, 0.0), (1.0, 1.0), (2.0, 2.0)], [
    None,
    None,
    None,
  ])
  let bytes = w.to_bytes()
  let d = @tiler.Diff::read(bytes[:], added, [1, 3]).unwrap()
  assert_eq(
    (d.remove_all, d.remove, d.add),
    (true, [Some(Num(1.0)), None], [1]),
  )
  let u = d.update[0]
  assert_eq(
    (
      u.id,
      u.geometry,
      u.remove_all_properties,
      u.remove_properties,
      u.add_properties,
    ),
    (Some(Str("a")), Some((1, 3)), true, ["x"], [("y", None)]),
  )
  assert_eq((d.update[1].id, d.update[1].geometry), (Some(Bool(true)), None))
  // Features left over or missing, and bytes cut short or left over, are refused.
  assert_true(@tiler.Diff::read(bytes[:], added, [1, 2, 3]) is None)
  assert_true(@tiler.Diff::read(bytes[:], added, [1]) is None)
  assert_true(
    @tiler.Diff::read(bytes[:bytes.length() - 1], added, [1, 3]) is None,
  )
  let longer = [..bytes, b'\x00']
  assert_true(
    @tiler.Diff::read(Bytes::from_array(longer)[:], added, [1, 3]) is None,
  )
}
