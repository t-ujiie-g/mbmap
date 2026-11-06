// Ported from @placemarkio/tokml 0.4.0: MIT License, Copyright (c) 2022 Placemark, and the
// escaping of xast-util-to-xml 4.0.0: MIT License, Copyright (c) Titus Wormer. See NOTICE.

///|
/// The rows of `table` as @placemarkio/tokml 0.4.0's `toKML` writes the FeatureCollection
/// `toGeoJSON` gives them, text escaped as xast-util-to-xml does. `number_text` is the host's
/// `String(x)`.
pub fn write_kml(
  table : @geom.Table,
  number_text~ : (Double) -> String,
) -> String {
  let sb = StringBuilder()
  sb.write_string("<kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document>")
  for row in 0..<table.length() {
    sb.write_string("\n<Placemark")
    match table.ids[row] {
      Some(Str(s)) => attribute(sb, "id", s)
      Some(Num(x)) if !x.is_nan() => attribute(sb, "id", number_text(x))
      _ => ()
    }
    sb.write_string(">\n")
    let value = (key : String) => {
      match table.column(key) {
        Some(c) => c.values[row]
        None => None
      }
    }
    if value("name") is Some(v) && truthy(v) {
      element(sb, "name", plain(v, number_text))
    }
    if value("description") is Some(v) && truthy(v) {
      element(sb, "description", plain(v, number_text))
    }
    if value("visibility") is Some(v) {
      element(sb, "visibility", if truthy(v) { "1" } else { "0" })
    }
    sb.write_string("<ExtendedData>")
    for c in table.columns {
      if c.name is ("name" | "description" | "visibility") {
        continue
      }
      guard c.values[row] is Some(v) else { continue }
      sb.write_string("\n  <Data")
      attribute(sb, "name", c.name)
      sb.write_string(">")
      element(
        sb,
        "value",
        match v {
          Str(s) => s
          Num(x) if x.is_nan() || x.is_inf() => "null"
          Num(x) => number_text(x)
          Bool(b) => if b { "true" } else { "false" }
          Null => "null"
        },
      )
      sb.write_string("</Data>")
    }
    sb.write_string("</ExtendedData>\n  ")
    placemark_geometry(sb, table, row, number_text)
    sb.write_string("</Placemark>")
  }
  sb.write_string("</Document></kml>")
  sb.to_string()
}

///|
/// Whether `v` is truthy in JavaScript.
fn truthy(v : @geom.Prop) -> Bool {
  match v {
    Str(s) => s != ""
    Num(x) => x != 0 && !x.is_nan()
    Bool(b) => b
    Null => false
  }
}

///|
/// tokml's `valueToString` of a value it writes (never null: falsy values are left out).
fn plain(v : @geom.Prop, number_text : (Double) -> String) -> String {
  match v {
    Str(s) => s
    Num(x) => number_text(x)
    Bool(b) => if b { "true" } else { "false" }
    Null => "null"
  }
}

///|
/// Whether xast-util-to-xml's `clean` drops `c` (C0 controls but tab, LF and CR).
fn noncharacter(c : Char) -> Bool {
  let n = c.to_int()
  n <= 8 || n == 0x0b || n == 0x0c || (n >= 0x0e && n <= 0x1f)
}

///|
/// `s` without noncharacters, `&`, `<` (and `"` in attributes) as hexadecimal references.
fn escaped(sb : StringBuilder, s : String, quote : Bool) -> Unit {
  for c in s {
    match c {
      '&' => sb.write_string("&#x26;")
      '<' => sb.write_string("&#x3C;")
      '"' if quote => sb.write_string("&#x22;")
      _ if noncharacter(c) => ()
      _ => sb.write_char(c)
    }
  }
}

///|
fn element(sb : StringBuilder, name : String, text : String) -> Unit {
  sb.write_string("<\{name}>")
  escaped(sb, text, false)
  sb.write_string("</\{name}>")
}

///|
fn attribute(sb : StringBuilder, name : String, value : String) -> Unit {
  sb.write_string(" \{name}=\"")
  escaped(sb, value, true)
  sb.write_char('"')
}

///|
/// The points of ring `r` as tokml's `coordinates`: `x,y` each, one per line.
fn coordinates(
  sb : StringBuilder,
  table : @geom.Table,
  r : Int32,
  number_text : (Double) -> String,
) -> Unit {
  sb.write_string("<coordinates>")
  let (start, end) = table.points(r)
  for i in start..<end {
    if i > start {
      sb.write_char('\n')
    }
    sb.write_string(number_text(table.coords[i * 2]))
    sb.write_char(',')
    sb.write_string(number_text(table.coords[i * 2 + 1]))
  }
  sb.write_string("</coordinates>")
}

///|
/// The polygon of part `p`: its first ring the outer boundary, the others inner ones.
fn polygon(
  sb : StringBuilder,
  table : @geom.Table,
  p : Int32,
  number_text : (Double) -> String,
) -> Unit {
  sb.write_string("<Polygon>")
  let (start, end) = table.rings(p)
  for r in start..<end {
    let side = if r == start { "outerBoundaryIs" } else { "innerBoundaryIs" }
    sb.write_string("\n<\{side}>\n  <LinearRing>")
    coordinates(sb, table, r, number_text)
    sb.write_string("</LinearRing></\{side}>")
  }
  sb.write_string("</Polygon>")
}

///|
/// The geometry of row `row` as tokml's `convertGeometry` writes it; nothing without one.
fn placemark_geometry(
  sb : StringBuilder,
  table : @geom.Table,
  row : Int32,
  number_text : (Double) -> String,
) -> Unit {
  let (first, last) = table.parts(row)
  let line = (tag : String, r : Int32) => {
    sb.write_string("<\{tag}>")
    coordinates(sb, table, r, number_text)
    sb.write_string("</\{tag}>")
  }
  match table.kinds[row] {
    NoGeometry => ()
    Point | LineString => {
      let tag = if table.kinds[row] is Point { "Point" } else { "LineString" }
      line(tag, table.rings(first).0)
    }
    Polygon => polygon(sb, table, first, number_text)
    MultiPoint => {
      sb.write_string("<MultiGeometry>")
      let (start, end) = table.points(table.rings(first).0)
      for i in start..<end {
        sb.write_string("\n<Point><coordinates>")
        sb.write_string(number_text(table.coords[i * 2]))
        sb.write_char(',')
        sb.write_string(number_text(table.coords[i * 2 + 1]))
        sb.write_string("</coordinates></Point>")
      }
      sb.write_string("</MultiGeometry>")
    }
    MultiLineString | MultiPolygon => {
      sb.write_string("<MultiGeometry>")
      for p in first..<last {
        sb.write_char('\n')
        if table.kinds[row] is MultiPolygon {
          polygon(sb, table, p, number_text)
        } else {
          line("LineString", table.rings(p).0)
        }
      }
      sb.write_string("</MultiGeometry>")
    }
  }
}
