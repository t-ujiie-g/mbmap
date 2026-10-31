///|
fn cmd(id : Int32, count : Int32) -> Int32 {
  (count << 3) | id
}

///|
/// Encodes a feature; `geometry` is the raw command/parameter integer stream.
fn feature_bytes(
  id? : UInt64,
  geom_type~ : Int32 = 3,
  tags~ : Array[Int32] = [],
  geometry~ : Array[Int32] = [],
  zigzag_params~ : Bool = true,
) -> Bytes {
  let w = @pbf.Writer::new()
  if id is Some(id) {
    w.write_tag(1, @pbf.WIRE_VARINT)
    w.write_varint(id)
  }
  if tags.length() > 0 {
    let t = @pbf.Writer::new()
    for v in tags {
      t.write_varint32(v)
    }
    w.write_tag(2, @pbf.WIRE_LEN)
    w.write_bytes(t.to_bytes()[:])
  }
  w.write_tag(3, @pbf.WIRE_VARINT)
  w.write_varint32(geom_type)
  let g = @pbf.Writer::new()
  // geometry is [header, params..., header, params...]; params are zigzagged.
  let mut i = 0
  while i < geometry.length() {
    let header = geometry[i]
    g.write_varint32(header)
    i += 1
    if (header & 7) != 7 {
      for _ in 0..<((header >> 3) * 2) {
        if i < geometry.length() {
          if zigzag_params {
            g.write_svarint32(geometry[i])
          } else {
            g.write_varint32(geometry[i])
          }
          i += 1
        }
      }
    }
  }
  w.write_tag(4, @pbf.WIRE_LEN)
  w.write_bytes(g.to_bytes()[:])
  w.to_bytes()
}

///|
fn layer_bytes(
  name : String,
  version? : Int32,
  extent? : Int32,
  keys~ : Array[String] = [],
  values~ : Array[@mvt.Value] = [],
  features~ : Array[Bytes] = [],
) -> Bytes {
  let w = @pbf.Writer::new()
  if version is Some(v) {
    w.write_tag(15, @pbf.WIRE_VARINT)
    w.write_varint32(v)
  }
  w.write_tag(1, @pbf.WIRE_LEN)
  w.write_string(name)
  for f in features {
    w.write_tag(2, @pbf.WIRE_LEN)
    w.write_bytes(f[:])
  }
  for k in keys {
    w.write_tag(3, @pbf.WIRE_LEN)
    w.write_string(k)
  }
  for v in values {
    let vw = @pbf.Writer::new()
    match v {
      String(s) => {
        vw.write_tag(1, @pbf.WIRE_LEN)
        vw.write_string(s)
      }
      Float(f) => {
        vw.write_tag(2, @pbf.WIRE_FIXED32)
        vw.write_fixed32(f.reinterpret_as_uint())
      }
      Double(d) => {
        vw.write_tag(3, @pbf.WIRE_FIXED64)
        vw.write_fixed64(d.reinterpret_as_uint64())
      }
      Int(i) => {
        vw.write_tag(4, @pbf.WIRE_VARINT)
        vw.write_varint(i.reinterpret_as_uint64())
      }
      UInt(u) => {
        vw.write_tag(5, @pbf.WIRE_VARINT)
        vw.write_varint(u)
      }
      SInt(s) => {
        vw.write_tag(6, @pbf.WIRE_VARINT)
        vw.write_sint64(s)
      }
      Bool(b) => {
        vw.write_tag(7, @pbf.WIRE_VARINT)
        vw.write_varint(if b { 1UL } else { 0UL })
      }
      Null => ()
    }
    w.write_tag(4, @pbf.WIRE_LEN)
    w.write_bytes(vw.to_bytes()[:])
  }
  if extent is Some(e) {
    w.write_tag(5, @pbf.WIRE_VARINT)
    w.write_varint32(e)
  }
  w.to_bytes()
}

///|
fn tile_bytes(layers : Array[Bytes]) -> Bytes {
  let w = @pbf.Writer::new()
  for l in layers {
    w.write_tag(3, @pbf.WIRE_LEN)
    w.write_bytes(l[:])
  }
  w.to_bytes()
}

