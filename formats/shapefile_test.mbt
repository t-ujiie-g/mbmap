///|
/// Little- and big-endian bytes written by hand.
priv struct Out {
  b : Array[Byte]
}

///|
fn Out::new() -> Out {
  { b: [], }
}

///|
fn Out::le(self : Out, v : Int32) -> Out {
  for k in 0..<4 {
    self.b.push(((v >> (k * 8)) & 255).to_byte())
  }
  self
}

///|
fn Out::be(self : Out, v : Int32) -> Out {
  for k in 0..<4 {
    self.b.push(((v >> ((3 - k) * 8)) & 255).to_byte())
  }
  self
}

///|
fn Out::f64(self : Out, v : Double) -> Out {
  let bits = v.reinterpret_as_int64()
  self.le(bits.to_int()).le((bits >> 32).to_int())
}

///|
fn Out::text(self : Out, s : Bytes, width : Int32, pad : Byte) -> Out {
  for i in 0..<width {
    self.b.push(if i < s.length() { s[i] } else { pad })
  }
  self
}

///|
fn Out::bytes(self : Out) -> Bytes {
  Bytes::from_array(self.b)
}

///|
/// A .shp of shape `kind` with `records` (each a record's content).
fn shp(kind : Int32, records : Array[Bytes]) -> Bytes {
  let o = Out::new().be(9994)
  for _ in 0..<5 {
    o.be(0) |> ignore
  }
  o.be(50).le(1000).le(kind) |> ignore
  for _ in 0..<8 {
    o.f64(0) |> ignore
  }
  for i, r in records {
    o.be(i + 1).be(r.length() / 2) |> ignore
    o.b.append(r.to_array())
  }
  o.bytes()
}

///|
fn point(x : Double, y : Double) -> Bytes {
  Out::new().le(1).f64(x).f64(y).bytes()
}

///|
/// A polyline or polygon record (`kind` 3 or 5, or their Z and M types) of `parts`;
/// Z and M values follow the points.
fn poly(kind : Int32, parts : Array[Array[(Double, Double)]]) -> Bytes {
  let o = Out::new().le(kind).f64(0).f64(0).f64(0).f64(0)
  let n = parts.fold(init=0, (s, p) => s + p.length())
  o.le(parts.length()).le(n) |> ignore
  let mut at = 0
  for p in parts {
    o.le(at) |> ignore
    at += p.length()
  }
  for p in parts {
    for xy in p {
      o.f64(xy.0).f64(xy.1) |> ignore
    }
  }
  if kind > 10 {
    for _ in 0..<(if kind < 20 { 2 } else { 1 }) {
      o.f64(0).f64(0) |> ignore
      for _ in 0..<n {
        o.f64(7) |> ignore
      }
    }
  }
  o.bytes()
}

///|
fn utf8_text(b : Bytes) -> (Int32, Int32) -> String {
  (s, e) => "<" + @utf8.decode_lossy(b[s:e]) + ">"
}

///|
fn read_shp(shp : Bytes, dbf? : Bytes) -> @geom.Table raise {
  match dbf {
    Some(d) =>
      @formats.read_shapefile(shp[:], Some(d[:]), text=utf8_text(d), slow_number=(
        s,
        e,
      ) => @core.strconv_number(d[s:e]))
    None =>
      @formats.read_shapefile(shp[:], None, text=(_, _) => "", slow_number=(
        _,
        _,
      ) => 0.0)
  }
}

///|
fn shp_error(shp : Bytes, dbf? : Bytes) -> String {
  try read_shp(shp, dbf?) catch {
    e =>
      match e {
        @formats.ReadError::Invalid(_) as e => e.message()
        _ => "other error"
      }
  } noraise {
    _ => "read"
  }
}

