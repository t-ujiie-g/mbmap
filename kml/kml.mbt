// Ported from @tmcw/togeojson 7.1.3: BSD 2-Clause License, Copyright (c) 2019 Tom MacWright,
// Mapbox. See NOTICE.

///|
/// Reads a KML document into rows as togeojson's `kml()` does: every `Placemark`, then every
/// `GroundOverlay` (no `NetworkLink`s); a multi-geometry gives a row per member, nested values are
/// JSON text. `number` / `number_text` are the host's `Number` / `String`; `trig` turns `LatLonBox`es.
pub fn read_kml(
  input : Bytes,
  number~ : (String) -> Double,
  number_text~ : (Double) -> String,
  trig~ : @core.Trig,
) -> @geom.Table raise @xml.XmlError {
  let r = Reader::new(@xml.Document::parse(input), number, number_text)
  let d = r.doc
  let ids = Lookup::new()
  let styles = Props::new()
  let ends = []
  r.style_map(ids, styles, ends)
  let schema = Lookup::new()
  for f in d.elements(0, "SimpleField") {
    schema.set(
      d.attribute(f, "name").unwrap_or(""),
      match d.attribute(f, "type").unwrap_or("") {
        "int" | "uint" | "short" | "ushort" | "float" | "double" => 1
        "bool" => 2
        _ => 0
      },
    )
  }
  let features = [d.elements(0, "Placemark"), d.elements(0, "GroundOverlay")]
  for k, nodes in features {
    for f in nodes {
      if r.stopped() {
        break
      }
      let p = Props::new()
      if k == 1 {
        p.set("@geometry-type", Str("groundoverlay"))
      }
      for
        t in [
          "name", "address", "visibility", "open", "phoneNumber", "description",
        ] {
        r.val_into(p, f, t)
      }
      let shapes = Shapes::new(r)
      let times = []
      if k == 0 {
        r.geometry(f, shapes, times)
      } else {
        r.overlay_box(f, shapes, trig)
      }
      r.common(p, f, ids, styles, ends, schema, k > 0)
      if k == 0 && times.length() > 0 {
        let t = if times.length() == 1 {
          times[0]
        } else {
          json_array(times, 0, times.length())
        }
        p.set("coordinateProperties", Str(json_object(["times"], [t])))
      }
      for i, item in p.items {
        if item.0 == "visibility" {
          p.items[i] = ("visibility", Bool(item.1 != Str("0")))
        }
      }
      let id = d.attribute(f, "id").unwrap_or("")
      r.emit(shapes, p, if id == "" { None } else { Some(id) })
    }
  }
  r.finish()
}

///|
/// The properties every feature kind takes after its own, in togeojson's order:
/// an HTML description, the cascaded and inline styles, (for overlays) the icon,
/// extended data, time span and time stamp.
fn Reader::common(
  self : Reader,
  p : Props,
  node : Int32,
  ids : Lookup,
  styles : Props,
  ends : Array[Int32],
  schema : Lookup,
  icon : Bool,
) -> Unit {
  let d = self.doc
  if d.first(node, "description") is Some(desc) {
    for c in d.children(desc) {
      if d.kind(c) == CData {
        p.set(
          "description",
          Str(
            json_object(["@type", "value"], [
              json_string("html"),
              json_string(d.text(c)),
            ]),
          ),
        )
        break
      }
    }
  }
  self.cascaded_style(p, node, ids, styles, ends)
  p.merge(self.style(node))
  if icon {
    self.icon_href(p, node)
  }
  if d.first(node, "ExtendedData") is Some(ext) {
    for data in d.elements(ext, "Data") {
      p.set(
        d.attribute(data, "name").unwrap_or(""),
        Str(self.val(data, "value")),
      )
    }
    for simple in d.elements(ext, "SimpleData") {
      let name = d.attribute(simple, "name").unwrap_or("")
      let text = d.text(simple)
      p.set(
        name,
        match schema.get(name) {
          1 => Num((self.number)(text))
          2 => Bool(text != "")
          _ => Str(text)
        },
      )
    }
  }
  if d.first(node, "TimeSpan") is Some(span) {
    p.set(
      "timespan",
      Str(
        json_object(["begin", "end"], [
          json_string(self.val(span, "begin")),
          json_string(self.val(span, "end")),
        ]),
      ),
    )
  }
  if d.first(node, "TimeStamp") is Some(stamp) {
    p.set("timestamp", Str(self.val(stamp, "when")))
  }
}

