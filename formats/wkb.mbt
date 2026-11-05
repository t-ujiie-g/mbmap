///|
/// Reads WKB or EWKB geometries one after another into rows as `read_wkt` does, each in
/// its byte order with an ISO code or EWKB flags (SRIDs to `srids`). A point of NaN
/// coordinates is empty; any other coordinate must be finite.
pub fn read_wkb(
  bytes : BytesView,
  srids? : Array[Int32],
) -> @geom.Table raise ReadError {
  wkb_table(bytes, MAX_POINTS, srids)
}

///|
/// `read_wkb` of hexadecimal text (as PostGIS prints EWKB), white space ignored.
pub fn read_wkb_hex(
  text : BytesView,
  srids? : Array[Int32],
) -> @geom.Table raise ReadError {
  match unhex(text, 0, text.length()) {
    Some(bytes) => wkb_table(bytes[:], MAX_POINTS, srids)
    None => raise Invalid(format="WKB", pos=0, "invalid hexadecimal text")
  }
}

///|
/// The bytes the hexadecimal digits of `text[start:end]` spell, ASCII white space
/// ignored; None for an odd count or another character.
fn unhex(text : BytesView, start : Int32, end : Int32) -> Bytes? {
  let out : Array[Byte] = Array(capacity=(end - start) / 2)
  let mut high = -1
  for i in start..<end {
    let c = text[i]
    let v = match c {
      b'0'..<=b'9' => c.to_int() - '0'.to_int()
      b'a'..<=b'f' => c.to_int() - 'a'.to_int() + 10
      b'A'..<=b'F' => c.to_int() - 'A'.to_int() + 10
      b' ' | b'\t' | b'\n' | b'\r' => continue
      _ => return None
    }
    if high < 0 {
      high = v
    } else {
      out.push((high * 16 + v).to_byte())
      high = -1
    }
  }
  if high >= 0 {
    return None
  }
  Some(Bytes::from_array(out))
}

///|
/// `read_wkb` taking at most `max_points` points.
fn wkb_table(
  bytes : BytesView,
  max_points : Int32,
  srids : Array[Int32]?,
) -> @geom.Table raise ReadError {
  let out = @geom.TableBuilder::new()
  let p = Wkb::new(bytes, max_points)
  while p.pos < bytes.length() {
    p.shapes.clear()
    p.geometry(0)
    if p.error is Some((pos, m)) {
      raise Invalid(format="WKB", pos~, m)
    }
    p.used += p.shapes.points()
    p.shapes.emit(out, [], srids)
  }
  out.finish()
}

///|
/// Reading state; errors are sticky as `Wkt`'s.
priv struct Wkb {
  mut b : BytesView
  mut pos : Int32
  mut little : Bool
  mut error : (Int32, String)?
  shapes : Shapes
  max_points : Int32
  mut used : Int32
}

///|
fn Wkb::new(b : BytesView, max_points : Int32) -> Wkb {
  {
    b,
    pos: 0,
    little: true,
    error: None,
    shapes: Shapes::new(),
    max_points,
    used: 0,
  }
}

///|
/// Reads the one geometry `b` holds into `shapes`; false if it is not one.
fn Wkb::cell(self : Wkb, b : BytesView) -> Bool {
  self.b = b
  self.pos = 0
  self.error = None
  self.shapes.clear()
  self.geometry(0)
  self.error is None && self.pos == b.length()
}

///|
fn Wkb::fail(self : Wkb, message : String) -> Unit {
  if self.error is None {
    self.error = Some((self.pos, message))
  }
  self.pos = self.b.length()
}

///|
fn Wkb::u32(self : Wkb) -> Int32 {
  if self.pos + 4 > self.b.length() {
    self.fail("unexpected end of data")
    return 0
  }
  let b = self.b
  let i = self.pos
  self.pos += 4
  if self.little {
    b[i].to_int() |
    (b[i + 1].to_int() << 8) |
    (b[i + 2].to_int() << 16) |
    (b[i + 3].to_int() << 24)
  } else {
    (b[i].to_int() << 24) |
    (b[i + 1].to_int() << 16) |
    (b[i + 2].to_int() << 8) |
    b[i + 3].to_int()
  }
}

///|
fn Wkb::f64(self : Wkb) -> Double {
  let (hi, lo) = if self.little {
    let lo = self.u32()
    (self.u32(), lo)
  } else {
    let hi = self.u32()
    (hi, self.u32())
  }
  ((hi.to_int64() << 32) | (lo.to_int64() & 0xffffffffL)).reinterpret_as_double()
}

