///|
/// WKB written by hand: `header` starts a geometry in a byte order.
priv struct Wkb {
  out : Array[Byte]
  mut little : Bool
}

///|
fn Wkb::new() -> Wkb {
  { out: [], little: true, }
}

///|
fn Wkb::u32(self : Wkb, v : Int32) -> Wkb {
  let bytes = [v, v >> 8, v >> 16, v >> 24].map(b => (b & 255).to_byte())
  if !self.little {
    bytes.rev_in_place()
  }
  self.out.append(bytes)
  self
}

///|
fn Wkb::f64(self : Wkb, v : Double) -> Wkb {
  let bits = v.reinterpret_as_int64()
  let (hi, lo) = ((bits >> 32).to_int(), bits.to_int())
  if self.little {
    self.u32(lo).u32(hi)
  } else {
    self.u32(hi).u32(lo)
  }
}

///|
fn Wkb::header(self : Wkb, little : Bool, code : Int32) -> Wkb {
  self.little = little
  self.out.push(if little { b'\x01' } else { b'\x00' })
  self.u32(code)
}

///|
fn Wkb::xy(self : Wkb, x : Double, y : Double) -> Wkb {
  self.f64(x).f64(y)
}

///|
fn Wkb::read(self : Wkb) -> @geom.Table raise {
  @formats.read_wkb(Bytes::from_array(self.out)[:])
}

