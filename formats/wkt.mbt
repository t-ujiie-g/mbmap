///|
/// Reads WKT or EWKT geometries one after another into rows: one per member of each
/// (collections flattened), one without geometry for an EMPTY one; Z and M dropped.
/// `srids` gets each row's SRID (0 where none was given). `slow_number` as `read_csv`'s.
pub fn read_wkt(
  bytes : BytesView,
  slow_number~ : (Int32, Int32) -> Double = (s, e) => {
    @core.strconv_number(bytes[s:e])
  },
  srids? : Array[Int32],
) -> @geom.Table raise ReadError {
  wkt_table(bytes, slow_number, @geom.MAX_TABLE_POINTS, srids)
}

///|
/// `read_wkt` taking at most `max_points` points.
fn wkt_table(
  bytes : BytesView,
  slow_number : (Int32, Int32) -> Double,
  max_points : Int32,
  srids : Array[Int32]?,
) -> @geom.Table raise ReadError {
  let out = @geom.TableBuilder::new()
  let p = Wkt::new(bytes, slow_number, max_points)
  p.skip_space()
  while p.pos < p.end {
    p.shapes.clear()
    p.geometry(0)
    if p.error is Some((pos, m)) {
      raise Invalid(format="WKT", pos~, m)
    }
    p.used += p.shapes.points()
    p.shapes.emit(out, [], srids)
    p.skip_space()
  }
  out.finish()
}

///|
/// Reading state, over `b[..end]`. Errors are sticky: the first is kept and the
/// position jumps to the end.
priv struct Wkt {
  b : BytesView
  slow : (Int32, Int32) -> Double
  mut pos : Int32
  mut end : Int32
  mut error : (Int32, String)?
  shapes : Shapes
  max_points : Int32
  mut used : Int32
}

///|
fn Wkt::new(
  b : BytesView,
  slow : (Int32, Int32) -> Double,
  max_points : Int32,
) -> Wkt {
  {
    b,
    slow,
    pos: 0,
    end: b.length(),
    error: None,
    shapes: Shapes::new(),
    max_points,
    used: 0,
  }
}

///|
/// Reads the one geometry `b[start:end]` holds (white space around it allowed)
/// into `shapes`; false if it is not one.
fn Wkt::cell(self : Wkt, start : Int32, end : Int32) -> Bool {
  self.pos = start
  self.end = end
  self.error = None
  self.shapes.clear()
  self.geometry(0)
  self.skip_space()
  self.error is None && self.pos == end
}

///|
fn Wkt::fail(self : Wkt, message : String) -> Unit {
  if self.error is None {
    self.error = Some((self.pos, message))
  }
  self.pos = self.end
}

///|
fn Wkt::skip_space(self : Wkt) -> Unit {
  while self.pos < self.end {
    match self.b[self.pos] {
      b' ' | b'\t' | b'\n' | b'\r' => self.pos += 1
      _ => return
    }
  }
}

///|
/// The next byte after white space, or -1 at the end.
fn Wkt::peek(self : Wkt) -> Int32 {
  self.skip_space()
  if self.pos < self.end {
    self.b[self.pos].to_int()
  } else {
    -1
  }
}

///|
fn Wkt::expect(self : Wkt, c : Char) -> Bool {
  if self.peek() == c.to_int() {
    self.pos += 1
    true
  } else {
    self.fail("expected '\{c}'")
    false
  }
}

