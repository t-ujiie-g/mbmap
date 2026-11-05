// Ported from @tmcw/togeojson 7.1.3: BSD 2-Clause License, Copyright (c) 2019 Tom MacWright,
// Mapbox. See NOTICE.

///|
/// Most properties one feature may have (AGENTS.md §8.2).
pub const MAX_KML_KEYS : Int32 = 4096

///|
/// Most property cells (columns times rows) a table may have.
pub const MAX_KML_CELLS : Int32 = 32_000_000

///|
/// Most points a table may have.
pub const MAX_KML_POINTS : Int32 = 20_000_000

///|
/// A feature's properties as togeojson assigns them: a key set again keeps its
/// place and takes the new value; `__proto__` is dropped, as assigning a string
/// to it does nothing in JavaScript. `index` finds keys once there are many;
/// `over` is set by a key past `MAX_KML_KEYS`, which is left out.
priv struct Props {
  items : Array[(String, @geom.Prop)]
  mut index : Map[String, Int32]?
  mut over : Bool
}

///|
fn Props::new() -> Props {
  { items: [], index: None, over: false, }
}

///|
fn Props::set(self : Props, key : String, value : @geom.Prop) -> Unit {
  if key == "__proto__" {
    return
  }
  let key = well_formed(key)
  let value = match value {
    Str(v) => @geom.Prop::Str(well_formed(v))
    v => v
  }
  let at = match self.index {
    Some(index) => index.get(key).unwrap_or(-1)
    None => {
      let mut at = -1
      for i, item in self.items {
        if item.0 == key {
          at = i
        }
      }
      at
    }
  }
  if at >= 0 {
    self.items[at] = (key, value)
    return
  }
  if self.items.length() >= MAX_KML_KEYS {
    self.over = true
    return
  }
  self.items.push((key, value))
  if self.index is Some(index) {
    index[key] = self.items.length() - 1
  } else if self.items.length() == 32 {
    let index = Map([])
    for i, item in self.items {
      index[item.0] = i
    }
    self.index = Some(index)
  }
}

///|
/// `s.toWellFormed()`: lone surrogates (from character references) as U+FFFD,
/// as UTF-8 cannot carry them.
fn well_formed(s : String) -> String {
  let n = s.length()
  let out = StringBuilder()
  let mut last = 0
  let mut i = 0
  while i < n {
    let c = s[i].to_int()
    if c >= 0xD800 && c <= 0xDFFF {
      if c <= 0xDBFF &&
        i + 1 < n &&
        s[i + 1].to_int() >= 0xDC00 &&
        s[i + 1].to_int() <= 0xDFFF {
        i += 1
      } else {
        out.write_view(s.clamped_view(start=last, end=i))
        out.write_char('\u{FFFD}')
        last = i + 1
      }
    }
    i += 1
  }
  if last == 0 {
    return s
  }
  out.write_view(s.clamped_view(start=last, end=n))
  out.to_string()
}

///|
fn Props::merge(self : Props, other : Props) -> Unit {
  for item in other.items {
    self.set(item.0, item.1)
  }
}

///|
/// The geometries of one feature, in `@geom.Table`'s offsets with a member per
/// row and z dropped: `kinds`, then part, ring and point ends over `coords`.
/// `reader` counts the points.
priv struct Shapes {
  reader : Reader
  kinds : Array[@geom.GeomKind]
  part_ends : Array[Int32]
  ring_ends : Array[Int32]
  point_ends : Array[Int32]
  coords : Array[Double]
}

///|
fn Shapes::new(reader : Reader) -> Shapes {
  {
    reader,
    kinds: [],
    part_ends: [],
    ring_ends: [],
    point_ends: [],
    coords: [],
  }
}

///|
fn Shapes::point(self : Shapes, x : Double, y : Double) -> Unit {
  if self.reader.has_room(1) {
    self.reader.points += 1
    self.coords.push(x)
    self.coords.push(y)
  }
}

///|
fn Shapes::end_ring(self : Shapes) -> Unit {
  if self.coords.length() / 2 > @geom.start_of_last(self.point_ends) {
    self.point_ends.push(self.coords.length() / 2)
  }
}

///|
fn Shapes::end_part(self : Shapes) -> Unit {
  if self.point_ends.length() > @geom.start_of_last(self.ring_ends) {
    self.ring_ends.push(self.point_ends.length())
  }
}

///|
/// Ends a member of `kind`; one left empty, or with a coordinate that is not
/// finite, is dropped.
fn Shapes::end_member(self : Shapes, kind : @geom.GeomKind) -> Unit {
  let parts = @geom.start_of_last(self.part_ends)
  let rings = @geom.start_of(self.ring_ends, parts)
  let points = @geom.start_of(self.point_ends, rings)
  let mut ok = self.ring_ends.length() > parts
  for i in (points * 2)..<self.coords.length() {
    ok = ok && !self.coords[i].is_nan() && !self.coords[i].is_inf()
  }
  if ok {
    self.part_ends.push(self.ring_ends.length())
    self.kinds.push(kind)
  } else {
    self.ring_ends.truncate(parts)
    self.point_ends.truncate(rings)
    self.coords.truncate(points * 2)
  }
}

