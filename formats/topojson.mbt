///|
/// Reads a TopoJSON Topology into a table: the object named `object`, or the first
/// one, as topojson-client's `feature` makes features of it (a GeometryCollection
/// object's members are features; collections inside them are flattened into rows,
/// as `read_wkt` does), each with its `id` and `properties` (nested values as their
/// JSON text). Returns the table and the names of every object, in order.
/// `slow_number` as `read_geojson`'s.
pub fn read_topojson(
  bytes : BytesView,
  object : String?,
  slow_number~ : (Int32, Int32) -> Double,
) -> (@geom.Table, Array[String]) raise ReadError {
  topojson_table(bytes, object, slow_number, MAX_POINTS)
}

///|
/// Reading state over `Parser`'s JSON primitives (numbers read by `read_decimal`):
/// the arcs (`coords`, `ends`; positions once decoded), the transform (scale x and
/// y, translate x and y), the objects' names and value ranges, and the geometry
/// being read.
priv struct Topo {
  p : Parser
  coords : Array[Double]
  ends : Array[Int32]
  transform : FixedArray[Double]
  mut quantized : Bool
  names : Array[String]
  objects : Array[Int32]
  shapes : Shapes
  max_points : Int32
}

///|
fn topojson_table(
  bytes : BytesView,
  object : String?,
  slow_number : (Int32, Int32) -> Double,
  max_points : Int32,
) -> (@geom.Table, Array[String]) raise ReadError {
  let p : Parser = {
    b: bytes,
    slow_number,
    pos: 0,
    error: None,
    depth: 0,
    out: @geom.TableBuilder::new(),
    keys: [],
    next_key: 0,
    max_points,
  }
  let t : Topo = {
    p,
    coords: [],
    ends: [],
    transform: [1.0, 1.0, 0.0, 0.0],
    quantized: false,
    names: [],
    objects: [],
    shapes: Shapes::new(),
    max_points,
  }
  let mut topology = false
  p.object((s, e, esc) => {
    if esc {
      t.skip()
    } else if p.matches(s, e, "type") {
      let (ts, te, _) = p.string_raw()
      topology = p.matches(ts, te, "Topology")
    } else if p.matches(s, e, "arcs") {
      p.array(() => {
        p.array(() => t.position(t.coords))
        t.ends.push(t.coords.length() / 2)
      })
    } else if p.matches(s, e, "transform") {
      t.quantized = true
      p.object((ks, ke, kesc) => {
        let at = if kesc {
          -1
        } else if p.matches(ks, ke, "scale") {
          0
        } else if p.matches(ks, ke, "translate") {
          2
        } else {
          -1
        }
        if at < 0 {
          t.skip()
        } else {
          let pair = []
          t.position(pair)
          if pair.length() == 2 {
            t.transform[at] = pair[0]
            t.transform[at + 1] = pair[1]
          }
        }
      })
    } else if p.matches(s, e, "objects") {
      p.object((ks, ke, kesc) => {
        t.names.push(p.text(ks, ke, kesc))
        p.peek() |> ignore
        t.objects.push(p.pos)
        t.skip()
      })
    } else {
      t.skip()
    }
  })
  if p.error is None && p.peek() != -1 {
    p.fail("unexpected data after the TopoJSON value")
  }
  if p.error is None && !topology {
    p.pos = 0
    p.fail("not a TopoJSON Topology")
  }
  if p.error is None {
    t.decode_arcs()
    let i = match object {
      Some(name) => t.names.search(name).unwrap_or(-1)
      None => if t.objects.is_empty() { -1 } else { 0 }
    }
    if i >= 0 {
      t.feature_rows(t.objects[i])
    } else if object is Some(name) {
      p.fail("no object named \"\{name}\"")
    }
  }
  match p.error {
    Some((pos, m)) => raise Invalid(format="TopoJSON", pos~, m)
    None => (p.out.finish(), t.names)
  }
}

///|
/// A JSON number (`read_decimal`, `slow_number` past its fast path).
fn Topo::number(self : Topo) -> Double {
  let p = self.p
  p.peek() |> ignore
  let (v, end) = read_decimal(p.b, p.pos, p.b.length(), false, p.slow_number)
  if end == p.pos {
    p.fail("invalid number")
  }
  p.pos = end
  v
}