///|
/// The tuples of `s` as togeojson's `coord` reads them, four numbers each (a count, up to three
/// values, NaN after); tuples of fewer than two numbers are left out (unless `point`, which
/// reads `s` as one tuple). Stops past the point limit.
fn Reader::tuples(self : Reader, s : String, point : Bool) -> Array[Double] {
  let out = []
  let n = s.length()
  let mut i = 0
  while i < n {
    while i < n && !point && @xml.is_js_space(s[i]) {
      i += 1
    }
    let at = out.length()
    out.push(0.0)
    out.push(@double.not_a_number)
    out.push(@double.not_a_number)
    out.push(@double.not_a_number)
    let mut count = 0
    let num = StringBuilder()
    while true {
      let end = i == n || (!point && @xml.is_js_space(s[i]))
      if end || s[i] == ',' {
        let v = parse_float(num.to_string(), self.number)
        if !v.is_nan() && count < 3 {
          count += 1
          out[at + count] = v
        }
        num.reset()
        if end {
          break
        }
      } else if !@xml.is_js_space(s[i]) {
        num.write_char(s[i].to_int().unsafe_to_char())
      }
      i += 1
    }
    out[at] = count.to_double()
    if count < 2 && !point {
      out.truncate(at)
    }
    if point || !self.has_room(out.length() / 4) {
      break
    }
  }
  out
}

///|
/// Appends `t`'s tuples as a ring (or line) of `shapes`, closed first as
/// togeojson's `fixRing` closes it (unless the last tuple equals the first,
/// z included) when `close`; false if there are fewer than `least` tuples.
fn add_tuples(
  shapes : Shapes,
  t : Array[Double],
  close : Bool,
  least : Int32,
) -> Bool {
  let n = t.length()
  let mut same = n == 0
  if n > 0 {
    same = t[0] == t[n - 4]
    for k in 1..<=t[0].to_int() {
      same = same && t[k] == t[n - 4 + k]
    }
  }
  let count = n / 4 + (if close && !same { 1 } else { 0 })
  guard count >= least else { return false }
  for k = 0; k < n; k = k + 4 {
    shapes.point(t[k + 1], t[k + 2])
  }
  if count > n / 4 {
    shapes.point(t[1], t[2])
  }
  shapes.end_ring()
  true
}

///|
/// `getGeometry`: the geometries among `node`'s child elements (multi-geometries
/// and multi-tracks entered), each track's `when`s (JSON arrays) in `times`.
fn Reader::geometry(
  self : Reader,
  node : Int32,
  shapes : Shapes,
  times : Array[String],
) -> Unit {
  let d = self.doc
  for c in d.children(node) {
    if self.stopped() {
      return
    }
    match d.name(c) {
      "MultiGeometry" | "MultiTrack" | "gx:MultiTrack" =>
        self.geometry(c, shapes, times)
      "Point" => {
        let t = self.tuples(self.val(c, "coordinates"), true)
        if t.length() > 0 && t[0] >= 2.0 {
          shapes.point(t[1], t[2])
          shapes.end_ring()
          shapes.end_part()
          shapes.end_member(Point)
        }
      }
      "LinearRing" | "LineString" =>
        if add_tuples(
            shapes,
            self.tuples(self.val(c, "coordinates"), false),
            false,
            2,
          ) {
          shapes.end_part()
          shapes.end_member(LineString)
        }
      "Polygon" => {
        for ring in d.elements(c, "LinearRing") {
          if self.stopped() {
            return
          }
          add_tuples(
            shapes,
            self.tuples(self.val(ring, "coordinates"), false),
            true,
            4,
          )
          |> ignore
        }
        shapes.end_part()
        shapes.end_member(Polygon)
      }
      "Track" | "gx:Track" => self.track(c, shapes, times)
      _ => ()
    }
  }
}

