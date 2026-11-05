///|
/// Where `write_csv` puts each row's geometry: `Wkt(name)` a column of WKT as betterknown 1.2.0's
/// `geoJSONToWkt` writes it, `LonLat(longitude, latitude)` two columns of a point's coordinates,
/// `Omitted` none. A column of the same name as a property takes that property's place.
pub(all) enum CsvGeometry {
  Wkt(String)
  LonLat(String, String)
  Omitted
}

///|
/// The rows of `table` as papaparse 5.7.0's `unparse` writes objects of their properties and
/// geometry columns (`fields` the table's columns, then the geometry's): `delimiter` between
/// values, CRLF between lines, values quoted where they hold a quote, a delimiter, CR, LF or a BOM
/// or start or end with a space. `number_text` is the host's `String(x)`. Fails for `LonLat` and a
/// row whose geometry is not a point.
pub fn write_csv(
  table : @geom.Table,
  delimiter~ : Char = ',',
  header~ : Bool = true,
  geometry~ : CsvGeometry,
  number_text~ : (Double) -> String,
) -> String raise ReadError {
  let columns = table.columns
  let names = []
  // Each field's geometry value: -1 none, 0 WKT, 1 x, 2 y.
  let slots = []
  for c in columns {
    names.push(c.name)
    slots.push(-1)
  }
  let extra = match geometry {
    Wkt(w) => [w]
    LonLat(lon, lat) => [lon, lat]
    Omitted => []
  }
  for k, name in extra {
    let slot = if extra.length() == 1 { 0 } else { k + 1 }
    match names.search(name) {
      Some(i) => slots[i] = slot
      None => {
        names.push(name)
        slots.push(slot)
      }
    }
  }
  let sb = StringBuilder()
  let d = delimiter.to_int()
  if header && names.length() > 0 {
    for i in 0..<names.length() {
      if i > 0 {
        sb.write_char(delimiter)
      }
      csv_cell(sb, names[i], d)
    }
    // papaparse writes no rows as one empty row.
    sb.write_string("\r\n")
  }
  let values : Array[@geom.Prop?] = Array::make(names.length(), None)
  for row in 0..<table.length() {
    let kind = table.kinds[row]
    if geometry is LonLat(_) && !(kind is (Point | NoGeometry)) {
      raise Invalid(
        format="CSV",
        pos=row,
        "a row is not a point: write the geometry as WKT",
      )
    }
    let mut empty = true
    for i in 0..<names.length() {
      let v = if slots[i] == 0 {
        Some(
          match wkt_of(table, row, number_text) {
            Some(w) => @geom.Str(w)
            None => Null
          },
        )
      } else if slots[i] > 0 {
        Some(
          if kind is Point {
            let p = table.points(table.rings(table.parts(row).0).0).0
            @geom.Num(table.coords[p * 2 + slots[i] - 1])
          } else {
            Null
          },
        )
      } else if i < columns.length() {
        columns[i].values[row]
      } else {
        None
      }
      values[i] = v
      if v is Some(_) {
        empty = false
      }
    }
    // papaparse writes a row of no values (no key at all) without delimiters.
    for i in 0..<names.length() {
      if i > 0 && !empty {
        sb.write_char(delimiter)
      }
      match values[i] {
        Some(Str(s)) => csv_cell(sb, s, d)
        Some(Num(x)) => sb.write_string(number_text(x))
        Some(Bool(b)) => sb.write_string(if b { "true" } else { "false" })
        _ => ()
      }
    }
    if row < table.length() - 1 {
      sb.write_string("\r\n")
    }
  }
  sb.to_string()
}

///|
/// `s` as papaparse's `safe` writes it, `d` the delimiter's code.
fn csv_cell(sb : StringBuilder, s : String, d : Int32) -> Unit {
  let n = s.length()
  let mut quote = n > 0 && (s[0] == ' ' || s[n - 1] == ' ')
  for i in 0..<n {
    let c = s[i].to_int()
    if c == '"' || c == '\r' || c == '\n' || c == 0xfeff || c == d {
      quote = true
    }
  }
  if !quote {
    sb.write_string(s)
    return
  }
  sb.write_char('"')
  for i in 0..<n {
    if s[i] == 34 {
      sb.write_char('"')
    }
    sb.write_char(s[i].to_int().unsafe_to_char())
  }
  sb.write_char('"')
}

///|
/// The geometry of row `row` in WKT as betterknown 1.2.0's `geoJSONToWkt` writes the GeoJSON
/// `toGeoJSON` gives (`POINT (x y)`, positions joined by commas without spaces); None without one.
pub fn wkt_of(
  table : @geom.Table,
  row : Int32,
  number_text : (Double) -> String,
) -> String? {
  let sb = StringBuilder()
  let ring = (r : Int32) => {
    let (start, end) = table.points(r)
    for i in start..<end {
      if i > start {
        sb.write_char(',')
      }
      sb.write_string(number_text(table.coords[i * 2]))
      sb.write_char(' ')
      sb.write_string(number_text(table.coords[i * 2 + 1]))
    }
  }
  // The rings of part `p`, each in parentheses.
  let rings = (p : Int32) => {
    let (start, end) = table.rings(p)
    for r in start..<end {
      if r > start {
        sb.write_char(',')
      }
      sb.write_char('(')
      ring(r)
      sb.write_char(')')
    }
  }
  let (first, last) = table.parts(row)
  let name = match table.kinds[row] {
    NoGeometry => return None
    Point => "POINT"
    MultiPoint => "MULTIPOINT"
    LineString => "LINESTRING"
    MultiLineString => "MULTILINESTRING"
    Polygon => "POLYGON"
    MultiPolygon => "MULTIPOLYGON"
  }
  sb.write_string(name)
  sb.write_string(" (")
  match table.kinds[row] {
    Point | MultiPoint | LineString => ring(table.rings(first).0)
    Polygon => rings(first)
    _ =>
      for p in first..<last {
        if p > first {
          sb.write_char(',')
        }
        if table.kinds[row] is MultiPolygon {
          sb.write_char('(')
          rings(p)
          sb.write_char(')')
        } else {
          rings(p)
        }
      }
  }
  sb.write_char(')')
  Some(sb.to_string())
}