///|
/// Skips any JSON value.
fn Topo::skip(self : Topo) -> Unit {
  let p = self.p
  match p.peek() {
    '{' | '[' => p.skip_nested()
    '"' => p.string_raw() |> ignore
    't' => p.literal("true") |> ignore
    'f' => p.literal("false") |> ignore
    'n' => p.literal("null") |> ignore
    _ => self.number() |> ignore
  }
}

///|
/// A property value as `Parser::prop` reads one.
fn Topo::prop(self : Topo) -> @geom.Prop {
  let p = self.p
  match p.peek() {
    '"' => {
      let (s, e, esc) = p.string_raw()
      Str(p.text(s, e, esc))
    }
    't' => if p.literal("true") { Bool(true) } else { Null }
    'f' => if p.literal("false") { Bool(false) } else { Null }
    'n' => {
      p.literal("null") |> ignore
      Null
    }
    '{' | '[' => {
      let start = p.pos
      p.skip_nested()
      Str(p.compact(start, p.pos))
    }
    _ => Num(self.number())
  }
}

///|
/// Reads a position's elements (two or more numbers), adding x and y to `into`.
fn Topo::position(self : Topo, into : Array[Double]) -> Unit {
  let mut n = 0
  self.p.array(() => {
    let v = self.number()
    if n < 2 {
      into.push(v)
    }
    n += 1
  })
  if n < 2 {
    self.p.fail("a position needs two numbers")
  } else if into.length() > 2 * self.max_points {
    self.p.fail("too many points")
  }
}

///|
/// With a transform, turns the arcs' quantized deltas into positions.
fn Topo::decode_arcs(self : Topo) -> Unit {
  guard self.quantized else { return }
  let (c, t) = (self.coords, self.transform)
  for a in 0..<self.ends.length() {
    let mut x = 0.0
    let mut y = 0.0
    for i in @geom.start_of(self.ends, a)..<self.ends[a] {
      x += c[i * 2]
      y += c[i * 2 + 1]
      c[i * 2] = x * t[0] + t[2]
      c[i * 2 + 1] = y * t[1] + t[3]
    }
  }
}

///|
/// Runs `f` with the parser at `at`, then puts it back.
fn Topo::at(self : Topo, at : Int32, f : () -> Unit) -> Unit {
  let pos = self.p.pos
  self.p.pos = at
  f()
  if self.p.error is None {
    self.p.pos = pos
  }
}

///|
/// Where a geometry object's members `type`, `arcs`, `coordinates`, `geometries`,
/// `properties` and `id` start (-1 where absent), the parser past it.
fn Topo::members(self : Topo) -> FixedArray[Int32] {
  let p = self.p
  let m = FixedArray::make(6, -1)
  if p.peek() != '{'.to_int() {
    self.skip()
    return m
  }
  p.object((s, e, esc) => {
    let i = if esc {
      -1
    } else if p.matches(s, e, "type") {
      0
    } else if p.matches(s, e, "arcs") {
      1
    } else if p.matches(s, e, "coordinates") {
      2
    } else if p.matches(s, e, "geometries") {
      3
    } else if p.matches(s, e, "properties") {
      4
    } else if p.matches(s, e, "id") {
      5
    } else {
      -1
    }
    if i >= 0 {
      p.peek() |> ignore
      m[i] = p.pos
    }
    self.skip()
  })
  m
}

///|
/// The type named at `at` (a string), or "" for none.
fn Topo::type_at(self : Topo, at : Int32) -> String {
  let mut name = ""
  if at >= 0 {
    self.at(at, () => {
      if self.p.peek() == '"'.to_int() {
        let (s, e, esc) = self.p.string_raw()
        name = self.p.text(s, e, esc)
      }
    })
  }
  name
}

///|
/// Calls `f` at each element of the array at `at` (if any), which `f` must read.
fn Topo::each(self : Topo, at : Int32, f : () -> Unit) -> Unit {
  if at >= 0 {
    self.at(at, () => self.p.array(f))
  }
}

///|
/// The rows of the object at `at`: its members' if it is a GeometryCollection, else its own.
fn Topo::feature_rows(self : Topo, at : Int32) -> Unit {
  let mut m = FixedArray::make(0, 0)
  self.at(at, () => m = self.members())
  if self.type_at(m[0]) == "GeometryCollection" {
    self.each(m[3], () => {
      let start = self.p.pos
      self.skip()
      self.feature(start)
    })
  } else {
    self.feature(at)
  }
}