///|
/// `gxCoords`: a track's `coord`s (prefixed ones if none are bare), each split
/// at single spaces; a line, or a point if there is one, and its `when`s.
fn Reader::track(
  self : Reader,
  node : Int32,
  shapes : Shapes,
  times : Array[String],
) -> Unit {
  let d = self.doc
  let mut coords = d.elements(node, "coord")
  if coords.length() == 0 {
    coords = d.elements_ns(node, uri=None, lname=Some("coord"))
  }
  guard coords.length() > 0 else { return }
  for c in coords {
    let s = d.text(c)
    let mut k = 0
    let mut from = 0
    let mut x = @double.not_a_number
    let mut y = @double.not_a_number
    for i in 0..<=s.length() {
      if i == s.length() || s[i] == ' ' {
        let v = parse_float(@xml.units(s, from, i), self.number)
        if k == 0 {
          x = v
        } else if k == 1 {
          y = v
        }
        k += 1
        from = i + 1
      }
    }
    shapes.point(x, y)
  }
  shapes.end_ring()
  shapes.end_part()
  shapes.end_member(if coords.length() >= 2 { LineString } else { Point })
  let when = []
  for w in d.elements(node, "when") {
    when.push(json_string(d.text(w)))
  }
  if when.length() > 0 {
    times.push(json_array(when, 0, when.length()))
  }
}

///|
/// A `LatLonBox`'s polygon, turned by `rotation` degrees
/// (unless NaN) about its center as togeojson's `rotateBox` turns it; none
/// unless all four sides are numbers.
fn Reader::box(
  self : Reader,
  node : Int32,
  shapes : Shapes,
  rotation : Double,
  trig : @core.Trig,
) -> Unit {
  let north = self.num1(node, "north")
  let west = self.num1(node, "west")
  let east = self.num1(node, "east")
  let south = self.num1(node, "south")
  guard !north.is_nan() && !west.is_nan() && !east.is_nan() && !south.is_nan() else {
    return
  }
  let ring = [west, north, east, north, east, south, west, south, west, north]
  if !rotation.is_nan() {
    let cx = (west + east) / 2.0
    let cy = (south + north) / 2.0
    for i = 0; i < ring.length(); i = i + 2 {
      let dy = ring[i + 1] - cy
      let dx = ring[i] - cx
      let distance = (trig.pow(dy, 2.0) + trig.pow(dx, 2.0)).sqrt()
      let angle = trig.atan2(dy, dx) + rotation * degrees_to_radians
      ring[i] = cx + trig.cos(angle) * distance
      ring[i + 1] = cy + trig.sin(angle) * distance
    }
  }
  shapes.line(ring)
  shapes.end_part()
  shapes.end_member(Polygon)
}

///|
/// JavaScript's `Math.PI / 180`.
let degrees_to_radians : Double = 0.017453292519943295

///|
/// `getGroundOverlayBox`: a `gx:LatLonQuad`'s ring (from the overlay's first
/// `coordinates`), else its `LatLonBox`.
fn Reader::overlay_box(
  self : Reader,
  node : Int32,
  shapes : Shapes,
  trig : @core.Trig,
) -> Unit {
  let d = self.doc
  if d.first(node, "gx:LatLonQuad") is Some(_) {
    add_tuples(
      shapes,
      self.tuples(self.val(node, "coordinates"), false),
      true,
      0,
    )
    |> ignore
    shapes.end_part()
    shapes.end_member(Polygon)
  } else if d.first(node, "LatLonBox") is Some(box) {
    self.box(box, shapes, self.num1(box, "rotation"), trig)
  }
}
