///|
/// Most fields in a CSV row (AGENTS.md §8.2).
pub const MAX_CSV_COLUMNS : Int32 = 4096

///|
/// Longest CSV field in bytes.
pub const MAX_CSV_FIELD_BYTES : Int32 = 16 * 1024 * 1024

///|
/// Most property cells (rows times columns) a CSV input may make.
pub const MAX_CSV_CELLS : Int32 = 32_000_000

///|
/// How `read_csv` reads its input. `delimiter`: a byte, or -1 to guess it as
/// papaparse does; `header`: the first row names the columns (else they are named
/// "0", "1", ...); `dynamic_typing`: fields become numbers, booleans and nulls as
/// papaparse's `dynamicTyping` makes them (else they stay strings); `latitude` and
/// `longitude`, or `geometry` (WKT, EWKT or hexadecimal WKB), name the columns
/// the geometry comes from, found by name when None.
pub(all) struct CsvOptions {
  delimiter : Int32
  header : Bool
  dynamic_typing : Bool
  latitude : String?
  longitude : String?
  geometry : String?
}

///|
pub fn CsvOptions::new(
  delimiter~ : Int32 = -1,
  header~ : Bool = true,
  dynamic_typing~ : Bool = true,
  latitude? : String,
  longitude? : String,
  geometry? : String,
) -> CsvOptions {
  { delimiter, header, dynamic_typing, latitude, longitude, geometry, }
}

///|
/// Column names that hold latitudes, longitudes and geometries, in order of
/// preference, compared without ASCII case.
let latitude_names : FixedArray[String] = ["lat", "latitude", "y", "緯度"]

///|
let longitude_names : FixedArray[String] = [
  "lon", "lng", "long", "longitude", "x", "経度",
]

///|
let geometry_names : FixedArray[String] = [
  "wkt", "geometry", "the_geom", "geom",
]

///|
/// Delimiters tried when guessing, papaparse's.
let guessed_delimiters : FixedArray[Byte] = [
  b',', b'\t', b'|', b';', b'\x1e', b'\x1f',
]

///|
/// Reads CSV (RFC 4180, with CRLF, LF or CR row ends) into a table, a row per CSV
/// row and per member of its geometry (npm/README.md `mbmap/data` has the rules).
/// `slow_number` parses the numbers the fast path cannot, from offsets into `bytes`.
pub fn read_csv(
  bytes : BytesView,
  options : CsvOptions,
  slow_number~ : (Int32, Int32) -> Double = (s, e) => {
    @core.strconv_number(bytes[s:e])
  },
) -> @geom.Table raise ReadError {
  csv_table(bytes, options, slow_number, MAX_POINTS, MAX_CSV_CELLS)
}

///|
/// A CSV reader over `b`; the fields of the row last read are `starts`, `ends`
/// (content ranges, quotes excluded) and `escaped` (holds `""`). Errors are sticky.
priv struct Csv {
  b : BytesView
  mut pos : Int32
  mut delimiter : Byte
  mut error : (Int32, String)?
  starts : Array[Int32]
  ends : Array[Int32]
  escaped : Array[Bool]
}

///|
fn Csv::fail(self : Csv, at : Int32, message : String) -> Unit {
  if self.error is None {
    self.error = Some((at, message))
  }
  self.pos = self.b.length()
}