///|
/// A .dbf of `fields` (name, type, length) and `records` (deleted, then the field
/// texts).
fn dbf(
  fields : Array[(Bytes, Char, Int32)],
  records : Array[(Bool, Array[Bytes])],
) -> Bytes {
  let len = fields.fold(init=1, (s, f) => s + f.2)
  let o = Out::new()
  o.b.append([b'\x03', b'\x7c', b'\x01', b'\x01'])
  o.le(records.length()) |> ignore
  o.b.append([(33 + 32 * fields.length()).to_byte(), b'\x00'])
  o.b.append([(len & 255).to_byte(), (len >> 8).to_byte()])
  o.text(b"", 20, b'\x00') |> ignore
  for f in fields {
    o.text(f.0, 11, b'\x00') |> ignore
    o.b.push(f.1.to_int().to_byte())
    o.text(b"", 4, b'\x00') |> ignore
    o.b.push(f.2.to_byte())
    o.text(b"", 15, b'\x00') |> ignore
  }
  o.b.push(b'\x0d')
  for r in records {
    o.b.push(if r.0 { b'*' } else { b' ' })
    for i, f in fields {
      o.text(r.1[i], f.2, b' ') |> ignore
    }
  }
  o.bytes()
}

///|
test "shapefile points with their DBF values; deleted records left out" {
  let s = shp(1, [
    point(1, 2),
    point(3, 4),
    Out::new().le(0).bytes(),
    point(5, 6),
    point(7, 8),
  ])
  let d = dbf(
    [
      (b"name", 'C', 8),
      (b"n", 'N', 6),
      (b"f", 'F', 8),
      (b"ok", 'L', 1),
      (b"day", 'D', 8),
      (b"memo", 'M', 10),
    ],
    [
      (false, [b"  a b", b"  12", b"-1.5e2", b"T", b"20240131", b"0000000001"]),
      (true, [b"gone", b"1", b"1", b"F", b"", b""]),
      (false, [b"caf\xc3\xa9", b"", b"*****", b"n", b"", b""]),
      (false, [b"", b"+3", b".5", b"?", b"2024", b""]),
    ],
  )
  let t = read_shp(s, dbf=d)
  assert_eq(t.kinds, [Point, NoGeometry, Point, Point])
  assert_eq(t.coords, [1.0, 2.0, 5.0, 6.0, 7.0, 8.0])
  assert_eq(t.columns.map(c => c.name), ["name", "n", "f", "ok", "day"])
  let col = (name : String) => t.column(name).unwrap().values
  assert_eq(col("name"), [
    Some(Str("a b")),
    Some(Str("<café>")),
    Some(Str("")),
    None,
  ])
  assert_eq(col("n"), [Some(Num(12.0)), Some(Null), Some(Num(3.0)), None])
  assert_eq(col("f"), [Some(Num(-150.0)), Some(Null), Some(Num(0.5)), None])
  assert_eq(col("ok"), [Some(Bool(true)), Some(Bool(false)), Some(Null), None])
  assert_eq(col("day"), [
    Some(Str("2024-01-31")),
    Some(Null),
    Some(Str("2024")),
    None,
  ])
}

///|
test "shapefile polygons: outer rings counter-clockwise, holes clockwise in the ring that holds them" {
  let outer = [(0.0, 0.0), (0.0, 10.0), (10.0, 10.0), (10.0, 0.0), (0.0, 0.0)]
  let hole = [(2.0, 2.0), (4.0, 2.0), (4.0, 4.0), (2.0, 4.0), (2.0, 2.0)]
  let island = [(20.0, 0.0), (20.0, 1.0), (21.0, 1.0), (20.0, 0.0)]
  let t = read_shp(
    shp(5, [poly(5, [outer, hole]), poly(15, [island, outer, hole])]),
  )
  assert_eq(t.kinds, [Polygon, MultiPolygon])
  assert_eq(t.ring_ends, [2, 3, 5])
  let ring = (r : Int32) => {
    let (s, e) = t.points(r)
    Array::makei(e - s, i => (t.coords[(s + i) * 2], t.coords[(s + i) * 2 + 1]))
  }
  assert_eq(ring(0), outer.rev())
  assert_eq(ring(1), hole.rev())
  assert_eq(ring(2), island.rev())
  // Rings all counter-clockwise read the other way round, as shpjs does.
  let flipped = read_shp(shp(5, [poly(25, [outer.rev(), hole.rev()])]))
  assert_eq(flipped.kinds, [Polygon])
  assert_eq(flipped.point_ends, [5, 10])
  // A hole in no outer ring either way becomes one.
  let stray = read_shp(
    shp(5, [
      poly(5, [outer, [(50.0, 50.0), (52.0, 50.0), (52.0, 52.0), (50.0, 50.0)]]),
    ]),
  )
  assert_eq(stray.kinds, [MultiPolygon])
}

