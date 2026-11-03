///|
/// A query (docs/FORMATS.md, "Query") at `points` of a tile drawn 4096 px wide,
/// one tile unit per pixel, looking straight down.
fn query_request(
  points : Array[(Double, Double)],
  layers? : Array[Int32],
  symbols~ : Array[(Int32, Int32)] = [],
  filter~ : String = "",
) -> Bytes {
  let w = @core.ByteWriter::new()
  for v in [14.0, 1.0, 1.0, 4096.0, 4096.0, 1.0, 1.0] {
    w.f64(v)
  }
  let m = FixedArray::make(16, 0.0)
  m[0] = 1.0 / 2048.0
  m[5] = -1.0 / 2048.0
  m[10] = 1.0
  m[12] = -1.0
  m[13] = 1.0
  m[15] = 1.0
  for v in m {
    w.f64(v)
  }
  for _ in 0..<2 {
    w.u32(points.length())
    for p in points {
      w.f64(p.0)
      w.f64(p.1)
    }
  }
  match layers {
    Some(ls) => {
      w.u8(0)
      w.u32(ls.length())
      for l in ls {
        w.u32(l)
      }
    }
    None => {
      w.u8(1)
      w.u32(0)
    }
  }
  w.u32(symbols.length())
  for s in symbols {
    w.u32(s.0)
    w.u32(s.1)
  }
  w.utf8(filter)
  w.to_bytes()
}

///|
/// The (layer, feature) pairs of a query result, and the first record's
/// geometry type and ring sizes.
fn hits_of(b : Bytes) -> (Array[(Int32, Int32)], Int32, Array[Int32]) {
  let r = @core.ByteReader::new(b[:])
  let n = r.u32()
  let hits = []
  let mut first = (0, [])
  for k in 0..<n {
    let layer = r.u32()
    let index = r.u32()
    r.f64() |> ignore
    if r.u8() == @core.PROP_NUMBER {
      r.f64() |> ignore
    }
    let ty = r.u8()
    r.u32() |> ignore
    let rings = Array::makei(r.u32(), _ => r.u32())
    for _ in 0..<(rings.fold(init=0, (a, b) => a + b) * 2) {
      r.u32() |> ignore
    }
    for _ in 0..<r.u32() {
      r.utf8() |> ignore
      let tag = r.u8()
      if tag == @core.PROP_NUMBER {
        r.f64() |> ignore
      } else if tag == @core.PROP_STRING {
        r.utf8() |> ignore
      }
    }
    if k == 0 {
      first = (ty, rings)
    }
    hits.push((layer, index))
  }
  (hits, first.0, first.1)
}

///|
let query_style : String =
  #|{"sources": {"a": {"type": "vector", "tiles": ["t"]}},
  #| "layers": [
  #|  {"id": "area", "type": "fill", "source": "a", "source-layer": "poly"},
  #|  {"id": "road", "type": "line", "source": "a", "source-layer": "line", "paint": {"line-width": 4}},
  #|  {"id": "dot", "type": "circle", "source": "a", "source-layer": "pts"},
  #|  {"id": "name", "type": "symbol", "source": "a", "source-layer": "pts", "layout": {"text-field": "x"}}
  #|]}

///|
/// A square (0, 0)-(100, 100), a line along y = 200, and points at (50, 52)
/// and (300, 300).
fn query_tile() -> Bytes {
  tile_of([
    tile_with("poly", 3, [
      cmd(1, 1),
      0,
      0,
      cmd(2, 3),
      100,
      0,
      0,
      100,
      -100,
      0,
      cmd(7, 1),
    ]),
    tile_with("line", 2, [cmd(1, 1), 0, 200, cmd(2, 1), 100, 0]),
    tile_with("pts", 1, [cmd(1, 2), 50, 52, 250, 248]),
  ])
}

///|
test "query finds what is drawn under a point: fills, lines within half their width, circles" {
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(query_style)[:])
  let tile = query_tile()
  let out = p.query("a", tile[:], 14, query_request([(50.0, 50.0)])[:]).unwrap()
  let (hits, ty, rings) = hits_of(out)
  // The square, and the circle (radius 5) 2 px away, in style order; the line
  // is 150 px off.
  assert_eq(hits, [(0, 0), (2, 0)])
  assert_eq((ty, rings), (3, [5]))
  let near_line = p.query("a", tile[:], 14, query_request([(50.0, 201.5)])[:])
  assert_eq(hits_of(near_line.unwrap()).0, [(1, 0)])
  let off_line = p.query("a", tile[:], 14, query_request([(50.0, 202.5)])[:])
  assert_eq(hits_of(off_line.unwrap()).0, [])
}

