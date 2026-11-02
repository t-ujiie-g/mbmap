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