///|
/// A count of items of at least `size` bytes each that must fit in what is
/// left; -1 (and an error) otherwise.
fn Wkb::count(self : Wkb, size : Int32) -> Int32 {
  let n = self.u32()
  if n < 0 || n > (self.b.length() - self.pos) / size {
    self.fail("count past the end of the data")
    return -1
  }
  n
}

///|
/// A geometry's byte order and type: its WKB code (1 to 7) and the ordinates per
/// position, or (0, 0) and an error.
fn Wkb::header(self : Wkb) -> (Int32, Int32) {
  if self.pos >= self.b.length() {
    self.fail("unexpected end of data")
    return (0, 0)
  }
  match self.b[self.pos] {
    b'\x00' => self.little = false
    b'\x01' => self.little = true
    _ => {
      self.fail("invalid byte order")
      return (0, 0)
    }
  }
  self.pos += 1
  let at = self.pos
  let t = self.u32()
  let flags = t & 0xe0000000
  let (code, ordinates) = if flags != 0 {
    let z = if t < 0 { 1 } else { 0 }
    let m = if (t & 0x40000000) != 0 { 1 } else { 0 }
    (t & 0x1fffffff, 2 + z + m)
  } else {
    let extra = match t / 1000 {
      0 => 0
      1 | 2 => 1
      3 => 2
      _ => -1
    }
    (if extra < 0 { 0 } else { t % 1000 }, 2 + extra)
  }
  if code < 1 || code > 7 {
    self.pos = at
    self.fail("unsupported geometry type")
    return (0, 0)
  }
  if (t & 0x20000000) != 0 {
    let srid = self.u32()
    if !self.shapes.take_srid(srid, m => {
        self.pos -= 4
        self.fail(m)
      }) {
      return (0, 0)
    }
  }
  (code, ordinates)
}

///|
/// Reads a geometry into `shapes`.
fn Wkb::geometry(self : Wkb, depth : Int32) -> Unit {
  if depth > MAX_GEOMETRY_DEPTH {
    self.fail("collections nested too deep")
    return
  }
  let (code, ordinates) = self.header()
  match code {
    1 => {
      self.body(code, ordinates)
      self.shapes.end_ring()
      self.shapes.end_part()
      self.shapes.end_member(Point)
    }
    2 => {
      self.body(code, ordinates)
      self.shapes.end_member(LineString)
    }
    3 => {
      self.body(code, ordinates)
      self.shapes.end_member(Polygon)
    }
    4 | 5 | 6 => {
      let n = self.count(9)
      let little = self.little
      for _ in 0..<n {
        let (part, part_ordinates) = self.header()
        if self.error is Some(_) {
          break
        }
        if part != code - 3 {
          self.fail("a member of the wrong type")
          break
        }
        self.body(part, part_ordinates)
      }
      self.little = little
      if code == 4 {
        self.shapes.end_ring()
        self.shapes.end_part()
      }
      self.shapes.end_member(
        match code {
          4 => MultiPoint
          5 => MultiLineString
          _ => MultiPolygon
        },
      )
    }
    7 => {
      let n = self.count(9)
      for _ in 0..<n {
        let little = self.little
        self.geometry(depth + 1)
        self.little = little
      }
    }
    _ => ()
  }
}

///|
/// The coordinates of a point (without closing its ring), a line (one ring and
/// part) or a polygon (one part).
fn Wkb::body(self : Wkb, code : Int32, ordinates : Int32) -> Unit {
  let size = ordinates * 8
  match code {
    1 => self.position(ordinates, true)
    2 => {
      for _ in 0..<self.count(size) {
        self.position(ordinates, false)
      }
      self.shapes.end_ring()
      self.shapes.end_part()
    }
    _ => {
      for _ in 0..<self.count(4) {
        for _ in 0..<self.count(size) {
          self.position(ordinates, false)
        }
        self.shapes.end_ring()
      }
      self.shapes.end_part()
    }
  }
}

///|
/// A position of `ordinates` f64s, x and y kept; a lone point (`point`) of NaN
/// x and y is empty.
fn Wkb::position(self : Wkb, ordinates : Int32, point : Bool) -> Unit {
  let x = self.f64()
  let y = self.f64()
  for _ in 2..<ordinates {
    self.f64() |> ignore
  }
  if self.error is Some(_) || (point && x.is_nan() && y.is_nan()) {
    return
  }
  if x.is_nan() || y.is_nan() || x.is_inf() || y.is_inf() {
    self.fail("coordinates must be finite")
  } else if self.used + self.shapes.points() >= self.max_points {
    self.fail("too many points")
  } else {
    self.shapes.point(x, y)
  }
}