///|
test "query finds heatmap points within their radius on the map" {
  let style =
    #|{"sources": {"a": {"type": "vector", "tiles": ["t"]}},
    #| "layers": [{"id": "heat", "type": "heatmap", "source": "a", "source-layer": "pts",
    #|   "paint": {"heatmap-radius": 10}}]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  let tile = query_tile()
  let near = p.query("a", tile[:], 14, query_request([(59.5, 52.0)])[:])
  assert_eq(hits_of(near.unwrap()).0, [(0, 0)])
  let off = p.query("a", tile[:], 14, query_request([(60.5, 52.0)])[:])
  assert_eq(hits_of(off.unwrap()).0, [])
}

///|
test "query keeps to the layers asked for, passes the filter, and returns the labels named" {
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(query_style)[:])
  let tile = query_tile()
  let only_dot = p.query(
    "a",
    tile[:],
    14,
    query_request([(50.0, 50.0)], layers=[2])[:],
  )
  assert_eq(hits_of(only_dot.unwrap()).0, [(2, 0)])
  let filtered = p.query(
    "a",
    tile[:],
    14,
    query_request(
      [(50.0, 50.0)],
      filter="[\"==\", [\"geometry-type\"], \"Point\"]",
    )[:],
  )
  assert_eq(hits_of(filtered.unwrap()).0, [(2, 0)])
  let labels = p.query(
    "a",
    tile[:],
    14,
    query_request([(4000.0, 4000.0)], symbols=[(3, 0), (3, 9)])[:],
  )
  assert_eq(hits_of(labels.unwrap()).0, [(3, 0)])
}

///|
test "query refuses a malformed request or tile" {
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(query_style)[:])
  let tile = query_tile()
  assert_eq(p.query("a", tile[:], 14, b"\x00\x01"[:]), None)
  assert_eq(p.error(), "malformed query")
  let bad_filter = query_request([(0.0, 0.0)], filter="[\"sqrt\", 2]")
  assert_eq(p.query("a", tile[:], 14, bad_filter[:]), None)
  assert_eq(
    p.query("a", b"\xff\xff"[:], 14, query_request([(0.0, 0.0)])[:]),
    None,
  )
}

///|
test "source_features gives a source layer's features that pass the filter, layer -1" {
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(query_style)[:])
  let tile = query_tile()
  let all = p.source_features("a", tile[:], 14, "pts", "").unwrap()
  // One MultiPoint feature with two points.
  let (hits, ty, rings) = hits_of(all)
  assert_eq((hits, ty), ([(-1, 0)], 1))
  assert_eq(rings.fold(init=0, (a, b) => a + b), 2)
  let none = p
    .source_features("a", tile[:], 14, "pts", "[\"has\", \"k\"]")
    .unwrap()
  assert_eq(hits_of(none).0, [])
  assert_eq(
    hits_of(p.source_features("a", tile[:], 14, "nope", "").unwrap()).0,
    [],
  )
  assert_eq(p.source_features("a", tile[:], 14, "pts", "[\"sqrt\"]"), None)
}

///|
/// Feature ranges (docs/FORMATS.md, "Feature ranges") as (entry, id, first,
/// count, outline first, outline count) records.
fn ranges_of(
  b : Bytes,
) -> Array[(Int32, @style.Value, Int32, Int32, Int32, Int32)] {
  let r = @core.ByteReader::new(b[:])
  let out = []
  for _ in 0..<r.u32() {
    let entry = r.u32()
    for _ in 0..<r.u32() {
      let id : @style.Value = match r.u8() {
        3 => Num(r.f64())
        4 => Str(r.utf8())
        _ => Null
      }
      let first = r.u32()
      let count = r.u32()
      let outline = r.u32()
      out.push((entry, id, first, count, outline, r.u32()))
    }
  }
  out
}

