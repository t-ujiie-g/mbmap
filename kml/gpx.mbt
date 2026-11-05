///|
let gpxx_namespace : String = "http://www.garmin.com/xmlschemas/GpxExtensions/v3"

///|
/// Reads a GPX document into rows as togeojson's `gpx()` does: every `trk`, then every `rte`
/// and `wpt`; elevations dropped, `coordinateProperties` and `links` as JSON text.
/// `number` and `number_text` as `read_kml` takes them.
pub fn read_gpx(
  input : Bytes,
  number~ : (String) -> Double,
  number_text~ : (Double) -> String,
) -> @geom.Table raise @xml.XmlError {
  let r = Reader::new(@xml.Document::parse(input), number, number_text)
  let d = r.doc
  let ns = [gpxx_namespace]
  if d.first(0, "gpx") is Some(gpx) {
    for i in 0..<d.attribute_count(gpx) {
      let v = d.attribute_value(gpx, i)
      if starts_with(d.attribute_name(gpx, i), "xmlns:") && v != gpxx_namespace {
        ns.push(v)
      }
    }
  }
  for t in d.elements(0, "trk") {
    r.track_feature(ns, t)
  }
  for rte in d.elements(0, "rte") {
    if r.stopped() {
      break
    }
    let line = Line::new()
    guard r.points(rte, "rtept", line) else { continue }
    let p = Props::new()
    p.set("_gpxType", Str("rte"))
    r.gpx_props(p, ns, rte)
    r.line_style(p, rte)
    let shapes = Shapes::new()
    shapes.line(line.xy)
    shapes.end_part()
    shapes.end_member(LineString)
    r.emit(shapes, p, None)
  }
  for w in d.elements(0, "wpt") {
    if r.stopped() {
      break
    }
    let x = r.coordinate(w, "lon")
    let y = r.coordinate(w, "lat")
    guard !x.is_nan() && !y.is_nan() else { continue }
    let p = Props::new()
    r.gpx_props(p, ns, w)
    r.val_into(p, w, "sym")
    let shapes = Shapes::new()
    shapes.point(x, y)
    shapes.end_ring()
    shapes.end_part()
    shapes.end_member(Point)
    r.emit(shapes, p, None)
  }
  r.finish()
}

///|
/// A point's `lon` or `lat` attribute by `parseFloat`.
fn Reader::coordinate(self : Reader, node : Int32, name : String) -> Double {
  parse_float(self.doc.attribute(node, name).unwrap_or(""), self.number)
}

///|
/// `extractProperties`: `name`, `cmt`, `desc`, `type`, `time`, `keywords`, each
/// element of the namespaces `ns` by its name (`:` made `_`), and the `link`s.
fn Reader::gpx_props(
  self : Reader,
  p : Props,
  ns : Array[String],
  node : Int32,
) -> Unit {
  let d = self.doc
  for t in ["name", "cmt", "desc", "type", "time", "keywords"] {
    self.val_into(p, node, t)
  }
  for uri in ns {
    for e in d.elements_ns(node, uri=Some(uri), lname=None) {
      p.set(replace_first(d.name(e), ":", "_"), Str(js_trim(d.text(e))))
    }
  }
  let links = d.elements(node, "link")
  if links.length() > 0 {
    let items = []
    for l in links {
      let keys = ["href"]
      let values = [
        match d.attribute(l, "href") {
          Some(h) => json_string(h)
          None => "null"
        },
      ]
      for t in ["text", "type"] {
        let v = self.val(l, t)
        if v != "" {
          keys.push(t)
          values.push(json_string(v))
        }
      }
      items.push(json_object(keys, values))
    }
    p.set("links", Str(json_array(items, 0, items.length())))
  }
}

///|
/// `getLineStyle` of the first `extensions`: its `line`'s color, opacity and
/// width (millimeters as pixels at 96 per inch); zeros are left out.
fn Reader::line_style(self : Reader, p : Props, node : Int32) -> Unit {
  guard self.doc.first(node, "extensions") is Some(ext) &&
    self.doc.first(ext, "line") is Some(line) else {
    return
  }
  let c = self.val(line, "color")
  if c != "" {
    p.set("stroke", Str("#" + c))
  }
  let o = self.num1(line, "opacity")
  if !o.is_nan() && o != 0.0 {
    p.set("stroke-opacity", Num(o))
  }
  let w = self.num1(line, "width")
  if !w.is_nan() && w != 0.0 {
    p.set("stroke-width", Num(w * 96.0 / 25.4))
  }
}

///|
/// A track's (or a route's) segments as `getPoints` reads them: x, y pairs with `ends` per segment,
/// times as a JSON array (`""` without any), and extension values by plural name (`names`,
/// `name_ends`), each a JSON array as long as the segment's points.
priv struct Line {
  xy : Array[Double]
  ends : Array[Int32]
  times : Array[String]
  names : Array[String]
  values : Array[String]
  name_ends : Array[Int32]
}

///|
fn Line::new() -> Line {
  { xy: [], ends: [], times: [], names: [], values: [], name_ends: [], }
}