///|
/// Takes a row end (CRLF, LF or CR) at the position; false if there is none.
fn Csv::row_end(self : Csv) -> Bool {
  let b = self.b
  if self.pos < b.length() && b[self.pos] == b'\r' {
    self.pos += if self.pos + 1 < b.length() && b[self.pos + 1] == b'\n' {
      2
    } else {
      1
    }
    true
  } else if self.pos < b.length() && b[self.pos] == b'\n' {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
fn Csv::field(self : Csv, start : Int32, end : Int32, escaped : Bool) -> Unit {
  if end - start > MAX_CSV_FIELD_BYTES {
    self.fail(start, "a field longer than \{MAX_CSV_FIELD_BYTES} bytes")
  } else if self.starts.length() >= MAX_CSV_COLUMNS {
    self.fail(start, "more than \{MAX_CSV_COLUMNS} fields in a row")
  }
  self.starts.push(start)
  self.ends.push(end)
  self.escaped.push(escaped)
}

///|
/// Reads the next row's fields; false at the end of the input or on an error.
fn Csv::row(self : Csv) -> Bool {
  self.starts.clear()
  self.ends.clear()
  self.escaped.clear()
  let b = self.b
  let n = b.length()
  if self.pos >= n || self.error is Some(_) {
    return false
  }
  while self.error is None {
    if self.pos < n && b[self.pos] == b'"' {
      let open = self.pos
      let start = self.pos + 1
      let mut i = start
      let mut escaped = false
      let mut closed = -1
      while i < n {
        if b[i] == b'"' {
          if i + 1 < n && b[i + 1] == b'"' {
            escaped = true
            i += 2
            continue
          }
          closed = i
          break
        }
        i += 1
      }
      if closed < 0 {
        self.fail(open, "unterminated quoted field")
        return false
      }
      self.field(start, closed, escaped)
      // Spaces may stand between the closing quote and a delimiter or row end, as
      // papaparse allows.
      self.pos = closed + 1
      while self.pos < n && b[self.pos] == b' ' {
        self.pos += 1
      }
      if self.pos == closed + 1 && self.pos == n {
        return true
      }
      if self.pos < n && b[self.pos] == self.delimiter {
        self.pos += 1
        continue
      }
      if self.row_end() {
        return true
      }
      self.fail(closed, "unexpected text after a quoted field")
      return false
    }
    let start = self.pos
    while self.pos < n {
      let c = b[self.pos]
      if c == self.delimiter || c == b'\n' || c == b'\r' {
        break
      }
      self.pos += 1
    }
    self.field(start, self.pos, false)
    if self.pos < n && b[self.pos] == self.delimiter {
      self.pos += 1
      continue
    }
    self.row_end() |> ignore
    return true
  }
  false
}

///|
/// Whether the row last read is empty (one empty field), which is skipped.
fn Csv::empty_row(self : Csv) -> Bool {
  self.starts.length() == 1 && self.starts[0] == self.ends[0]
}

///|
/// The delimiter papaparse's `guessDelimiter` picks from the first ten rows at
/// `start`: the one whose rows' field counts vary least, more fields breaking
/// ties, if its rows average two or more; ',' if none does.
fn Csv::guess_delimiter(self : Csv, start : Int32) -> Byte {
  let mut best = b','
  let mut best_delta = -1
  let mut best_fields = 0.0
  for d in guessed_delimiters {
    self.delimiter = d
    self.pos = start
    self.error = None
    let mut rows = 0
    let mut empty = 0
    let mut fields = 0
    let mut delta = 0
    let mut previous = -1
    while rows < 10 && self.row() {
      rows += 1
      if self.empty_row() {
        empty += 1
        continue
      }
      let count = self.starts.length()
      fields += count
      if previous >= 0 {
        delta += (count - previous).abs()
      }
      previous = count
    }
    let average = if rows > empty {
      fields.to_double() / (rows - empty).to_double()
    } else {
      0.0
    }
    if average > 1.99 &&
      (
        best_delta < 0 ||
        delta < best_delta ||
        (delta == best_delta && average > best_fields)
      ) {
      best = d
      best_delta = delta
      best_fields = average
    }
  }
  self.error = None
  best
}

///|
/// Field `i` of the row last read as text, `""` unescaped and invalid UTF-8
/// replaced.
fn Csv::text(self : Csv, i : Int32) -> String {
  let (s, e) = (self.starts[i], self.ends[i])
  if !self.escaped[i] {
    return @core.utf8_lossy(self.b[s:e])
  }
  let out : Array[Byte] = Array(capacity=e - s)
  let mut j = s
  while j < e {
    out.push(self.b[j])
    j += if self.b[j] == b'"' { 2 } else { 1 }
  }
  @core.utf8_lossy(Bytes::from_array(out))
}

///|
/// Whether field `i` of the row last read is the ASCII `word`.
fn Csv::field_is(self : Csv, i : Int32, word : String) -> Bool {
  let (s, e) = (self.starts[i], self.ends[i])
  if e - s != word.length() || self.escaped[i] {
    return false
  }
  for k in 0..<word.length() {
    if self.b[s + k].to_int() != word.code_unit_at(k).to_int() {
      return false
    }
  }
  true
}

///|
/// `name` with ASCII letters in lower case.
fn ascii_lower(name : String) -> String {
  let sb = StringBuilder()
  for c in name {
    sb.write_char(
      if c >= 'A' && c <= 'Z' {
        (c.to_int() + 32).unsafe_to_char()
      } else {
        c
      },
    )
  }
  sb.to_string()
}

///|
/// The column with the first of `names` (compared without ASCII case), or -1.
fn find_column(columns : Array[String], names : FixedArray[String]) -> Int32 {
  for name in names {
    for i, c in columns {
      if ascii_lower(c) == name {
        return i
      }
    }
  }
  -1
}

///|
/// The column named `name` exactly; -1 and an error if there is none.
fn Csv::named_column(
  self : Csv,
  columns : Array[String],
  name : String,
) -> Int32 {
  for i, c in columns {
    if c == name {
      return i
    }
  }
  self.fail(0, "no column named \"\{name}\"")
  -1
}

///|
/// Header names made unique as papaparse makes them: a repeated name gets `_1`,
/// `_2`, ... (the first suffix no column has yet).
fn unique_names(names : Array[String]) -> Array[String] {
  let counts : Map[String, Int32] = Map([])
  let used : Set[String] = Set::from_array(names)
  names.map(name => {
    match counts.get(name) {
      None => {
        counts[name] = 1
        name
      }
      Some(count) => {
        let mut suffix = count
        let mut renamed = "\{name}_\{suffix}"
        while used.contains(renamed) {
          suffix += 1
          renamed = "\{name}_\{suffix}"
        }
        used.add(renamed)
        counts[name] = count + 1
        renamed
      }
    }
  })
}

///|
/// The columns a row's geometry comes from: `geometry` (WKT or WKB), else
/// `latitude` and `longitude`; -1 for none.
priv struct GeometryColumns {
  geometry : Int32
  latitude : Int32
  longitude : Int32
}

///|
/// `read_csv` taking at most `max_points` points and `max_cells` cells.
fn csv_table(
  bytes : BytesView,
  options : CsvOptions,
  slow : (Int32, Int32) -> Double,
  max_points : Int32,
  max_cells : Int32,
) -> @geom.Table raise ReadError {
  let bom = bytes.length() >= 3 &&
    bytes[0] == b'\xef' &&
    bytes[1] == b'\xbb' &&
    bytes[2] == b'\xbf'
  let start = if bom { 3 } else { 0 }
  let csv : Csv = {
    b: bytes,
    pos: start,
    delimiter: b',',
    error: None,
    starts: [],
    ends: [],
    escaped: [],
  }
  let d = options.delimiter
  if d == -1 {
    csv.delimiter = csv.guess_delimiter(start)
  } else if d < 0 ||
    d > 127 ||
    d == '"'.to_int() ||
    d == '\n'.to_int() ||
    d == '\r'.to_int() {
    raise Invalid(format="CSV", pos=0, "invalid delimiter")
  } else {
    csv.delimiter = d.to_byte()
  }
  csv.pos = start
  let columns : Array[String] = []
  if options.header {
    while csv.row() {
      if !csv.empty_row() {
        columns.append(
          unique_names(Array::makei(csv.starts.length(), i => csv.text(i))),
        )
        break
      }
    }
  }
  let data = csv.pos
  let wkt = Wkt::new(bytes, slow, max_points)
  let wkb = Wkb::new(bytes, max_points)
  let geometry = csv.geometry_columns(columns, options, wkt, wkb)
  if csv.error is None {
    csv.pos = data
  }
  let out = @geom.TableBuilder::new()
  let props : Array[(String, @geom.Prop)] = []
  let none = Shapes::new()
  let mut used = 0
  while csv.row() {
    if csv.empty_row() {
      continue
    }
    props.clear()
    let count = if options.header {
      @cmp.minimum(csv.starts.length(), columns.length())
    } else {
      csv.starts.length()
    }
    for i in 0..<count {
      if i != geometry.geometry {
        let name = if options.header { columns[i] } else { i.to_string() }
        props.push((name, csv.prop(i, options.dynamic_typing, slow)))
      }
    }
    wkt.used = used
    wkb.used = used
    let shapes = csv.shapes(geometry, wkt, wkb, slow).unwrap_or(none)
    if used + shapes.points() > max_points {
      csv.fail(csv.pos, "too many points")
      break
    }
    used += shapes.points()
    shapes.emit(out, props)
    let t = out.table
    if t.length().to_double() * t.columns.length().to_double() >
      max_cells.to_double() {
      csv.fail(csv.pos, "too many property cells")
    }
  }
  match csv.error {
    Some((pos, m)) => raise Invalid(format="CSV", pos~, m)
    None => out.finish()
  }
}

///|
/// The columns the geometry comes from: those `options` name, else a column
/// named as a geometry whose first value is one, else columns named as a
/// latitude and a longitude. Reads rows on from the position.
fn Csv::geometry_columns(
  self : Csv,
  columns : Array[String],
  options : CsvOptions,
  wkt : Wkt,
  wkb : Wkb,
) -> GeometryColumns {
  let none = { geometry: -1, latitude: -1, longitude: -1, }
  match (options.geometry, options.latitude, options.longitude) {
    (Some(g), _, _) =>
      return { ..none, geometry: self.named_column(columns, g), }
    (None, Some(lat), Some(lon)) =>
      return {
        ..none,
        latitude: self.named_column(columns, lat),
        longitude: self.named_column(columns, lon),
      }
    (None, Some(_), None) | (None, None, Some(_)) => {
      self.fail(0, "latitude and longitude go together")
      return none
    }
    (None, None, None) => ()
  }
  let g = find_column(columns, geometry_names)
  if g >= 0 {
    while self.row() {
      if g < self.starts.length() && self.starts[g] < self.ends[g] {
        if self.geometry_cell(g, wkt, wkb) is Some(_) {
          return { ..none, geometry: g, }
        }
        break
      }
    }
  }
  let latitude = find_column(columns, latitude_names)
  let longitude = find_column(columns, longitude_names)
  if latitude >= 0 && longitude >= 0 {
    { ..none, latitude, longitude, }
  } else {
    none
  }
}

///|
/// Field `i` read as WKT, EWKT or hexadecimal WKB (by its first character),
/// into `wkt.shapes` or `wkb.shapes`; None if it is none of them.
fn Csv::geometry_cell(self : Csv, i : Int32, wkt : Wkt, wkb : Wkb) -> Shapes? {
  let (s, e) = (self.starts[i], self.ends[i])
  let mut first = s
  while first < e && space_at(self.b, first, e) == 1 {
    first += 1
  }
  if first == e || self.escaped[i] {
    return None
  }
  match self.b[first] {
    b'0'..<=b'9' | b'a'..<=b'f' | b'A'..<=b'F' =>
      match unhex(self.b, s, e) {
        Some(bytes) if wkb.cell(bytes[:]) => Some(wkb.shapes)
        _ => None
      }
    _ => if wkt.cell(s, e) { Some(wkt.shapes) } else { None }
  }
}

///|
/// The geometry of the row last read, or None.
fn Csv::shapes(
  self : Csv,
  columns : GeometryColumns,
  wkt : Wkt,
  wkb : Wkb,
  slow : (Int32, Int32) -> Double,
) -> Shapes? {
  let n = self.starts.length()
  let g = columns.geometry
  if g >= 0 {
    return if g < n { self.geometry_cell(g, wkt, wkb) } else { None }
  }
  let (lat, lon) = (columns.latitude, columns.longitude)
  if lat < 0 ||
    lat >= n ||
    lon < 0 ||
    lon >= n ||
    self.escaped[lat] ||
    self.escaped[lon] {
    return None
  }
  let y = typed_number(self.b, self.starts[lat], self.ends[lat], slow)
  let x = typed_number(self.b, self.starts[lon], self.ends[lon], slow)
  guard x is Some(x) && y is Some(y) else { return None }
  let s = wkt.shapes
  s.clear()
  s.point(x, y)
  s.end_ring()
  s.end_part()
  s.end_member(Point)
  Some(s)
}

///|
/// Field `i` of the row last read as a property value: with `typed`, "true" and
/// "TRUE", "false" and "FALSE" as booleans, numbers as `typed_number` reads them
/// and an empty field as null, as papaparse's `dynamicTyping`; else its text.
fn Csv::prop(
  self : Csv,
  i : Int32,
  typed : Bool,
  slow : (Int32, Int32) -> Double,
) -> @geom.Prop {
  if typed {
    let (s, e) = (self.starts[i], self.ends[i])
    if s == e {
      return Null
    }
    if self.field_is(i, "true") || self.field_is(i, "TRUE") {
      return Bool(true)
    }
    if self.field_is(i, "false") || self.field_is(i, "FALSE") {
      return Bool(false)
    }
    if !self.escaped[i] && typed_number(self.b, s, e, slow) is Some(v) {
      return Num(v)
    }
  }
  Str(self.text(i))
}
