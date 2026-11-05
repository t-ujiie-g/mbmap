///|
/// Deepest nesting of arrays and objects in GeoJSON input; deeper input is
/// rejected instead of recursing without bound (AGENTS.md §8.2).
pub const MAX_GEOJSON_DEPTH : Int32 = 64

///|
/// Most distinct property keys in GeoJSON input: every key is a column as
/// long as the table, so input past it is rejected (AGENTS.md §8.2).
pub const MAX_GEOJSON_KEYS : Int32 = 4096

///|
/// Malformed GeoJSON: the byte offset where reading stopped and why.
pub(all) suberror GeoJSONError {
  Malformed(pos~ : Int32, String)
} derive(Debug)

///|
/// A one-line description, e.g. `malformed GeoJSON at 12: expected ':'`.
pub fn GeoJSONError::message(self : GeoJSONError) -> String {
  match self {
    Malformed(pos~, m) => "malformed GeoJSON at \{pos}: \{m}"
  }
}

///|
/// Reads GeoJSON from UTF-8 into a table, a row per feature (and per member of a
/// GeometryCollection, as geojson-vt does). `slow_number` parses the numbers the
/// fast path cannot, from offsets into `bytes`; NaN rejects them.
pub fn read_geojson(
  bytes : BytesView,
  slow_number~ : (Int32, Int32) -> Double = (s, e) => {
    @core.strconv_number(bytes[s:e])
  },
) -> @geom.Table raise GeoJSONError {
  read_points(bytes, slow_number, @geom.MAX_TABLE_POINTS)
}

///|
/// `read_geojson` rejecting input with more than `max_points` points. Not an
/// optional argument of it: a second one links its default `slow_number`.
fn read_points(
  bytes : BytesView,
  slow_number : (Int32, Int32) -> Double,
  max_points : Int32,
) -> @geom.Table raise GeoJSONError {
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
    max_cells: @geom.MAX_TABLE_CELLS,
  }
  p.feature_like()
  if p.error is None && p.peek() != -1 {
    p.fail("unexpected data after the GeoJSON value")
  }
  match p.error {
    Some((pos, m)) => raise Malformed(pos~, m)
    None => p.out.finish()
  }
}

///|
/// Reading state. Errors are sticky: the first is kept and the position
/// jumps to the end, so loops stop without raising on the hot path.
priv struct Parser {
  b : BytesView
  slow_number : (Int32, Int32) -> Double
  mut pos : Int32
  mut error : (Int32, String)?
  mut depth : Int32
  out : @geom.TableBuilder
  keys : Array[(Int32, Int32, String)]
  mut next_key : Int32
  max_points : Int32
  max_cells : Int32
}

///|
/// The text of an unescaped key, decoded once per distinct key: features
/// repeat the same keys.
fn Parser::key(
  self : Parser,
  start : Int32,
  end : Int32,
  escaped : Bool,
) -> String {
  if escaped {
    return self.text(start, end, escaped)
  }
  let n = end - start
  let count = self.keys.length()
  // Features tend to repeat their keys in order: try the one after the last
  // match first.
  for j in 0..<count {
    let index = (self.next_key + j) % count
    let k = self.keys[index]
    if k.1 - k.0 == n {
      let mut same = true
      for i in 0..<n {
        if self.b[k.0 + i] != self.b[start + i] {
          same = false
          break
        }
      }
      if same {
        self.next_key = index + 1
        return k.2
      }
    }
  }
  let text = self.text(start, end, false)
  if count < 256 {
    self.keys.push((start, end, text))
    self.next_key = count + 1
  }
  text
}

///|
/// A property value; objects and arrays become their JSON text without
/// insignificant whitespace.
fn Parser::prop(self : Parser) -> @geom.Prop {
  match self.peek() {
    '"' => {
      let (s, e, esc) = self.string_raw()
      Str(self.text(s, e, esc))
    }
    't' => if self.literal("true") { Bool(true) } else { Null }
    'f' => if self.literal("false") { Bool(false) } else { Null }
    'n' => {
      self.literal("null") |> ignore
      Null
    }
    '{' | '[' => {
      let start = self.pos
      self.skip()
      Str(self.compact(start, self.pos))
    }
    _ => Num(self.number())
  }
}

