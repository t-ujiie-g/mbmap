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
/// FeatureCollection.proto's field numbers: FeatureCollectionPBuffer's query result, a
/// QueryResult's feature result, a FeatureResult's fields, a Transform's and a Feature's.
const QUERY_RESULT = 2

///|
const FEATURE_RESULT = 1

///|
const ID_FIELD = 1

///|
const GEOMETRY_TYPE = 7

///|
const EXCEEDED = 9

///|
const HAS_Z = 10

///|
const HAS_M = 11

///|
const TRANSFORM = 12

///|
const FIELD = 13

///|
const FEATURE = 15

///|
const ORIGIN = 1

///|
const SCALE = 2

///|
const TRANSLATE = 3

///|
const ATTRIBUTE = 1

///|
const GEOMETRY = 2

///|
const LENGTHS = 2

///|
const COORDS = 3

///|
/// esriGeometryType's polygons: the only type read as rings (multipatches and
/// `esriGeometryTypeNone` give no geometry).
const POLYGON = 3

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
    if t == @pbf.tag(QUERY_RESULT, @pbf.WIRE_LEN) {
      let query = r.enter()
      while !r.at_end() {
        let u = r.read_tag()
        if u == @pbf.tag(FEATURE_RESULT, @pbf.WIRE_LEN) {
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
  let steps = Ref(0L)
  for range in res.features {
    let (start, end) = range
    r.reset(start, end)
    shapes.clear()
    let props = []
    let lengths = []
    values.clear()
    // The values a feature may hold before its positions pass the table's points.
    let room = (max_points - out.table.coords.length() / 2).to_int64() *
      stride.to_int64()
    while !r.at_end() {
      let t = r.read_tag()
      if t == @pbf.tag(ATTRIBUTE, @pbf.WIRE_LEN) {
        let token = r.enter()
        let v = esri_value(r)
        r.exit(token)
        let i = props.length()
        props.push(
          (if i < res.fields.length() { res.fields[i] } else { "" }, v),
        )
      } else if t == @pbf.tag(GEOMETRY, @pbf.WIRE_LEN) {
        let token = r.enter()
        esri_pbf_geometry(r, lengths, values, room)
        r.exit(token)
      } else {
        r.skip(t)
      }
      if values.length().to_int64() > room {
        fail(start, "too many points")
      }
    }
    if r.failed() {
      fail(r.pos(), "malformed protocol buffers")
    }
    props.retain(p => p.0 != "")
    if values.length() > 0 &&
      esri_shape(res, stride, lengths, values, shapes, steps) is Some(m) {
      fail(start, m)
    }
    if out.table.coords.length() / 2 + shapes.points() > max_points {
      fail(start, "too many points")
    }
    shapes.emit(out, props, None, id=esri_id(props, res.id_field), max_cells~)
    if property_limit(out, max_cells) is Some(m) {
      fail(start, m)
    }
  }
  (out.finish(), res.exceeded)
}

///|
/// Reads a `FeatureResult`'s fields into `res`, the features' byte ranges kept for later;
/// a field of another wire type than the proto's is skipped.
fn esri_result(r : @pbf.Reader, res : EsriResult) -> Unit {
  let varint = (n : Int32) => @pbf.tag(n, @pbf.WIRE_VARINT)
  let len = (n : Int32) => @pbf.tag(n, @pbf.WIRE_LEN)
  while !r.at_end() {
    let t = r.read_tag()
    if t == len(ID_FIELD) {
      res.id_field = Some(r.read_string())
    } else if t == varint(GEOMETRY_TYPE) {
      res.geometry_type = r.read_varint32()
    } else if t == varint(EXCEEDED) {
      res.exceeded = r.read_bool()
    } else if t == varint(HAS_Z) {
      res.has_z = r.read_bool()
    } else if t == varint(HAS_M) {
      res.has_m = r.read_bool()
    } else if t == len(TRANSFORM) {
      res.quantized = true
      let token = r.enter()
      esri_transform(r, res)
      r.exit(token)
    } else if t == len(FIELD) {
      let token = r.enter()
      let mut name = ""
      while !r.at_end() {
        let u = r.read_tag()
        if u == len(1) {
          name = r.read_string()
        } else {
          r.skip(u)
        }
      }
      r.exit(token)
      res.fields.push(name)
    } else if t == len(FEATURE) {
      let start = r.read_len_start()
      res.features.push((start, r.pos()))
    } else {
      r.skip(t)
    }
  }
}

///|
/// A `Transform`: the origin (0 upper left) and the scale and translate pairs.
fn esri_transform(r : @pbf.Reader, res : EsriResult) -> Unit {
  while !r.at_end() {
    let u = r.read_tag()
    if u == @pbf.tag(ORIGIN, @pbf.WIRE_VARINT) {
      res.upper_left = r.read_varint32() == 0
    } else if u == @pbf.tag(SCALE, @pbf.WIRE_LEN) ||
      u == @pbf.tag(TRANSLATE, @pbf.WIRE_LEN) {
      let at = if u >> 3 == SCALE { 0 } else { 2 }
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
    } else {
      r.skip(u)
    }
  }
}

///|
/// A `Value` message: the last of its fields that is set (string, float, double,
/// sint, uint, int64, uint64, sint64, bool), else null.
fn esri_value(r : @pbf.Reader) -> @geom.Prop {
  let mut v : @geom.Prop = Null
  while !r.at_end() {
    let t = r.read_tag()
    v = if t == @pbf.tag(1, @pbf.WIRE_LEN) {
      Str(r.read_string())
    } else if t == @pbf.tag(2, @pbf.WIRE_FIXED32) {
      Num(r.read_float().to_double())
    } else if t == @pbf.tag(3, @pbf.WIRE_FIXED64) {
      Num(r.read_double())
    } else if t == @pbf.tag(4, @pbf.WIRE_VARINT) {
      Num(r.read_svarint32().to_double())
    } else if t == @pbf.tag(5, @pbf.WIRE_VARINT) ||
      t == @pbf.tag(7, @pbf.WIRE_VARINT) {
      Num(r.read_varint64().to_double())
    } else if t == @pbf.tag(6, @pbf.WIRE_VARINT) {
      Num(r.read_int64().to_double())
    } else if t == @pbf.tag(8, @pbf.WIRE_VARINT) {
      Num(r.read_sint64().to_double())
    } else if t == @pbf.tag(9, @pbf.WIRE_VARINT) {
      Bool(r.read_bool())
    } else {
      r.skip(t)
      v
    }
  }
  v
}

///|
/// A `Geometry` message's part lengths and quantized coordinates (packed or not), the
/// coordinates read until `values` holds more than `room`.
fn esri_pbf_geometry(
  r : @pbf.Reader,
  lengths : Array[Int32],
  values : Array[Int64],
  room : Int64,
) -> Unit {
  let full = () => values.length().to_int64() > room
  while !r.at_end() && !full() {
    let t = r.read_tag()
    if t == @pbf.tag(LENGTHS, @pbf.WIRE_LEN) ||
      t == @pbf.tag(COORDS, @pbf.WIRE_LEN) {
      let token = r.enter()
      while !r.at_end() && !full() {
        if t >> 3 == LENGTHS {
          lengths.push(r.read_varint32())
        } else {
          values.push(r.read_sint64())
        }
      }
      r.exit(token)
    } else if t == @pbf.tag(LENGTHS, @pbf.WIRE_VARINT) {
      lengths.push(r.read_varint32())
    } else if t == @pbf.tag(COORDS, @pbf.WIRE_VARINT) {
      values.push(r.read_sint64())
    } else {
      r.skip(t)
    }
  }
}

///|
/// Adds the geometry of `lengths` and `values` (`stride` values a position, each part's
/// first absolute and the rest deltas, as arcgis-pbf-parser reads them) to `shapes`;
/// why not when the lengths ask for more values than there are, or telling rings apart
/// passes the read's `steps`. Geometry types beyond polygons add nothing.
fn esri_shape(
  res : EsriResult,
  stride : Int32,
  lengths : Array[Int32],
  values : Array[Int64],
  shapes : Shapes,
  steps : Ref[Int64],
) -> String? {
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
    guard values.length() >= stride else { return Some("malformed geometry") }
    shapes.point(x(values[0]), y(values[1]))
    shapes.end_ring()
    shapes.end_part()
    shapes.end_member(Point)
    return None
  }
  let parts = []
  let mut at = 0
  for n in lengths {
    if n < 0 ||
      n.to_int64() * stride.to_int64() > (values.length() - at).to_int64() {
      return Some("malformed geometry")
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
    1 => shapes.multipoint(parts.iter().flat_map(p => p.iter()).collect())
    2 => shapes.lines(parts)
    POLYGON =>
      if !esri_rings(parts, shapes, steps) {
        return Some("too many rings to tell apart")
      }
    _ => ()
  }
  None
}