///|
/// The JSON array of segment `k`'s values named `name`, or of nulls for each of
/// its points if it has none.
fn Line::column(self : Line, k : Int32, name : String) -> String {
  for i in @geom.start_of(self.name_ends, k)..<self.name_ends[k] {
    if self.names[i] == name {
      return self.values[i]
    }
  }
  json_array(
    Array::make(self.ends[k] - @geom.start_of(self.ends, k), "null"),
    0,
    self.ends[k] - @geom.start_of(self.ends, k),
  )
}

///|
/// `getExtensions`: an `extensions` element's children as names and JSON values,
/// Garmin's `TrackPointExtension` entered, heart rates named `heart`.
fn Reader::extension_values(
  self : Reader,
  node : Int32,
  names : Array[String],
  values : Array[String],
) -> Unit {
  let d = self.doc
  for c in d.children(node) {
    guard d.kind(c) == Element else { continue }
    let name = match d.name(c) {
      "heart" | "gpxtpx:hr" | "hr" => "heart"
      n => n
    }
    if name == "gpxtpx:TrackPointExtension" {
      self.extension_values(c, names, values)
    } else {
      let text = d.text(c)
      let v = parse_float(text, self.number)
      names.push(name)
      values.push(
        if v.is_nan() {
          json_string(text)
        } else {
          self.json_number(v)
        },
      )
    }
  }
}

///|
/// `getPoints`: the `tag` points under `node` added to `line` as a segment;
/// false (nothing added) for fewer than two with a position.
fn Reader::points(
  self : Reader,
  node : Int32,
  tag : String,
  line : Line,
) -> Bool {
  let d = self.doc
  let pts = d.elements(node, tag)
  let n = pts.length()
  let xy = []
  let times = []
  let names = []
  // Column-major: name k's values are `columns[k * n:(k + 1) * n]`.
  let columns = []
  let ext_names = []
  let ext_values = []
  for i, pt in pts {
    let x = self.coordinate(pt, "lon")
    let y = self.coordinate(pt, "lat")
    guard !x.is_nan() && !y.is_nan() else { continue }
    xy.push(x)
    xy.push(y)
    if d.first(pt, "time") is Some(t) {
      let v = d.text(t)
      if v != "" {
        times.push(json_string(v))
      }
    }
    ext_names.clear()
    ext_values.clear()
    if d.first(pt, "extensions") is Some(e) {
      self.extension_values(e, ext_names, ext_values)
    }
    for j, name in ext_names {
      let plural = if name == "heart" {
        name
      } else {
        replace_first(name, "gpxtpx:", "") + "s"
      }
      let k = match names.search(plural) {
        Some(k) => k
        None => {
          names.push(plural)
          for _ in 0..<n {
            columns.push("null")
          }
          names.length() - 1
        }
      }
      columns[k * n + i] = ext_values[j]
    }
  }
  guard xy.length() >= 4 else { return false }
  for v in xy {
    line.xy.push(v)
  }
  line.ends.push(line.xy.length() / 2)
  line.times.push(
    if times.length() > 0 {
      json_array(times, 0, times.length())
    } else {
      ""
    },
  )
  for k, name in names {
    line.names.push(name)
    line.values.push(json_array(columns, k * n, (k + 1) * n))
  }
  line.name_ends.push(line.names.length())
  true
}

///|
/// `getTrack`: a track's segments as one feature. (An extension named `time` of
/// several segments is left out; togeojson writes it into the times by segment.)
fn Reader::track_feature(
  self : Reader,
  ns : Array[String],
  node : Int32,
) -> Unit {
  guard !self.stopped() else { return }
  let line = Line::new()
  for s in self.doc.elements(node, "trkseg") {
    self.points(s, "trkpt", line) |> ignore
  }
  let count = line.ends.length()
  guard count > 0 else { return }
  let multi = count > 1
  let p = Props::new()
  p.set("_gpxType", Str("trk"))
  self.gpx_props(p, ns, node)
  self.line_style(p, node)
  let keys = []
  let values = []
  let times = []
  for t in line.times {
    if t != "" {
      times.push(t)
    }
  }
  if times.length() > 0 {
    keys.push("times")
    values.push(
      if multi {
        json_array(times, 0, times.length())
      } else {
        times[0]
      },
    )
  }
  for i in 0..<line.names.length() {
    let name = line.names[i]
    let value = if multi {
      let all = []
      for m in 0..<count {
        all.push(line.column(m, name))
      }
      json_array(all, 0, count)
    } else {
      line.values[i]
    }
    match keys.search(name) {
      None => {
        keys.push(name)
        values.push(value)
      }
      Some(at) => if !multi { values[at] = value }
    }
  }
  p.set("coordinateProperties", Str(json_object(keys, values)))
  let shapes = Shapes::new()
  for k in 0..<count {
    for i in @geom.start_of(line.ends, k)..<line.ends[k] {
      shapes.point(line.xy[i * 2], line.xy[i * 2 + 1])
    }
    shapes.end_ring()
    shapes.end_part()
  }
  shapes.end_member(if multi { MultiLineString } else { LineString })
  self.emit(shapes, p, None)
}
