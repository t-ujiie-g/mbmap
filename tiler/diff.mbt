// Ported from @maplibre/geojson-vt 6.3.0 (src/difference.ts and the updateable
// parts of src/geojsonvt.ts and src/convert.ts): MIT License, Copyright (c)
// 2025 MapLibre contributors, and ISC License, Copyright (c) 2024, Mapbox. See NOTICE.

///|
/// geojson-vt's `GeoJSONVTSourceDiff`, its features read into `table`: `add` ends
/// each feature to add over its rows (rows of a GeometryCollection's members), and
/// `update` each feature's change, in the order given.
pub(all) struct Diff {
  remove_all : Bool
  remove : Array[@geom.Prop?]
  table : @geom.Table
  add : Array[Int32]
  update : Array[FeatureDiff]
}

///|
/// geojson-vt's `GeoJSONVTFeatureDiff`: `geometry` the rows of the diff's table
/// holding `newGeometry` (None without one), then the property changes (an
/// added value None is `undefined`, which leaves the key out).
pub(all) struct FeatureDiff {
  id : @geom.Prop?
  geometry : (Int32, Int32)?
  remove_all_properties : Bool
  remove_properties : Array[String]
  add_properties : Array[(String, @geom.Prop?)]
}

///|
/// A diff in docs/FORMATS.md's "GeoJSON diff" form after its GeoJSON (read into
/// `table`, its features ending at `feature_ends`); None if malformed.
pub fn Diff::read(
  bytes : BytesView,
  table : @geom.Table,
  feature_ends : Array[Int32],
) -> Diff? {
  let r = @core.ByteReader::new(bytes)
  let remove_all = r.u8() != 0
  let count = (r : @core.ByteReader) => {
    let n = r.u32()
    if n > r.remaining() {
      r.fail()
      0
    } else {
      n
    }
  }
  let remove = []
  for _ in 0..<count(r) {
    remove.push(@geom.read_prop(r))
  }
  let adds = r.u32()
  guard r.ok() && adds >= 0 && adds <= feature_ends.length() else {
    return None
  }
  let mut next = adds
  let update = []
  for _ in 0..<count(r) {
    let id = @geom.read_prop(r)
    let flags = r.u8()
    let geometry = if (flags & 1) != 0 && next < feature_ends.length() {
      next += 1
      Some((@geom.start_of(feature_ends, next - 1), feature_ends[next - 1]))
    } else if (flags & 1) != 0 {
      r.fail()
      None
    } else {
      None
    }
    let remove_properties = []
    for _ in 0..<count(r) {
      remove_properties.push(r.utf8())
    }
    let add_properties = []
    for _ in 0..<count(r) {
      let k = r.utf8()
      add_properties.push((k, @geom.read_prop(r)))
    }
    update.push({
      id,
      geometry,
      remove_all_properties: (flags & 2) != 0,
      remove_properties,
      add_properties,
    })
  }
  guard r.ok() && r.done() && next == feature_ends.length() else { return None }
  Some({
    remove_all,
    remove,
    table,
    add: feature_ends[:adds].to_owned(),
    update,
  })
}
