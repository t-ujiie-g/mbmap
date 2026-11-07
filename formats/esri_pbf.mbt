// Coordinates restored as arcgis-pbf-parser 0.0.4 restores them: Apache License 2.0, Copyright
// Rowan Winsemius. See NOTICE.

///|
/// Reads an ArcGIS REST query result in protocol buffers (`f=pbf`,
/// FeatureCollection.proto's `FeatureResult`) as `read_esri_json` reads its JSON:
/// quantized coordinates restored by the result's transform (y down from an upper-left
/// origin), Z and M dropped, rings as terraformer gives them; ids from the
/// `objectIdFieldName` field. Gives the table and whether `exceededTransferLimit` is set.
pub fn read_esri_pbf(bytes : BytesView) -> (@geom.Table, Bool) raise ReadError {
  esri_pbf_table(bytes, @geom.MAX_TABLE_POINTS, @geom.MAX_TABLE_CELLS)
}

///|
/// What a `FeatureResult` says about its features: the id field, the geometry type
/// (0 point, 1 multipoint, 2 polyline, 3 polygon), values per position, the
/// transform (x and y scale, x and y translate, whether y grows down) and the fields.
priv struct EsriResult {
  mut id_field : String?
  mut geometry_type : Int32
  mut exceeded : Bool
  mut has_z : Bool
  mut has_m : Bool
  transform : FixedArray[Double]
  mut quantized : Bool
  mut upper_left : Bool
  fields : Array[String]
  features : Array[(Int32, Int32)]
}

///|
fn esri_pbf_table(
  bytes : BytesView,
  max_points : Int32,
  max_cells : Int32,
) -> (@geom.Table, Bool) raise ReadError {
  let r = @pbf.Reader::new(bytes)
  let res : EsriResult = {
    id_field: None,
    geometry_type: 0,
    exceeded: false,
    has_z: false,
    has_m: false,
    transform: [1.0, 1.0, 0.0, 0.0],
    quantized: false,
    upper_left: true,
    fields: [],
    features: [],
  }
  let mut found = false
  while !r.at_end() {
    let t = r.read_tag()
    if t == @pbf.tag(2, @pbf.WIRE_LEN) {
      let query = r.enter()
      while !r.at_end() {
        let u = r.read_tag()
        if u == @pbf.tag(1, @pbf.WIRE_LEN) {
          let token = r.enter()
          esri_result(r, res)
          r.exit(token)
          found = true
        } else {
          r.skip(u)
        }
      }
      r.exit(query)
    } else {
      r.skip(t)
    }
  }
  let fail = (pos : Int32, m : String) => {
    raise Invalid(format="ArcGIS PBF", pos~, m)
  }
  if r.failed() {
    fail(r.pos(), "malformed protocol buffers")
  }
  if !found {
    fail(0, "not an ArcGIS query result")
  }
  let out = @geom.TableBuilder::new()
  let shapes = Shapes::new()
  let values = []
  let stride = 2 +
    (if res.has_z { 1 } else { 0 }) +
    (if res.has_m { 1 } else { 0 })
  for range in res.features {
    let (start, end) = range
    r.reset(start, end)
    shapes.clear()
    let props = []
    let lengths = []
    values.clear()
    while !r.at_end() {
      let t = r.read_tag()
      if t == @pbf.tag(1, @pbf.WIRE_LEN) {
        let token = r.enter()
        let v = esri_value(r)
        r.exit(token)
        let i = props.length()
        props.push(
          (if i < res.fields.length() { res.fields[i] } else { "" }, v),
        )
      } else if t == @pbf.tag(2, @pbf.WIRE_LEN) {
        let token = r.enter()
        esri_pbf_geometry(r, lengths, values)
        r.exit(token)
      } else {
        r.skip(t)
      }
    }
    if r.failed() {
      fail(r.pos(), "malformed protocol buffers")
    }
    props.retain(p => p.0 != "")
    if values.length() > 0 && !esri_shape(res, stride, lengths, values, shapes) {
      fail(start, "malformed geometry")
    }
    if out.table.coords.length() / 2 + shapes.points() > max_points {
      fail(start, "too many points")
    }
    shapes.emit(out, props, None, id=esri_id(props, res.id_field), max_cells~)
    if out.table.columns.length() > MAX_GEOJSON_KEYS {
      fail(start, "more than \{MAX_GEOJSON_KEYS} property keys")
    } else if out.cells() > max_cells.to_int64() {
      fail(start, "more than \{@geom.MAX_TABLE_CELLS} property cells")
    }
  }
  (out.finish(), res.exceeded)
}

