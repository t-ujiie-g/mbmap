///|
/// Deepest nesting of arrays and objects in GeoJSON input; deeper input is
/// rejected instead of recursing without bound (AGENTS.md §8.2).
pub const MAX_GEOJSON_DEPTH : Int32 = 64

///|
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
/// Reads GeoJSON (a FeatureCollection, a Feature or a bare geometry) from
/// UTF-8 into a table with one row per feature; a GeometryCollection becomes
/// one row per member geometry with the feature's properties, as geojson-vt
/// flattens it. Coordinates beyond x and y are ignored; a geometry whose
/// coordinates do not fit its type is kept as `NoGeometry`. Raises once, at
/// the end, on malformed JSON.
pub fn read_geojson(bytes : BytesView) -> @geom.Table raise GeoJSONError {
  let p : Parser = {
    b: bytes,
    pos: 0,
    error: None,
    depth: 0,
    out: @geom.TableBuilder::new(),
    keys: [],
    next_key: 0,
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
  mut pos : Int32
  mut error : (Int32, String)?
  mut depth : Int32
  out : @geom.TableBuilder
  keys : Array[(Int32, Int32, String)]
  mut next_key : Int32
}

///|
fn Parser::fail(self : Parser, message : String) -> Unit {
  if self.error is None {
    self.error = Some((self.pos, message))
  }
  self.pos = self.b.length()
}

///|
/// The next non-space byte, or -1 at the end.
fn Parser::peek(self : Parser) -> Int32 {
  while self.pos < self.b.length() {
    match self.b[self.pos] {
      b' ' | b'\t' | b'\n' | b'\r' => self.pos += 1
      c => return c.to_int()
    }
  }
  -1
}

///|
fn Parser::expect(self : Parser, c : Char) -> Bool {
  if self.peek() == c.to_int() {
    self.pos += 1
    true
  } else {
    self.fail("expected '\{c}'")
    false
  }
}

///|
/// Enters an array or object; false (and an error) past `MAX_GEOJSON_DEPTH`.
fn Parser::enter(self : Parser) -> Bool {
  self.depth += 1
  if self.depth > MAX_GEOJSON_DEPTH {
    self.fail("nested deeper than \{MAX_GEOJSON_DEPTH}")
    return false
  }
  true
}

///|
/// Calls `on_member` for each key of the object at the position, with the
/// parser at the member's value; `on_member` must consume the value.
fn Parser::object(
  self : Parser,
  on_member : (Int32, Int32, Bool) -> Unit,
) -> Unit {
  if !self.expect('{') || !self.enter() {
    return
  }
  if self.peek() == '}'.to_int() {
    self.pos += 1
    self.depth -= 1
    return
  }
  while self.error is None {
    let (start, end, escaped) = self.string_raw()
    if !self.expect(':') {
      return
    }
    on_member(start, end, escaped)
    match self.peek() {
      ',' => self.pos += 1
      '}' => {
        self.pos += 1
        self.depth -= 1
        return
      }
      _ => self.fail("expected ',' or '}'")
    }
  }
}

///|
/// Calls `element` for each element of the array at the position; `element`
/// must consume it.
fn Parser::array(self : Parser, element : () -> Unit) -> Unit {
  if !self.expect('[') || !self.enter() {
    return
  }
  if self.peek() == ']'.to_int() {
    self.pos += 1
    self.depth -= 1
    return
  }
  while self.error is None {
    element()
    match self.peek() {
      ',' => self.pos += 1
      ']' => {
        self.pos += 1
        self.depth -= 1
        return
      }
      _ => self.fail("expected ',' or ']'")
    }
  }
}

///|
/// A string's content range (without quotes) and whether it has escapes.
fn Parser::string_raw(self : Parser) -> (Int32, Int32, Bool) {
  if !self.expect('"') {
    return (0, 0, false)
  }
  let start = self.pos
  let mut escaped = false
  while self.pos < self.b.length() {
    match self.b[self.pos] {
      b'"' => {
        self.pos += 1
        return (start, self.pos - 1, escaped)
      }
      b'\\' => {
        escaped = true
        self.pos += 2
      }
      c if c < b' ' => {
        self.fail("control character in string")
        return (0, 0, false)
      }
      _ => self.pos += 1
    }
  }
  self.fail("unterminated string")
  (0, 0, false)
}

///|
/// Whether the unescaped key `start..<end` is the ASCII `name`.
fn Parser::matches(
  self : Parser,
  start : Int32,
  end : Int32,
  name : String,
) -> Bool {
  if end - start != name.length() {
    return false
  }
  for i in 0..<name.length() {
    if self.b[start + i].to_int() != name.code_unit_at(i).to_int() {
      return false
    }
  }
  true
}

///|
fn hex(c : Byte) -> Int32 {
  match c {
    b'0'..<=b'9' => c.to_int() - '0'.to_int()
    b'a'..<=b'f' => c.to_int() - 'a'.to_int() + 10
    b'A'..<=b'F' => c.to_int() - 'A'.to_int() + 10
    _ => -1
  }
}

///|
/// The string `start..<end` as text, with escapes resolved and invalid UTF-8
/// replaced.
fn Parser::text(
  self : Parser,
  start : Int32,
  end : Int32,
  escaped : Bool,
) -> String {
  if !escaped {
    return @utf8.decode_lossy(self.b[start:end])
  }
  let sb = StringBuilder()
  let mut i = start
  let mut run = start
  while i < end {
    if self.b[i] != b'\\' {
      i += 1
      continue
    }
    sb.write_string(@utf8.decode_lossy(self.b[run:i]))
    let c = if i + 1 < end { self.b[i + 1] } else { b' ' }
    i += 2
    match c {
      b'"' => sb.write_char('"')
      b'\\' => sb.write_char('\\')
      b'/' => sb.write_char('/')
      b'b' => sb.write_char('\b')
      b'f' => sb.write_char('\u{0C}')
      b'n' => sb.write_char('\n')
      b'r' => sb.write_char('\r')
      b't' => sb.write_char('\t')
      b'u' if i + 4 <= end => {
        let mut v = 0
        for k in 0..<4 {
          let h = hex(self.b[i + k])
          v = if h < 0 || v < 0 { -1 } else { v * 16 + h }
        }
        i += 4
        // Surrogates go out as UTF-16 code units, which String holds.
        sb.write_char(Int32::unsafe_to_char(if v < 0 { 0xFFFD } else { v }))
      }
      _ => sb.write_char('\u{FFFD}')
    }
    run = i
  }
  sb.write_string(@utf8.decode_lossy(self.b[run:end]))
  sb.to_string()
}

///|
/// Powers of ten that doubles hold exactly.
let exact_powers : FixedArray[Double] = [
  1.0e0, 1.0e1, 1.0e2, 1.0e3, 1.0e4, 1.0e5, 1.0e6, 1.0e7, 1.0e8, 1.0e9, 1.0e10, 1.0e11,
  1.0e12, 1.0e13, 1.0e14, 1.0e15, 1.0e16, 1.0e17, 1.0e18, 1.0e19, 1.0e20, 1.0e21,
  1.0e22,
]

///|
/// A JSON number. With at most 15 significant digits and a decimal exponent
/// within ±22, one exact multiplication or division gives the correctly
/// rounded double (Clinger's fast path); anything else goes to the core
/// parser.
fn Parser::number(self : Parser) -> Double {
  self.peek() |> ignore
  let b = self.b
  let start = self.pos
  let mut i = start
  let negative = i < b.length() && b[i] == b'-'
  if negative {
    i += 1
  }
  let mut mantissa = 0L
  let mut digits = 0
  let mut exponent = 0
  let mut any = false
  while i < b.length() && b[i] >= b'0' && b[i] <= b'9' {
    if digits < 18 {
      mantissa = mantissa * 10L + (b[i].to_int() - '0'.to_int()).to_int64()
      if mantissa > 0L {
        digits += 1
      }
    } else {
      exponent += 1
      digits += 1
    }
    any = true
    i += 1
  }
  // JSON wants digits on both sides of the point.
  let int_part = any
  if i < b.length() && b[i] == b'.' {
    i += 1
    any = false
    while i < b.length() && b[i] >= b'0' && b[i] <= b'9' {
      if digits < 18 {
        mantissa = mantissa * 10L + (b[i].to_int() - '0'.to_int()).to_int64()
        if mantissa > 0L {
          digits += 1
        }
        exponent -= 1
      } else {
        digits += 1
      }
      any = true
      i += 1
    }
  }
  if i < b.length() && (b[i] == b'e' || b[i] == b'E') {
    i += 1
    let mut sign = 1
    if i < b.length() && (b[i] == b'+' || b[i] == b'-') {
      sign = if b[i] == b'-' { -1 } else { 1 }
      i += 1
    }
    let mut e = 0
    let mut any_e = false
    while i < b.length() && b[i] >= b'0' && b[i] <= b'9' {
      e = @cmp.minimum(e * 10 + (b[i].to_int() - '0'.to_int()), 100000)
      any_e = true
      i += 1
    }
    if !any_e {
      any = false
    }
    exponent += sign * e
  }
  if !any || !int_part {
    self.fail("invalid number")
    return 0.0
  }
  self.pos = i
  if digits <= 15 && exponent.abs() <= 22 {
    let m = mantissa.to_double()
    let v = if exponent < 0 {
      m / exact_powers[-exponent]
    } else {
      m * exact_powers[exponent]
    }
    return if negative { -v } else { v }
  }
  @string.parse_double(@utf8.decode_lossy(b[start:i])) catch {
    _ => {
      self.fail("invalid number")
      0.0
    }
  }
}

///|
/// Skips a literal (`true`, `false` or `null`); false if it is not `word`.
fn Parser::literal(self : Parser, word : String) -> Bool {
  if self.pos + word.length() > self.b.length() ||
    !self.matches(self.pos, self.pos + word.length(), word) {
    self.fail("invalid literal")
    return false
  }
  self.pos += word.length()
  true
}

///|
/// Skips any JSON value.
fn Parser::skip(self : Parser) -> Unit {
  match self.peek() {
    '{' | '[' => self.skip_nested()
    '"' => self.string_raw() |> ignore
    't' => self.literal("true") |> ignore
    'f' => self.literal("false") |> ignore
    'n' => self.literal("null") |> ignore
    _ => self.number() |> ignore
  }
}

///|
/// Skips an object or array by matching brackets, honoring strings and the
/// depth limit. It does not check the commas and colons inside: values the
/// reader ignores need not be valid JSON, only bounded.
fn Parser::skip_nested(self : Parser) -> Unit {
  let b = self.b
  let mut nested = 0
  while self.pos < b.length() {
    match b[self.pos] {
      b'{' | b'[' => {
        nested += 1
        if self.depth + nested > MAX_GEOJSON_DEPTH {
          self.fail("nested deeper than \{MAX_GEOJSON_DEPTH}")
          return
        }
      }
      b'}' | b']' => {
        nested -= 1
        if nested == 0 {
          self.pos += 1
          return
        }
      }
      b'"' => {
        self.string_raw() |> ignore
        continue
      }
      _ => ()
    }
    self.pos += 1
  }
  self.fail("unterminated array or object")
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
/// The JSON text `start..<end` without whitespace outside strings.
fn Parser::compact(self : Parser, start : Int32, end : Int32) -> String {
  let out : Array[Byte] = []
  let mut in_string = false
  let mut i = start
  while i < end {
    let c = self.b[i]
    if in_string {
      out.push(c)
      if c == b'\\' && i + 1 < end {
        out.push(self.b[i + 1])
        i += 1
      } else if c == b'"' {
        in_string = false
      }
    } else if !(c == b' ' || c == b'\t' || c == b'\n' || c == b'\r') {
      out.push(c)
      in_string = c == b'"'
    }
    i += 1
  }
  @utf8.decode_lossy(Bytes::from_array(out))
}

///|
/// A geometry read before its type is known: positions, and the ends of
/// the lists at each nesting level above them (`ends[0]` closes lists of
/// positions). `levels` is how deep positions sit: 1 for a Point's single
/// position, 4 for a MultiPolygon.
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
  let start = (ends : Array[Int32], i : Int32) => {
    if i == 0 {
      0
    } else {
      ends[i - 1]
    }
  }
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
        for r in start(g.ends[1], poly)..<g.ends[1][poly] {
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
  }
}