///|
test "feature_ranges lists each feature's indices in layers whose paint reads the state" {
  let style =
    #|{"sources": {"a": {"type": "vector", "tiles": ["t"], "promoteId": {"pts": "k"}}},
    #| "layers": [
    #|  {"id": "plain", "type": "line", "source": "a", "source-layer": "line"},
    #|  {"id": "lit", "type": "line", "source": "a", "source-layer": "line",
    #|   "paint": {"line-color": ["case", ["boolean", ["feature-state", "on"], false], "#f00", "#00f"]}},
    #|  {"id": "dots", "type": "circle", "source": "a", "source-layer": "pts",
    #|   "paint": {"circle-radius": ["number", ["feature-state", "r"], 3]}}
    #|]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  assert_true(p.process("a", query_tile()[:], 14))
  // "lit" keeps its own buffers (no alias of "plain"); the line has no id
  // (Null), the points take "k", which they lack (Null).
  assert_eq(p.out.layer_count(), 3)
  let ranges = ranges_of(p.feature_ranges())
  assert_eq(ranges.map(r => r.0), [1, 2])
  assert_eq(ranges.map(r => (r.1, r.2)), [(Null, 0), (Null, 0)])
  assert_true(ranges.iter().all(r => r.3 > 0 && r.3 % 3 == 0))
  // Lines and circles have no outline.
  assert_true(ranges.iter().all(r => r.4 == 0 && r.5 == 0))
  // A style without state layers has none.
  let q = @worker.TileProcessor::from_utf8(@utf8.encode(query_style)[:])
  assert_true(q.process("a", query_tile()[:], 14))
  assert_eq(ranges_of(q.feature_ranges()), [])
}

///|
test "query results carry promoted ids" {
  let style =
    #|{"sources": {"a": {"type": "vector", "tiles": ["t"], "promoteId": "n"}},
    #| "layers": [{"id": "area", "type": "fill", "source": "a", "source-layer": "poly"}]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  let out = p.query("a", query_tile()[:], 14, query_request([(50.0, 50.0)])[:])
  let r = @core.ByteReader::new(out.unwrap()[:])
  assert_eq((r.u32(), r.u32(), r.u32()), (1, 0, 0))
  r.f64() |> ignore
  // No property "n": the id is null.
  assert_eq(r.u8(), @core.PROP_NULL)
}

///|
test "a fill's ranges also cover its outline, so it follows the state too" {
  let style =
    #|{"sources": {"a": {"type": "vector", "tiles": ["t"]}},
    #| "layers": [
    #|  {"id": "lot", "type": "fill", "source": "a", "source-layer": "poly",
    #|   "paint": {"fill-color": ["case", ["boolean", ["feature-state", "on"], false], "#f00", "#00f"]}}
    #|]}
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style)[:])
  assert_true(p.process("a", query_tile()[:], 14))
  let ranges = ranges_of(p.feature_ranges())
  assert_true(ranges.length() > 0)
  // One edge (two indices) per point of each ring, from the start in order.
  assert_eq((ranges[0].2, ranges[0].4), (0, 0))
  assert_true(ranges.iter().all(r => r.5 > 0 && r.5 % 2 == 0))
  for k in 1..<ranges.length() {
    assert_eq(ranges[k].4, ranges[k - 1].4 + ranges[k - 1].5)
  }
}

///|
test "GeoJSON features' ranges take their ids, or the promoted property" {
  let style = (promote : String) => {
    "{\"sources\": {\"g\": {\"type\": \"geojson\", \"data\": \"x\"\{promote}}}, \"layers\": [{\"id\": \"c\", \"type\": \"circle\", \"source\": \"g\", \"paint\": {\"circle-radius\": [\"number\", [\"feature-state\", \"r\"], 3]}}, {\"id\": \"f\", \"type\": \"fill\", \"source\": \"g\", \"paint\": {\"fill-opacity\": [\"number\", [\"feature-state\", \"o\"], 1]}}]}"
  }
  let p = @worker.TileProcessor::from_utf8(@utf8.encode(style(""))[:])
  assert_true(p.process("g", geojson_tile()[:], 0))
  let ids = ranges_of(p.feature_ranges()).map(r => (r.0, r.1))
  // Circles go on every vertex: the square's corners too; only the square has an id.
  assert_eq(ids, [(0, Null), (0, Null), (0, Str("square")), (1, Str("square"))])
  let q = @worker.TileProcessor::from_utf8(
    @utf8.encode(style(", \"promoteId\": \"k\""))[:],
  )
  assert_true(q.process("g", geojson_tile()[:], 0))
  assert_eq(ranges_of(q.feature_ranges()).map(r => r.1), [
    Num(1.0),
    Null,
    Null,
    Null,
  ])
}