///|
/// A geometry read before its type is known: positions and the list ends at
/// each nesting level (`ends[0]` closes lists of positions); `levels` is how
/// deep positions sit (1 for a Point, 4 for a MultiPolygon).
priv struct GeomBuf {
  mut kind : @geom.GeomKind
  coords : Array[Double]
  ends : FixedArray[Array[Int32]]
  mut levels : Int32
  mut bad : Bool
}

///|
fn GeomBuf::new() -> GeomBuf {
  { kind: NoGeometry, coords: [], ends: [[], [], []], levels: 0, bad: false, }
}

///|
/// Reads a coordinates value at nesting `level` (1 at the top).
fn Parser::coordinates(self : Parser, g : GeomBuf, level : Int32) -> Unit {
  // Plain loops, no closures: this runs once per position.
  if self.peek() != '['.to_int() {
    self.skip()
    g.bad = true
    return
  }
  self.pos += 1
  if !self.enter() {
    return
  }
  let first = self.peek()
  if first == ']'.to_int() {
    // An empty list: nothing to close.
    self.pos += 1
    self.depth -= 1
    return
  }
  if first == '-'.to_int() || (first >= '0'.to_int() && first <= '9'.to_int()) {
    // A position: x, y and any further numbers, which are dropped.
    let mut n = 0
    while self.error is None {
      let v = self.number()
      if n < 2 {
        g.coords.push(v)
      }
      if n == 1 &&
        self.out.table.coords.length() + g.coords.length() > 2 * self.max_points {
        // A constant message: printing `max_points` would link integer formatting.
        self.fail("too many points")
      }
      n += 1
      if !self.next_or_close() {
        break
      }
    }
    if n < 2 {
      g.bad = true
      // Keep coords in pairs.
      if n == 1 {
        g.coords.unsafe_pop() |> ignore
      }
    }
    if g.levels != 0 && g.levels != level {
      g.bad = true
    }
    g.levels = level
    return
  }
  while self.error is None {
    self.coordinates(g, level + 1)
    if !self.next_or_close() {
      break
    }
  }
  // `levels - level - 1` lists sit between this one and the positions.
  let k = g.levels - level - 1
  if g.levels == 0 {
    ()
  } else if k >= 0 && k < 3 {
    let count = if k == 0 {
      g.coords.length() / 2
    } else {
      g.ends[k - 1].length()
    }
    g.ends[k].push(count)
  } else {
    g.bad = true
  }
}

///|
/// After an array element: true past a ',' (another element follows),
/// false past the closing ']' or on an error.
fn Parser::next_or_close(self : Parser) -> Bool {
  match self.peek() {
    ',' => {
      self.pos += 1
      true
    }
    ']' => {
      self.pos += 1
      self.depth -= 1
      false
    }
    _ => {
      self.fail("expected ',' or ']'")
      false
    }
  }
}

///|
fn kind_of(name : String) -> @geom.GeomKind {
  match name {
    "Point" => Point
    "MultiPoint" => MultiPoint
    "LineString" => LineString
    "MultiLineString" => MultiLineString
    "Polygon" => Polygon
    "MultiPolygon" => MultiPolygon
    _ => NoGeometry
  }
}

///|
/// Reads a geometry object into `out`, one buffer per geometry (members of
/// a GeometryCollection are flattened, nested ones too).
fn Parser::geometry(self : Parser, out : Array[GeomBuf]) -> Unit {
  if self.peek() == 'n'.to_int() {
    self.literal("null") |> ignore
    return
  }
  let g = GeomBuf::new()
  let mut collection = false
  self.object((s, e, esc) => {
    if !esc && self.matches(s, e, "type") {
      if self.peek() == '"'.to_int() {
        let (ts, te, tesc) = self.string_raw()
        let name = self.text(ts, te, tesc)
        g.kind = kind_of(name)
        collection = name == "GeometryCollection"
      } else {
        self.skip()
      }
    } else if !esc && self.matches(s, e, "coordinates") {
      self.coordinates(g, 1)
    } else if !esc && self.matches(s, e, "geometries") {
      self.array(() => self.geometry(out))
    } else {
      self.skip()
    }
  })
  if !collection {
    out.push(g)
  }
}

