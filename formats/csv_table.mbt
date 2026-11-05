// Ported from papaparse 5.7.0: MIT License, Copyright (c) 2015 Matthew Holt. See NOTICE.

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
  srids : Array[Int32]?,
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
    shapes.emit(out, props, srids, max_cells~)
    if out.cells() > max_cells.to_int64() {
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