///|
/// Adds the feature of the geometry object at `at`: a row per member of its
/// geometry, each with its id and properties.
fn Topo::feature(self : Topo, at : Int32) -> Unit {
  let p = self.p
  let mut m = FixedArray::make(0, 0)
  self.at(at, () => m = self.members())
  self.shapes.clear()
  self.geometry(m)
  let props = []
  if m[4] >= 0 {
    self.at(m[4], () => {
      if p.peek() == '{'.to_int() {
        p.object((s, e, esc) => props.push((p.key(s, e, esc), self.prop())))
      }
    })
  }
  let mut id = None
  if m[5] >= 0 {
    self.at(m[5], () => {
      id = match self.prop() {
        Null => None
        v => Some(v)
      }
    })
  }
  if p.out.table.coords.length() / 2 + self.shapes.points() > self.max_points {
    p.fail("too many points")
  }
  if p.error is None {
    self.shapes.emit(p.out, props, None, id~)
  }
}

///|
/// Adds the geometry whose members are `m` to `shapes`, collections flattened (as
/// deep as `MAX_GEOJSON_DEPTH` lets the JSON nest).
fn Topo::geometry(self : Topo, m : FixedArray[Int32]) -> Unit {
  let s = self.shapes
  let t = self.transform
  let points = (at : Int32) => {
    let xy = []
    self.at(at, () => self.position(xy))
    if xy.length() == 2 && self.quantized {
      s.point(xy[0] * t[0] + t[2], xy[1] * t[1] + t[3])
    } else if xy.length() == 2 {
      s.point(xy[0], xy[1])
    }
  }
  match self.type_at(m[0]) {
    "GeometryCollection" => self.each(m[3], () => self.geometry(self.members()))
    "Point" =>
      if m[2] >= 0 {
        points(m[2])
        s.end_ring()
        s.end_part()
        s.end_member(Point)
      }
    "MultiPoint" => {
      self.each(m[2], () => {
        points(self.p.pos)
        self.skip()
      })
      s.end_ring()
      s.end_part()
      s.end_member(MultiPoint)
    }
    "LineString" => {
      self.at(m[1], () => self.line(false))
      s.end_part()
      s.end_member(LineString)
    }
    "MultiLineString" => {
      self.each(m[1], () => {
        self.line(false)
        s.end_part()
      })
      s.end_member(MultiLineString)
    }
    "Polygon" => {
      self.each(m[1], () => self.line(true))
      s.end_part()
      s.end_member(Polygon)
    }
    "MultiPolygon" => {
      self.each(m[1], () => {
        self.p.array(() => self.line(true))
        s.end_part()
      })
      s.end_member(MultiPolygon)
    }
    _ => ()
  }
}

///|
/// Reads a list of arc indices as one line, as topojson-client's `line` (and `ring`)
/// stitch them: each arc after the first replaces the line's last point; a line of
/// one point repeats it, a ring is padded to four with its first.
fn Topo::line(self : Topo, ring : Bool) -> Unit {
  let p = self.p
  let s = self.shapes
  let first = s.points()
  if p.peek() != '['.to_int() {
    p.fail("expected arc indices")
    return
  }
  p.array(() => {
    p.peek() |> ignore
    let at = p.pos
    let v = self.number()
    let n = self.ends.length()
    let i = v.to_int()
    if p.error is None && (i.to_double() != v || i >= n || i < -n) {
      p.pos = at
      p.fail("invalid arc index")
      return
    }
    let a = if i < 0 { -1 - i } else { i }
    let (start, end) = (@geom.start_of(self.ends, a), self.ends[a])
    if s.points() > first {
      s.coords.unsafe_pop() |> ignore
      s.coords.unsafe_pop() |> ignore
    }
    if s.points() + end - start > self.max_points {
      p.fail("too many points")
      return
    }
    for k in 0..<(end - start) {
      let j = if i < 0 { end - 1 - k } else { start + k }
      s.point(self.coords[j * 2], self.coords[j * 2 + 1])
    }
  })
  let n = s.points() - first
  if n > 0 {
    let (x, y) = (s.coords[first * 2], s.coords[first * 2 + 1])
    for _ in n..<(if ring { 4 } else { 2 }) {
      s.point(x, y)
    }
  }
  s.end_ring()
}