///|
/// A flat x, y ring or line as one part of one ring.
fn Shapes::line(self : Shapes, xy : Array[Double]) -> Unit {
  for i = 0; i + 1 < xy.length(); i = i + 2 {
    self.point(xy[i], xy[i + 1])
  }
  self.end_ring()
}

///|
/// A map from strings to numbers over `@xml.Names`.
priv struct Lookup {
  names : @xml.Names
  values : Array[Int32]
}

///|
fn Lookup::new() -> Lookup {
  { names: @xml.Names::new(), values: [], }
}

///|
/// The number `key` maps to, -1 if none.
fn Lookup::get(self : Lookup, key : String) -> Int32 {
  let i = self.names.find(key)
  if i >= 0 {
    self.values[i]
  } else {
    -1
  }
}

///|
fn Lookup::set(self : Lookup, key : String, value : Int32) -> Unit {
  let i = self.names.add(key)
  if i == self.values.length() {
    self.values.push(value)
  } else {
    self.values[i] = value
  }
}

///|
/// What both readers share: the document, the host's number conversions, the
/// table being built, the points read into shapes and what `charge` has counted.
priv struct Reader {
  doc : @xml.Document
  number : (String) -> Double
  number_text : (Double) -> String
  out : @geom.TableBuilder
  mut limit : String?
  mut points : Int32
  mut charged : Int64
  max_cells : Int64
  max_points : Int32
}

///|
fn Reader::new(
  doc : @xml.Document,
  number : (String) -> Double,
  number_text : (Double) -> String,
) -> Reader {
  {
    doc,
    number,
    number_text,
    out: @geom.TableBuilder::new(),
    limit: None,
    points: 0,
    charged: 0,
    max_cells: MAX_KML_CELLS.to_int64(),
    max_points: MAX_KML_POINTS,
  }
}

///|
/// Whether reading must stop: a limit was passed (kept in `limit`, which
/// `finish` raises).
fn Reader::stopped(self : Reader) -> Bool {
  self.limit is Some(_)
}

///|
/// Stops reading past `max` of `what`.
fn Reader::limit_at(self : Reader, max : Int32, what : String) -> Unit {
  self.limit = Some("more than \{max} \{what}")
}

///|
/// Whether `pending` more points fit; if not, reading stops.
fn Reader::has_room(self : Reader, pending : Int32) -> Bool {
  if self.points + pending <= self.max_points {
    return true
  }
  self.limit_at(MAX_KML_POINTS, "points")
  false
}

///|
/// Counts `cells` of text about to be built that no table row holds yet, as a table's
/// cells count; false past the limit, where reading stops.
fn Reader::charge(self : Reader, cells : Int64) -> Bool {
  self.charged += cells
  if self.charged <= self.max_cells {
    return true
  }
  self.limit_at(MAX_KML_CELLS, "property cells")
  false
}

///|
/// The table, or the limit it passed.
fn Reader::finish(self : Reader) -> @geom.Table raise @xml.XmlError {
  if self.limit is Some(m) {
    raise @xml.Limit(m)
  }
  self.out.finish()
}

///|
/// togeojson's `nodeVal(get1(node, tag))`: the first such descendant's text, `""`
/// without one.
fn Reader::val(self : Reader, node : Int32, tag : String) -> String {
  match self.doc.first(node, tag) {
    Some(e) => self.doc.text(e)
    None => ""
  }
}

///|
/// `val1` as `getMulti` uses it: `val` set as `key` unless empty.
fn Reader::val_into(
  self : Reader,
  p : Props,
  node : Int32,
  tag : String,
) -> Unit {
  let v = self.val(node, tag)
  if v != "" {
    p.set(tag, Str(v))
  }
}

///|
/// `num1`: `parseFloat` of `val`, NaN if none.
fn Reader::num1(self : Reader, node : Int32, tag : String) -> Double {
  parse_float(self.val(node, tag), self.number)
}

///|
/// Adds a row per member of `shapes` with `props` (one without geometry if it
/// has none), up to the limits.
fn Reader::emit(
  self : Reader,
  shapes : Shapes,
  props : Props,
  id : String?,
) -> Unit {
  let out = self.out
  let id = match id {
    Some(s) => Some(@geom.Prop::Str(s))
    None => None
  }
  let members = shapes.kinds.length()
  for m in 0..<@cmp.maximum(members, 1) {
    if members > 0 {
      for p in @geom.start_of(shapes.part_ends, m)..<shapes.part_ends[m] {
        for r in @geom.start_of(shapes.ring_ends, p)..<shapes.ring_ends[p] {
          for i in @geom.start_of(shapes.point_ends, r)..<shapes.point_ends[r] {
            out.point(shapes.coords[i * 2], shapes.coords[i * 2 + 1])
          }
          out.end_ring()
        }
        out.end_part()
      }
    }
    for item in props.items {
      out.prop(item.0, item.1)
    }
    out.end_feature(if members > 0 { shapes.kinds[m] } else { NoGeometry }, id~)
    if props.over {
      self.limit_at(MAX_KML_KEYS, "properties in a feature")
    } else if out.cells() > self.max_cells {
      self.limit_at(MAX_KML_CELLS, "property cells")
    }
    if self.stopped() {
      return
    }
  }
}