///|
test "shapefile lines, multipoints and Z and M records" {
  let line = [(0.0, 0.0), (1.0, 1.0)]
  let multi = Out::new()
    .le(18)
    .f64(0)
    .f64(0)
    .f64(0)
    .f64(0)
    .le(2)
    .f64(1)
    .f64(2)
    .f64(3)
    .f64(4)
  let one = Out::new().le(8).f64(0).f64(0).f64(0).f64(0).le(1).f64(5).f64(6)
  let none = Out::new().le(3).f64(0).f64(0).f64(0).f64(0).le(0).le(0)
  let t = read_shp(
    shp(3, [
      poly(3, [line]),
      poly(23, [line, [], line]),
      multi.bytes(),
      one.bytes(),
      none.bytes(),
    ]),
  )
  assert_eq(t.kinds, [
    LineString,
    MultiLineString,
    MultiPoint,
    Point,
    NoGeometry,
  ])
  assert_eq(t.part_ends, [1, 3, 4, 5, 5])
  let z = Out::new().le(11).f64(9).f64(8).f64(7).f64(6).bytes()
  let nan = Out::new()
    .le(21)
    .f64(@double.not_a_number)
    .f64(@double.not_a_number)
    .f64(0)
    .bytes()
  let p = read_shp(shp(11, [z, nan]))
  assert_eq(p.kinds, [Point, NoGeometry])
  assert_eq(p.coords, [9.0, 8.0])
}

///|
test "malformed shapefiles are refused" {
  assert_eq(shp_error(b"\x00"), "malformed shapefile at 0: not a shapefile")
  assert_eq(
    shp_error(shp(31, [])),
    "malformed shapefile at 32: MultiPatch shapes are not supported",
  )
  assert_eq(
    shp_error(shp(2, [])),
    "malformed shapefile at 32: unsupported shape type 2",
  )
  assert_eq(
    shp_error(shp(1, [Out::new().le(9).f64(0).f64(0).bytes()])),
    "malformed shapefile at 108: unsupported shape type 9",
  )
  let cut = shp(1, [point(1, 2)])
  assert_eq(
    shp_error(cut[:cut.length() - 2].to_owned()),
    "malformed shapefile at 100: a record past the end of the file",
  )
  assert_eq(
    shp_error(shp(1, [Out::new().le(1).f64(0).bytes()])),
    "malformed shapefile at 108: a record cut short",
  )
  assert_eq(
    shp_error(shp(1, [Bytes::from_array([b'\x01', b'\x00'])])),
    "malformed shapefile at 108: a record cut short",
  )
  let counts = Out::new().le(3).f64(0).f64(0).f64(0).f64(0).le(1).le(100).le(0)
  assert_eq(
    shp_error(shp(3, [counts.bytes()])),
    "malformed shapefile at 108: counts past the end of the record",
  )
  let parts = Out::new()
    .le(3)
    .f64(0)
    .f64(0)
    .f64(0)
    .f64(0)
    .le(2)
    .le(1)
    .le(0)
    .le(5)
    .f64(0)
    .f64(0)
  assert_eq(
    shp_error(shp(3, [parts.bytes()])),
    "malformed shapefile at 156: invalid part start",
  )
  assert_eq(
    shp_error(shp(1, [point(@double.infinity, 0)])),
    "malformed shapefile at 112: coordinates must be finite",
  )
}

///|
test "malformed DBFs are refused" {
  let s = shp(1, [point(1, 2)])
  assert_eq(
    shp_error(s, dbf=b"\x03"),
    "malformed DBF at 0: the header is cut short",
  )
  let d = dbf([(b"a", 'C', 4)], [(false, [b"x"])])
  let bad = d.to_array()
  bad[8] = b'\x05'
  assert_eq(
    shp_error(s, dbf=Bytes::from_array(bad)),
    "malformed DBF at 0: invalid header",
  )
  let long = d.to_array()
  long[10] = b'\x02'
  assert_eq(
    shp_error(s, dbf=Bytes::from_array(long)),
    "malformed DBF at 0: fields longer than a record",
  )
  // Records the file does not hold whole are not read.
  let t = read_shp(s, dbf=d[:d.length() - 1].to_owned())
  assert_eq(t.kinds, [Point])
  assert_eq(t.columns.length(), 0)
}