///|
/// A layer holding just `f`, which is then feature 0.
fn single_feature(
  f : Bytes,
  keys~ : Array[String] = [],
  values~ : Array[@mvt.Value] = [],
) -> @mvt.Layer raise @mvt.MvtError {
  let tile = @mvt.Tile::parse(
    tile_bytes([layer_bytes("l", keys~, values~, features=[f])])[:],
  )
  tile.layers[0]
}

///|
test "layer metadata, defaults and duplicate names" {
  let tile = @mvt.Tile::parse(
    tile_bytes([
      layer_bytes("road", features=[feature_bytes(), feature_bytes()]),
      layer_bytes("water", version=2, extent=8192),
      layer_bytes("road", extent=512),
    ])[:],
  )
  assert_eq(tile.layers.length(), 3)
  let road = tile.layers[0]
  assert_eq(
    (road.name, road.version, road.extent, road.length()),
    ("road", 1, @mvt.DEFAULT_EXTENT, 2),
  )
  let water = tile.layer("water").unwrap()
  assert_eq((water.version, water.extent, water.length()), (2, 8192, 0))
  assert_eq(tile.layer("road").unwrap().extent, 512)
  assert_true(tile.layer("missing") is None)
}

///|
test "feature id, type and every value type" {
  let values : Array[@mvt.Value] = [
    String("東京"),
    Float(1.5),
    Double(-0.25),
    Int(-3L),
    UInt(18446744073709551615UL),
    SInt(-9007199254740993L),
    Bool(true),
    Null,
  ]
  let keys = ["s", "f", "d", "i", "u", "si", "b", "n"]
  let tags = []
  for i in 0..<keys.length() {
    tags.push(i)
    tags.push(i)
  }
  let l = single_feature(
    feature_bytes(id=7UL, geom_type=2, tags~),
    keys~,
    values~,
  )
  assert_eq(l.id(0), Some(7UL))
  assert_eq(l.geom_type(0), LineString)
  let props = l.properties(0)
  assert_eq(props.length(), keys.length())
  for i, k in keys {
    assert_eq(props[k], values[i])
  }
  let anon = single_feature(feature_bytes(geom_type=9))
  assert_eq(anon.id(0), None)
  assert_eq(anon.geom_type(0), Unknown)
  assert_eq(anon.properties(0).length(), 0)
}

///|
test "repeated keys keep the last value" {
  let l = single_feature(feature_bytes(tags=[0, 0, 0, 1]), keys=["k"], values=[
    Int(1L),
    Int(2L),
  ])
  assert_eq(l.properties(0)["k"], Int(2L))
}

///|
test "bad tag indices and odd tag counts fail Tile::parse" {
  let cases : Array[(Array[Int32], MvtErrorKind)] = [
    ([1, 0], Index(1)),
    ([0, 5], Index(5)),
    ([0, 0, 0], Odd),
  ]
  for c in cases {
    let (tags, kind) = c
    try
      single_feature(feature_bytes(tags~), keys=["k"], values=[Bool(true)])
    catch {
      IndexOutOfRange(pos=_, i) => assert_eq(kind, Index(i))
      OddTagCount(_) => assert_eq(kind, Odd)
      e => fail("unexpected \{Repr(e)}")
    } noraise {
      _ => fail("expected an error for \{Repr(tags)}")
    }
  }
}

///|
priv enum MvtErrorKind {
  Index(Int32)
  Odd
} derive(Debug, Eq)

///|
test "points, lines and closed polygons decode like loadGeometry" {
  // MultiPoint: one ring per MoveTo point.
  let mp = single_feature(
    feature_bytes(geom_type=1, geometry=[cmd(1, 2), 5, 7, 3, 2]),
  )
  assert_eq(mp.load_geometry(0), [[(5, 7)], [(8, 9)]])
  let line = single_feature(
    feature_bytes(geom_type=2, geometry=[cmd(1, 1), 2, 2, cmd(2, 2), 0, 8, 8, 0]),
  )
  assert_eq(line.load_geometry(0), [[(2, 2), (2, 10), (10, 10)]])
  // Polygon with a hole; ClosePath repeats the first point of each ring.
  let poly = single_feature(
    feature_bytes(geometry=[
      cmd(1, 1),
      0,
      0,
      cmd(2, 2),
      10,
      0,
      0,
      10,
      cmd(7, 1),
      cmd(1, 1),
      -8,
      -2,
      cmd(2, 2),
      1,
      0,
      0,
      1,
      cmd(7, 1),
    ]),
  )
  assert_eq(poly.geom_type(0), Polygon)
  assert_eq(mp.geom_type(0), Point)
  assert_eq(poly.load_geometry(0), [
    [(0, 0), (10, 0), (10, 10), (0, 0)],
    [(2, 8), (3, 8), (3, 9), (2, 8)],
  ])
}