///|
/// Writes `g` to the builder as the geometry of the feature being built;
/// false if its coordinates do not fit its kind.
fn Parser::emit(self : Parser, g : GeomBuf) -> Bool {
  let o = self.out
  let levels = match g.kind {
    Point => 1
    MultiPoint | LineString => 2
    MultiLineString | Polygon => 3
    MultiPolygon => 4
    NoGeometry => return false
  }
  if g.bad || g.levels == 0 {
    return false
  }
  if g.levels != levels {
    return false
  }
  // Plain loops: this runs once per point.
  let coords = o.table.coords
  let base = coords.length() / 2
  for v in g.coords {
    coords.push(v)
  }
  let end_ring = (end : Int32) => o.end_ring_at(base + end)
  match g.kind {
    Point | MultiPoint | LineString => {
      end_ring(g.coords.length() / 2)
      o.end_part()
    }
    MultiLineString | Polygon => {
      for e in g.ends[0] {
        end_ring(e)
        if g.kind is MultiLineString {
          o.end_part()
        }
      }
      if g.kind is Polygon {
        o.end_part()
      }
    }
    _ =>
      for poly in 0..<g.ends[1].length() {
        for r in @geom.start_of(g.ends[1], poly)..<g.ends[1][poly] {
          end_ring(g.ends[0][r])
        }
        o.end_part()
      }
  }
  true
}

///|
/// Reads an object that is a FeatureCollection, a Feature or a geometry
/// (which one shows only once all its members are read) and adds its
/// features to the table.
fn Parser::feature_like(self : Parser) -> Unit {
  let geoms : Array[GeomBuf] = []
  let props : Array[(String, @geom.Prop)] = []
  let mut id : @geom.Prop? = None
  let mut is_feature = false
  let bare = GeomBuf::new()
  let mut is_bare = false
  let mut bare_collection = false
  self.object((s, e, esc) => {
    if esc {
      self.skip()
    } else if self.matches(s, e, "features") {
      self.array(() => self.feature_like())
    } else if self.matches(s, e, "geometry") {
      is_feature = true
      self.geometry(geoms)
    } else if self.matches(s, e, "properties") {
      if self.peek() == '{'.to_int() {
        self.object((ks, ke, kesc) => {
          props.push((self.key(ks, ke, kesc), self.prop()))
        })
      } else {
        self.skip()
      }
    } else if self.matches(s, e, "id") {
      id = Some(self.prop())
    } else if self.matches(s, e, "type") {
      if self.peek() == '"'.to_int() {
        let (ts, te, tesc) = self.string_raw()
        let name = self.text(ts, te, tesc)
        is_feature = is_feature || name == "Feature"
        bare.kind = kind_of(name)
        bare_collection = name == "GeometryCollection"
      } else {
        self.skip()
      }
    } else if self.matches(s, e, "coordinates") {
      is_bare = true
      self.coordinates(bare, 1)
    } else if self.matches(s, e, "geometries") {
      is_bare = true
      self.array(() => self.geometry(geoms))
    } else {
      self.skip()
    }
  })
  if self.error is Some(_) {
    return
  }
  if is_bare && !is_feature {
    if !bare_collection {
      geoms.push(bare)
    }
  } else if !is_feature {
    return
  }
  // An empty geometry list still makes one row without geometry.
  if geoms.is_empty() {
    geoms.push(GeomBuf::new())
  }
  for g in geoms {
    let kind = if self.emit(g) { g.kind } else { NoGeometry }
    if kind is NoGeometry {
      self.out.discard_feature()
    }
    for p in props {
      self.out.prop(p.0, p.1)
    }
    self.out.end_feature(kind, id~)
    self.check_properties()
    if self.error is Some(_) {
      return
    }
  }
}

///|
/// Fails past `MAX_GEOJSON_KEYS` keys or `max_cells` cells.
fn Parser::check_properties(self : Parser) -> Unit {
  if self.out.table.columns.length() > MAX_GEOJSON_KEYS {
    self.fail("more than \{MAX_GEOJSON_KEYS} property keys")
  } else if self.out.cells() > self.max_cells.to_int64() {
    self.fail("more than \{@geom.MAX_TABLE_CELLS} property cells")
  }
}