///|
/// Reads a `FeatureResult`'s fields into `res`, the features' byte ranges kept for later.
fn esri_result(r : @pbf.Reader, res : EsriResult) -> Unit {
  while !r.at_end() {
    let t = r.read_tag()
    match t >> 3 {
      1 => res.id_field = Some(r.read_string())
      7 => res.geometry_type = r.read_varint32()
      9 => res.exceeded = r.read_bool()
      10 => res.has_z = r.read_bool()
      11 => res.has_m = r.read_bool()
      12 if (t & 7) == @pbf.WIRE_LEN => {
        res.quantized = true
        let token = r.enter()
        while !r.at_end() {
          let u = r.read_tag()
          match u >> 3 {
            1 => res.upper_left = r.read_varint32() == 0
            2 | 3 if (u & 7) == @pbf.WIRE_LEN => {
              let at = if u >> 3 == 2 { 0 } else { 2 }
              let pair = r.enter()
              while !r.at_end() {
                let w = r.read_tag()
                if (w >> 3 == 1 || w >> 3 == 2) && (w & 7) == @pbf.WIRE_FIXED64 {
                  res.transform[at + (w >> 3) - 1] = r.read_double()
                } else {
                  r.skip(w)
                }
              }
              r.exit(pair)
            }
            _ => r.skip(u)
          }
        }
        r.exit(token)
      }
      13 if (t & 7) == @pbf.WIRE_LEN => {
        let token = r.enter()
        let mut name = ""
        while !r.at_end() {
          let u = r.read_tag()
          if u == @pbf.tag(1, @pbf.WIRE_LEN) {
            name = r.read_string()
          } else {
            r.skip(u)
          }
        }
        r.exit(token)
        res.fields.push(name)
      }
      15 if (t & 7) == @pbf.WIRE_LEN => {
        let start = r.read_len_start()
        res.features.push((start, r.pos()))
      }
      _ => r.skip(t)
    }
  }
}

///|
/// A `Value` message: the last of its fields that is set, else null.
fn esri_value(r : @pbf.Reader) -> @geom.Prop {
  let mut v : @geom.Prop = Null
  while !r.at_end() {
    let t = r.read_tag()
    v = match t {
      0x0a => Str(r.read_string())
      0x15 => Num(r.read_float().to_double())
      0x19 => Num(r.read_double())
      0x20 => Num(r.read_svarint32().to_double())
      0x28 | 0x38 => Num(r.read_varint64().to_double())
      0x30 => Num(r.read_int64().to_double())
      0x40 => Num(r.read_sint64().to_double())
      0x48 => Bool(r.read_bool())
      _ => {
        r.skip(t)
        v
      }
    }
  }
  v
}

///|
/// A `Geometry` message's part lengths and quantized coordinates (packed or not).
fn esri_pbf_geometry(
  r : @pbf.Reader,
  lengths : Array[Int32],
  values : Array[Int64],
) -> Unit {
  while !r.at_end() {
    let t = r.read_tag()
    if t == @pbf.tag(2, @pbf.WIRE_LEN) || t == @pbf.tag(3, @pbf.WIRE_LEN) {
      let token = r.enter()
      while !r.at_end() {
        if t >> 3 == 2 {
          lengths.push(r.read_varint32())
        } else {
          values.push(r.read_sint64())
        }
      }
      r.exit(token)
    } else if t == @pbf.tag(2, @pbf.WIRE_VARINT) {
      lengths.push(r.read_varint32())
    } else if t == @pbf.tag(3, @pbf.WIRE_VARINT) {
      values.push(r.read_sint64())
    } else {
      r.skip(t)
    }
  }
}

///|
/// Adds the geometry of `lengths` and `values` (`stride` values a position, each part's
/// first absolute and the rest deltas, as arcgis-pbf-parser reads them) to `shapes`;
/// false when the lengths ask for more values than there are.
fn esri_shape(
  res : EsriResult,
  stride : Int32,
  lengths : Array[Int32],
  values : Array[Int64],
  shapes : Shapes,
) -> Bool {
  let t = res.transform
  let x = (q : Int64) => {
    if res.quantized {
      q.to_double() * t[0] + t[2]
    } else {
      q.to_double()
    }
  }
  let y = (q : Int64) => {
    if !res.quantized {
      q.to_double()
    } else if res.upper_left {
      -q.to_double() * t[1] + t[3]
    } else {
      q.to_double() * t[1] + t[3]
    }
  }
  if res.geometry_type == 0 {
    guard values.length() >= stride else { return false }
    shapes.point(x(values[0]), y(values[1]))
    shapes.end_ring()
    shapes.end_part()
    shapes.end_member(Point)
    return true
  }
  let parts = []
  let mut at = 0
  for n in lengths {
    if n < 0 ||
      n.to_int64() * stride.to_int64() > (values.length() - at).to_int64() {
      return false
    }
    let part = Array(capacity=n * 2)
    let mut qx = 0L
    let mut qy = 0L
    for i in 0..<n {
      let k = at + i * stride
      if i == 0 {
        qx = values[k]
        qy = values[k + 1]
      } else {
        qx = qx + values[k]
        qy = qy + values[k + 1]
      }
      part.push(x(qx))
      part.push(y(qy))
    }
    at += n * stride
    parts.push(part)
  }
  match res.geometry_type {
    1 => {
      for part in parts {
        for c in part {
          shapes.coords.push(c)
        }
      }
      shapes.end_ring()
      shapes.end_part()
      shapes.end_member(MultiPoint)
    }
    2 => {
      for part in parts {
        for c in part {
          shapes.coords.push(c)
        }
        shapes.end_ring()
        shapes.end_part()
      }
      shapes.end_member(
        if parts.length() == 1 {
          LineString
        } else {
          MultiLineString
        },
      )
    }
    _ => esri_rings(parts, shapes)
  }
  true
}
