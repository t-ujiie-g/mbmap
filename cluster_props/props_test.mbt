///|
fn points_table(text : String) -> @geom.Table {
  @formats.read_geojson(@utf8.encode(text)[:]) catch {
    e => abort(e.message())
  }
}

///|
fn compiled(text : String) -> Array[(String, @style.Expr, @style.Expr)] {
  let json = @json.parse(text) catch { _ => abort("not JSON") }
  @style.compile_cluster_properties(json) catch {
    e => abort(e.message())
  }
}

///|
test "cluster properties map points and reduce into the cluster's values" {
  let table = points_table(
    (
      #|{"type": "FeatureCollection", "features": [
      #|  {"type": "Feature", "properties": {"n": 2, "k": "a"}, "geometry": {"type": "Point", "coordinates": [0, 0]}},
      #|  {"type": "Feature", "properties": {"n": 5, "k": "b"}, "geometry": {"type": "Point", "coordinates": [0, 0]}},
      #|  {"type": "Feature", "properties": {"k": "c"}, "geometry": {"type": "Point", "coordinates": [0, 0]}}]}
    ),
  )
  let p = @cluster_props.cluster_properties(
    table,
    compiled(
      (
        #|{"sum": ["+", ["get", "n"]],
        #| "kinds": [["concat", ["accumulated"], ",", ["get", "kinds"]], ["get", "k"]],
        #| "half": ["max", ["/", ["get", "n"], 0]]}
      ),
    ),
  )
  assert_eq(p.keys, ["sum", "kinds", "half"])
  let a = (p.map)(0)
  assert_eq(a, [Num(2.0), Str("a"), Num(@double.infinity)])
  // A missing property maps to null; the sum then fails and is null too.
  assert_eq((p.map)(2), [Null, Str("c"), Null])
  (p.reduce)(a, (p.map)(1))
  assert_eq(a, [Num(7.0), Str("a,b"), Num(@double.infinity)])
  (p.reduce)(a, (p.map)(2))
  assert_eq(a, [Null, Str("a,b,c"), Null])
}

///|
test "clusters carry their reduced properties into tiles and children" {
  let table = points_table(
    (
      #|{"type": "FeatureCollection", "features": [
      #|  {"type": "Feature", "properties": {"n": 1}, "geometry": {"type": "Point", "coordinates": [10, 10]}},
      #|  {"type": "Feature", "properties": {"n": 2}, "geometry": {"type": "Point", "coordinates": [10.00001, 10]}},
      #|  {"type": "Feature", "properties": {"n": 4}, "geometry": {"type": "Point", "coordinates": [10, 10.05]}}]}
    ),
  )
  let properties = @cluster_props.cluster_properties(
    table,
    compiled("{\"total\": [\"+\", [\"get\", \"n\"]]}"),
  )
  let index = @tiler.ClusterIndex::new(table, properties~)
  let fs = index.tile(0, 0, 0).unwrap()
  assert_eq(fs.length(), 1)
  assert_eq((fs[0].count, fs[0].props), (3, [("total", Num(7.0))]))
  // At the zoom it breaks apart, 4 stands alone and 1 + 2 still cluster.
  let children = index.children(fs[0].cluster_id).unwrap()
  assert_eq(children.map(c => (c.count, c.props)), [
    (2, [("total", Num(3.0))]),
    (1, []),
  ])
  // Points keep their own properties and carry none of these.
  let leaves = index.leaves(fs[0].cluster_id).unwrap()
  assert_eq(leaves.map(l => l.props.length()), [0, 0, 0])
}