///|
fn Wkb::error(self : Wkb) -> String {
  try self.read() catch {
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
test "WKB points in both byte orders, one after another" {
  let t = Wkb::new()
    .header(true, 1)
    .xy(1, 2)
    .header(false, 1)
    .xy(3, -4.5)
    .read()
  assert_eq(t.kinds, [Point, Point])
  assert_eq(t.coords, [1.0, 2.0, 3.0, -4.5])
}

///|
test "ISO Z, M and ZM codes and EWKB flags drop the extra ordinates" {
  let t = Wkb::new()
    .header(true, 1001)
    .xy(1, 2)
    .f64(9)
    .header(false, 2002)
    .u32(2)
    .xy(0, 0)
    .f64(9)
    .xy(1, 1)
    .f64(9)
    .header(true, 3001)
    .xy(5, 6)
    .f64(9)
    .f64(9)
    // EWKB: Z and SRID 4326.
    .header(false, 0xa0000001)
    .u32(4326)
    .xy(7, 8)
    .f64(9)
    .header(true, 0x40000001)
    .xy(10, 11)
    .f64(9)
    .read()
  assert_eq(t.kinds, [Point, LineString, Point, Point, Point])
  assert_eq(t.coords, [
    1.0, 2.0, 0.0, 0.0, 1.0, 1.0, 5.0, 6.0, 7.0, 8.0, 10.0, 11.0,
  ])
}

///|
test "WKB polygons, multi geometries with members in their own byte order, collections" {
  let t = Wkb::new()
    .header(true, 3)
    .u32(2)
    .u32(4)
    .xy(0, 0)
    .xy(4, 0)
    .xy(4, 4)
    .xy(0, 0)
    .u32(3)
    .xy(1, 1)
    .xy(2, 1)
    .xy(1, 1)
    .header(false, 4)
    .u32(3)
    .header(true, 1)
    .xy(1, 2)
    .header(false, 1)
    .xy(@double.not_a_number, @double.not_a_number)
    .header(true, 1)
    .xy(3, 4)
    .header(true, 5)
    .u32(2)
    .header(true, 2)
    .u32(2)
    .xy(0, 0)
    .xy(1, 1)
    .header(false, 2)
    .u32(2)
    .xy(2, 2)
    .xy(3, 3)
    .header(true, 6)
    .u32(1)
    .header(true, 3)
    .u32(1)
    .u32(3)
    .xy(0, 0)
    .xy(1, 0)
    .xy(0, 0)
    .header(false, 7)
    .u32(2)
    .header(true, 7)
    .u32(1)
    .header(true, 1)
    .xy(8, 9)
    .header(true, 2)
    .u32(0)
    .read()
  assert_eq(t.kinds, [Polygon, MultiPoint, MultiLineString, MultiPolygon, Point])
  assert_eq(coords_of(t, 0).map(p => p.map(r => r.length() / 2)), [[4, 3]])
  // The NaN point is empty, so left out.
  assert_eq(coords_of(t, 1), [[[1.0, 2.0, 3.0, 4.0]]])
  assert_eq(coords_of(t, 2), [[[0.0, 0.0, 1.0, 1.0]], [[2.0, 2.0, 3.0, 3.0]]])
  assert_eq(coords_of(t, 3), [[[0.0, 0.0, 1.0, 0.0, 0.0, 0.0]]])
  assert_eq(coords_of(t, 4), [[[8.0, 9.0]]])
}

///|
test "empty WKB geometries make rows without geometry" {
  let t = Wkb::new()
    .header(true, 1)
    .xy(@double.not_a_number, @double.not_a_number)
    .header(true, 3)
    .u32(0)
    .header(true, 7)
    .u32(0)
    .read()
  assert_eq(t.kinds, [NoGeometry, NoGeometry, NoGeometry])
  assert_eq(t.coords.length(), 0)
}

///|
test "malformed WKB is refused" {
  let truncated = Wkb::new().header(true, 1).f64(1)
  assert_eq(truncated.error(), "malformed WKB at 13: unexpected end of data")
  let order = Wkb::new().header(true, 1).xy(1, 2)
  order.out[0] = b'\x02'
  assert_eq(order.error(), "malformed WKB at 0: invalid byte order")
  assert_eq(
    Wkb::new().header(true, 8).error(),
    "malformed WKB at 1: unsupported geometry type",
  )
  assert_eq(
    Wkb::new().header(true, 4001).error(),
    "malformed WKB at 1: unsupported geometry type",
  )
  assert_eq(
    Wkb::new().header(true, 0x20000001).u32(-1).xy(1, 2).error(),
    "malformed WKB at 5: invalid SRID",
  )
  assert_eq(
    Wkb::new()
    .header(true, 0x20000004)
    .u32(3857)
    .u32(1)
    .header(true, 0x20000001)
    .u32(4326)
    .xy(1, 2)
    .error(),
    "malformed WKB at 18: mixed SRIDs in one geometry",
  )
  assert_eq(
    Wkb::new().header(true, 2).u32(1000).xy(1, 2).error(),
    "malformed WKB at 9: count past the end of the data",
  )
  assert_eq(
    Wkb::new().header(true, 2).u32(-1).error(),
    "malformed WKB at 9: count past the end of the data",
  )
  assert_eq(
    Wkb::new().header(true, 4).u32(1).header(true, 2).u32(0).error(),
    "malformed WKB at 14: a member of the wrong type",
  )
  assert_eq(
    Wkb::new()
    .header(true, 2)
    .u32(2)
    .xy(0, 0)
    .xy(@double.not_a_number, 1)
    .error(),
    "malformed WKB at 41: coordinates must be finite",
  )
  let deep = Wkb::new()
  for _ in 0..<40 {
    deep.header(true, 7).u32(1) |> ignore
  }
  deep.header(true, 1).xy(1, 2) |> ignore
  assert_eq(deep.error(), "malformed WKB at 297: collections nested too deep")
}

///|
test "EWKB gives each row its SRID" {
  let b = Wkb::new()
    .header(true, 0x20000004)
    .u32(3857)
    .u32(2)
    .header(true, 1)
    .xy(1, 2)
    .header(false, 0x20000001)
    .u32(3857)
    .xy(3, 4)
    .header(true, 1)
    .xy(5, 6)
  let srids = []
  let t = @formats.read_wkb(Bytes::from_array(b.out)[:], srids~)
  assert_eq(t.length(), 2)
  assert_eq(srids, [3857, 0])
  let hex = []
  @formats.read_wkb_hex(
    b"0101000020e6100000000000000000084000000000000010c0",
    srids=hex,
  )
  |> ignore
  assert_eq(hex, [4326])
}

///|
test "hexadecimal WKB in either case, white space ignored" {
  let t = @formats.read_wkb_hex(
    b"0101000000000000000000F03F0000000000000040\n 0101000020e6100000000000000000084000000000000010c0",
  )
  assert_eq(t.coords, [1.0, 2.0, 3.0, -4.0])
  for bad in [b"010", b"01x1"] {
    try @formats.read_wkb_hex(bad) catch {
      e =>
        assert_eq(e.message(), "malformed WKB at 0: invalid hexadecimal text")
    } noraise {
      _ => fail("expected an error")
    }
  }
}