///|
/// Takes `c` if it comes next.
fn Wkt::take(self : Wkt, c : Char) -> Bool {
  if self.peek() == c.to_int() {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
/// The range of the ASCII letters (and '_') at the position.
fn Wkt::word(self : Wkt) -> (Int32, Int32) {
  self.skip_space()
  let start = self.pos
  while self.pos < self.end {
    let c = self.b[self.pos]
    if (c >= b'A' && c <= b'Z') || (c >= b'a' && c <= b'z') || c == b'_' {
      self.pos += 1
    } else {
      break
    }
  }
  (start, self.pos)
}

///|
/// Whether `b[start:end]` is `name` (upper case) in any case.
fn Wkt::named(self : Wkt, start : Int32, end : Int32, name : String) -> Bool {
  if end - start != name.length() {
    return false
  }
  for i in 0..<name.length() {
    let c = self.b[start + i].to_int()
    let upper = if c >= 'a'.to_int() && c <= 'z'.to_int() { c - 32 } else { c }
    if upper != name.code_unit_at(i).to_int() {
      return false
    }
  }
  true
}

///|
/// Geometry types by WKB code (1 to 7).
let wkt_types : FixedArray[String] = [
  "", "POINT", "LINESTRING", "POLYGON", "MULTIPOINT", "MULTILINESTRING", "MULTIPOLYGON",
  "GEOMETRYCOLLECTION",
]

///|
/// The ordinates per position a dimension tag (`Z`, `M`, `ZM`; empty for none)
/// asks for: 0 for none (2 to 4 accepted), -1 for something else.
fn Wkt::dimension(self : Wkt, start : Int32, end : Int32) -> Int32 {
  if start == end {
    0
  } else if self.named(start, end, "Z") || self.named(start, end, "M") {
    3
  } else if self.named(start, end, "ZM") {
    4
  } else {
    -1
  }
}

///|
/// Reads a geometry (with an `SRID=n;` prefix at the top) into `shapes`.
fn Wkt::geometry(self : Wkt, depth : Int32) -> Unit {
  if depth > MAX_GEOMETRY_DEPTH {
    self.fail("collections nested too deep")
    return
  }
  let mut first = self.word()
  while depth == 0 && self.named(first.0, first.1, "SRID") {
    if !self.expect('=') {
      return
    }
    let mut srid = 0
    let digits = self.pos
    while self.pos < self.end &&
          self.b[self.pos] >= b'0' &&
          self.b[self.pos] <= b'9' &&
          self.pos - digits < 9 {
      srid = srid * 10 + (self.b[self.pos].to_int() - '0'.to_int())
      self.pos += 1
    }
    if self.pos == digits || !self.expect(';') {
      self.fail("invalid SRID")
      return
    }
    self.shapes.srid = srid
    first = self.word()
  }
  let (s, e) = first
  // The type, with its dimension attached (`POINTZ`) or after it (`POINT Z`).
  let mut code = 0
  let mut dims = -1
  for c in 1..<wkt_types.length() {
    let name = wkt_types[c]
    if e - s >= name.length() && self.named(s, s + name.length(), name) {
      let d = self.dimension(s + name.length(), e)
      if d >= 0 {
        code = c
        dims = d
      }
    }
  }
  if code == 0 {
    self.pos = s
    self.fail("expected a geometry type")
    return
  }
  let (ws, we) = self.word()
  if dims == 0 && self.dimension(ws, we) > 0 {
    dims = self.dimension(ws, we)
    let (es, ee) = self.word()
    if self.named(es, ee, "EMPTY") {
      return
    }
    self.pos = es
  } else if self.named(ws, we, "EMPTY") {
    return
  } else {
    self.pos = ws
  }
  match code {
    1 => {
      self.expect('(') |> ignore
      self.position(dims)
      self.expect(')') |> ignore
      self.shapes.end_ring()
      self.shapes.end_part()
      self.shapes.end_member(Point)
    }
    2 => {
      self.positions(dims, false)
      self.shapes.end_part()
      self.shapes.end_member(LineString)
    }
    3 => {
      self.polygon(dims)
      self.shapes.end_member(Polygon)
    }
    4 => {
      self.positions(dims, true)
      self.shapes.end_part()
      self.shapes.end_member(MultiPoint)
    }
    5 => {
      self.list(() => {
        self.positions(dims, false)
        self.shapes.end_part()
      })
      self.shapes.end_member(MultiLineString)
    }
    6 => {
      self.list(() => self.polygon(dims))
      self.shapes.end_member(MultiPolygon)
    }
    _ => self.list(() => self.geometry(depth + 1))
  }
}

///|
/// `(item, item, ...)`, calling `item` for each.
fn Wkt::list(self : Wkt, item : () -> Unit) -> Unit {
  if !self.expect('(') {
    return
  }
  while self.error is None {
    item()
    if !self.take(',') {
      break
    }
  }
  self.expect(')') |> ignore
}

///|
/// A polygon's rings, `((x y, ...), (x y, ...))`, as one part.
fn Wkt::polygon(self : Wkt, dims : Int32) -> Unit {
  self.list(() => self.positions(dims, false))
  self.shapes.end_part()
}

///|
/// `(x y, x y, ...)` as one ring; `wrapped` also takes each position in its own
/// parentheses (`MULTIPOINT((1 2), (3 4))`).
fn Wkt::positions(self : Wkt, dims : Int32, wrapped : Bool) -> Unit {
  self.list(() => {
    if wrapped && self.take('(') {
      self.position(dims)
      self.expect(')') |> ignore
    } else {
      self.position(dims)
    }
  })
  self.shapes.end_ring()
}

///|
/// A position of `dims` ordinates (2 to 4 if 0) separated by white space; x and
/// y are kept and must be finite.
fn Wkt::position(self : Wkt, dims : Int32) -> Unit {
  let x = self.ordinate()
  let y = self.ordinate()
  let most = if dims == 0 { 4 } else { dims }
  let mut n = 2
  while n < most && self.error is None {
    let at = self.pos
    self.skip_space()
    if self.pos == at || !self.number_next() {
      self.pos = at
      if dims != 0 {
        self.fail("expected \{dims} ordinates")
      }
      break
    }
    self.ordinate() |> ignore
    n += 1
  }
  if self.error is Some(_) {
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

///|
/// Whether a number starts at the position.
fn Wkt::number_next(self : Wkt) -> Bool {
  self.pos < self.end &&
  (match self.b[self.pos] {
    b'0'..<=b'9' | b'-' | b'+' | b'.' => true
    _ => false
  })
}

///|
/// A number after white space, ending at white space, ',' or ')'.
fn Wkt::ordinate(self : Wkt) -> Double {
  self.skip_space()
  let (v, after) = read_decimal(self.b, self.pos, self.end, true, self.slow)
  if after == self.pos {
    self.fail("expected a number")
    return 0.0
  }
  // A number must end at white space, ',' or ')'.
  if after < self.end {
    match self.b[after] {
      b' ' | b'\t' | b'\n' | b'\r' | b',' | b')' => ()
      _ => {
        self.pos = after
        self.fail("expected a number")
        return 0.0
      }
    }
  }
  self.pos = after
  v
}