///|
test "decode_geometry replaces the buffer contents on reuse" {
  let g = @mvt.Geometry::new()
  let a = single_feature(
    feature_bytes(geometry=[cmd(1, 1), 1, 1, cmd(2, 1), 1, 1]),
  )
  let b = single_feature(feature_bytes(geom_type=1, geometry=[cmd(1, 1), 4, 4]))
  assert_true(a.decode_geometry(0, g))
  assert_eq(
    (g.num_points(), g.num_rings(), g.ring_start(0), g.ring_ends[0]),
    (2, 1, 0, 2),
  )
  assert_true(b.decode_geometry(0, g))
  assert_eq(g.coords, [4, 4])
  assert_eq(g.ring_ends, [1])
  assert_true(single_feature(feature_bytes()).decode_geometry(0, g))
  assert_eq((g.num_points(), g.num_rings(), g.error()), (0, 0, None))
}

///|
test "invalid command streams fail without runaway loops" {
  let cases : Array[(String, Array[Int32])] = [
    ("unknown command", [cmd(3, 0)]),
    ("LineTo before MoveTo", [cmd(2, 1), 1, 1]),
    ("ClosePath count > 1", [cmd(1, 1), 0, 0, cmd(7, 100000000)]),
    ("count larger than the remaining bytes", [cmd(1, 0x1fffffff), 1, 1]),
    // Parameters cut short fail the count bound before any read runs past the end.
    ("truncated parameters", [cmd(1, 1), 3]),
  ]
  let g = @mvt.Geometry::new()
  for c in cases {
    let (name, geometry) = c
    let l = single_feature(feature_bytes(geometry~))
    assert_false(l.decode_geometry(0, g))
    guard g.error() is Some(InvalidCommand(_)) else {
      fail("\{name}: unexpected \{Repr(g.error())}")
    }
    try l.load_geometry(0) catch {
      InvalidCommand(_) => ()
      e => fail("\{name}: unexpected \{Repr(e)}")
    } noraise {
      _ => fail("\{name}: expected load_geometry to raise")
    }
  }
}

///|
test "malformed tile bytes are reported, not panicked on" {
  for
    bytes in [
      b"\x1a\x7f\x00", b"\x1a\x02\x0f\x00", b"\x1a", b"\x1a\x02\x12\x05",
    ] {
    try @mvt.Tile::parse(bytes[:]) catch {
      Malformed(_) => ()
      e => fail("unexpected \{Repr(e)}")
    } noraise {
      _ => fail("expected Malformed for \{Repr(bytes)}")
    }
  }
}

///|
test "key_index and property read single values without building a map" {
  let l = single_feature(
    feature_bytes(tags=[0, 0, 1, 1, 0, 2]),
    keys=["a", "b"],
    values=[Int(1L), String("x"), Int(3L)],
  )
  let a = l.key_index("a").unwrap()
  assert_eq(l.property(0, a), Some(Int(3L)))
  assert_eq(l.property(0, l.key_index("b").unwrap()), Some(String("x")))
  assert_eq(l.key_index("missing"), None)
  let other = single_feature(feature_bytes(tags=[1, 1]), keys=["a", "b"], values=[
    Int(1L),
    String("x"),
  ])
  assert_eq(other.property(0, 0), None)
}

///|
test "MvtError::message names the problem and its position" {
  assert_eq(
    @mvt.Malformed(@pbf.UnexpectedEof(pos=7)).message(),
    "malformed protobuf at 7: unexpected end",
  )
  assert_eq(
    @mvt.Malformed(@pbf.LengthOutOfRange(pos=2, 99)).message(),
    "malformed protobuf at 2: length out of range",
  )
  assert_eq(
    @mvt.InvalidCommand(pos=4, 5).message(),
    "invalid geometry command 5 at 4",
  )
  assert_eq(
    @mvt.IndexOutOfRange(pos=1, 9).message(),
    "tag index 9 out of range at 1",
  )
  assert_eq(@mvt.OddTagCount(pos=3).message(), "odd tag count at 3")
}
