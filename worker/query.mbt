// Rendered-feature queries of one tile as MapLibre GL JS 6.16.0 answers them
// (src/data/feature_index.ts and the `queryIntersectsFeature` of the fill,
// line, circle and fill-extrusion style layers), BSD-3-Clause, Copyright (c)
// 2020, MapLibre contributors. See NOTICE.

///|
/// A query of one tile (docs/FORMATS.md, "Query"). `zoom` is the camera's, at
/// which paint is evaluated; `pixels` are `TILE_EXTENT` units per CSS pixel;
/// `pitch_factor` is `max_pitch_scale_factor`; `matrix` maps `TILE_EXTENT`
/// units (and heights in world pixels, `meters` per meter) to clip space;
/// `polygon` is the query in `TILE_EXTENT` units and `camera` the same grown
/// to the camera (MapLibre's camera query geometry, for extrusions);
/// `layers` the style layers asked for (all if None); `symbols` the (layer,
/// feature) pairs of labels the main thread found under the query.
priv struct Query {
  zoom : Double
  pixels : Double
  pitch_factor : Double
  width : Double
  height : Double
  center_depth : Double
  meters : Double
  matrix : FixedArray[Double]
  polygon : @core.Line
  camera : @core.Line
  layers : Array[Int32]?
  symbols : Array[(Int32, Int32)]
  filter : @style.Expr?
}

///|
/// Most points of a query polygon, layers and labels; a request over them is
/// refused (AGENTS.md §8.2).
const MAX_QUERY_ITEMS : Int32 = 65536

///|
fn read_query(r : @core.ByteReader) -> Query? {
  let zoom = r.f64()
  let pixels = r.f64()
  let pitch_factor = r.f64()
  let width = r.f64()
  let height = r.f64()
  let center_depth = r.f64()
  let meters = r.f64()
  let matrix = FixedArray::makei(16, _ => r.f64())
  let n = r.u32()
  guard r.ok() && n >= 1 && n <= MAX_QUERY_ITEMS else { return None }
  let polygon = Array::makei(n, _ => (r.f64(), r.f64()))
  let m = r.u32()
  guard r.ok() && m >= 1 && m <= MAX_QUERY_ITEMS else { return None }
  let camera = Array::makei(m, _ => (r.f64(), r.f64()))
  let all = r.u8() == 1
  let l = r.u32()
  guard r.ok() && l >= 0 && l <= MAX_QUERY_ITEMS else { return None }
  let layers = Array::makei(l, _ => r.u32())
  let s = r.u32()
  guard r.ok() && s >= 0 && s <= MAX_QUERY_ITEMS else { return None }
  let symbols = Array::makei(s, _ => (r.u32(), r.u32()))
  let text = r.utf8()
  guard r.done() else { return None }
  let filter = if text == "" {
    None
  } else {
    Some(
      @style.compile(@json.parse(text), expected=BoolType, path="filter") catch {
        _ => return None
      },
    )
  }
  Some({
    zoom,
    pixels,
    pitch_factor,
    width,
    height,
    center_depth,
    meters,
    matrix,
    polygon,
    camera,
    layers: if all {
      None
    } else {
      Some(layers)
    },
    symbols,
    filter,
  })
}

///|
/// Clip space (x, y, z over w) and w of tile point (x, y) at height `z`.
fn project(
  m : FixedArray[Double],
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double, Double) {
  let w = m[3] * x + m[7] * y + m[11] * z + m[15]
  (
    (m[0] * x + m[4] * y + m[8] * z + m[12]) / w,
    (m[1] * x + m[5] * y + m[9] * z + m[13]) / w,
    (m[2] * x + m[6] * y + m[10] * z + m[14]) / w,
    w,
  )
}

///|
/// Screen point (CSS pixels) of `TILE_EXTENT` point `p`, and its clip w.
fn Query::screen(
  self : Query,
  p : (Double, Double),
) -> (Double, Double, Double) {
  let (x, y, _, w) = project(self.matrix, p.0, p.1, 0.0)
  ((x * 0.5 + 0.5) * self.width, (-y * 0.5 + 0.5) * self.height, w)
}

///|
/// Feature geometry loaded by `TileProcessor::decode`, as rings in `TILE_EXTENT`
/// units (`f` per feature unit).
fn rings_of(g : @mvt.Geometry, f : Double) -> Array[@core.Line] {
  Array::makei(g.num_rings(), r => {
    Array::makei(g.ring_ends[r] - g.ring_start(r), k => {
      let p = g.ring_start(r) + k
      (g.coords[p * 2].to_double() * f, g.coords[p * 2 + 1].to_double() * f)
    })
  })
}

///|
/// The box around `points`: min x, min y, max x, max y.
fn box_of(points : @core.Line) -> (Double, Double, Double, Double) {
  points.fold(
    init=(
      @double.infinity, @double.infinity, @double.neg_infinity, @double.neg_infinity,
    ),
    (b, p) => {
      (
        @cmp.minimum(b.0, p.0),
        @cmp.minimum(b.1, p.1),
        @cmp.maximum(b.2, p.0),
        @cmp.maximum(b.3, p.1),
      )
    },
  )
}

///|
/// Whether a feature with these rings is in MapLibre's index of the tile and
/// found by the query: some ring's box overlaps the tile, and one grown by
/// `pad` overlaps the query's box (or, for an extrusion, the camera polygon).
fn near_query(
  rings : Array[@core.Line],
  query : Query,
  pad : Double,
  extruded : Bool,
) -> Bool {
  let extent = @core.TILE_EXTENT.to_double()
  let boxes = rings
    .map(box_of)
    .filter(b => b.0 < extent && b.1 < extent && b.2 >= 0.0 && b.3 >= 0.0)
  if extruded {
    return boxes
      .iter()
      .any(b => {
        @core.polygon_hits_box(
          query.camera,
          b.0 - pad,
          b.1 - pad,
          b.2 + pad,
          b.3 + pad,
        )
      })
  }
  let (qx0, qy0, qx1, qy1) = box_of(query.polygon)
  boxes
  .iter()
  .any(b => {
    b.0 <= qx1 + pad && b.2 >= qx0 - pad && b.1 <= qy1 + pad && b.3 >= qy0 - pad
  })
}

///|
/// How far from the camera an extrusion with these rings, between heights
/// `base` and `top` (world pixels), meets the query (clip z; smaller is
/// nearer), or None if it does not (MapLibre's `checkIntersection`).
fn extrusion_hit(
  query : Query,
  rings : Array[@core.Line],
  base : Double,
  top : Double,
) -> Double? {
  let m = query.matrix
  let q = query.polygon.map(p => {
    let (x, y, _, _) = project(m, p.0, p.1, 0.0)
    (x, y)
  })
  let lift = (z : Double) => {
    rings.map(ring => ring.map(p => project(m, p.0, p.1, z)))
  }
  let bases = lift(base)
  let tops = lift(top)
  let flat = (r : Array[(Double, Double, Double, Double)]) => {
    r.map(p => (p.0, p.1))
  }
  let mut closest = @double.infinity
  if @core.polygon_hits_polygons(q, tops.map(flat)) {
    closest = face_distance(q, tops[0])
  }
  for r, ring in tops {
    for k in 0..<(ring.length() - 1) {
      let face = [ring[k], ring[k + 1], bases[r][k + 1], bases[r][k], ring[k]]
      if @core.polygon_hits_polygon(q, flat(face)) {
        closest = @cmp.minimum(closest, face_distance(q, face))
      }
    }
  }
  if closest == @double.infinity {
    None
  } else {
    Some(closest)
  }
}

///|
/// MapLibre's `getIntersectionDistance`: for a point, the depth where it meets
/// the face's plane; for a box, the face's nearest corner.
fn face_distance(
  q : @core.Line,
  face : Array[(Double, Double, Double, Double)],
) -> Double {
  if q.length() != 1 {
    return face.iter().map(p => p.2).fold(init=@double.infinity, @cmp.minimum)
  }
  guard face.length() > 0 else { return @double.infinity }
  let a = face[0]
  let mut i = 1
  while i < face.length() && face[i].0 == a.0 && face[i].1 == a.1 {
    i += 1
  }
  guard i < face.length() else { return @double.infinity }
  let b = face[i]
  let p = q[0]
  for c in face[i + 1:] {
    let (abx, aby) = (b.0 - a.0, b.1 - a.1)
    let (acx, acy) = (c.0 - a.0, c.1 - a.1)
    let (apx, apy) = (p.0 - a.0, p.1 - a.1)
    let ab_ab = abx * abx + aby * aby
    let ab_ac = abx * acx + aby * acy
    let ac_ac = acx * acx + acy * acy
    let ap_ab = apx * abx + apy * aby
    let ap_ac = apx * acx + apy * acy
    let denom = ab_ab * ac_ac - ab_ac * ab_ac
    let v = (ac_ac * ap_ab - ab_ac * ap_ac) / denom
    let w = (ab_ab * ap_ac - ab_ac * ap_ab) / denom
    let distance = a.2 * (1.0 - v - w) + b.2 * v + c.2 * w
    if !distance.is_nan() && !distance.is_inf() {
      return distance
    }
  }
  @double.infinity
}

///|
/// Whether feature `i` of `layer`, drawn by `sl`, meets the query; for an
/// extrusion, how far away.
fn TileProcessor::hit(
  self : TileProcessor,
  query : Query,
  pad : Double,
  sl : @style.StyleLayer,
  layer : Features,
  feature : FeatureRef,
) -> Double? {
  // MapLibre's buckets index every feature of these layers, whatever its type.
  guard !(layer.geom_type(feature.index) is Unknown) &&
    self.decode(layer, feature.index) else {
    return None
  }
  let rings = rings_of(
    self.geometry,
    @core.TILE_EXTENT.to_double() / layer.extent().to_double(),
  )
  let zoom = query.zoom
  let q = query.polygon
  guard near_query(rings, query, pad, sl.kind is FillExtrusion) else {
    return None
  }
  match sl.kind {
    Fill =>
      if @core.polygon_hits_polygons(q, rings) {
        Some(@double.not_a_number)
      } else {
        None
      }
    Line => {
      let half = query.pixels / 2.0 * number_at(sl.width, zoom, feature)
      if @core.polygon_hits_lines(q, rings, half) {
        Some(@double.not_a_number)
      } else {
        None
      }
    }
    // `circle-pitch-alignment: viewport`, `circle-pitch-scale: map`: compared
    // on screen, the size scaled by the point's distance like the circle.
    Circle => {
      let size = number_at(sl.radius, zoom, feature) +
        number_at(sl.stroke_width, zoom, feature)
      let screen = q.map(p => {
        let (x, y, _) = query.screen(p)
        (x, y)
      })
      for ring in rings {
        for p in ring {
          let (x, y, w) = query.screen(p)
          if @core.polygon_hits_point(
              screen,
              (x, y),
              size * query.center_depth / w,
            ) {
            return Some(@double.not_a_number)
          }
        }
      }
      None
    }
    FillExtrusion => {
      guard sl.extrusion is Some(e) else { return None }
      extrusion_hit(
        query,
        rings,
        number_at(e.base, zoom, feature) * query.meters,
        number_at(e.height, zoom, feature) * query.meters,
      )
    }
    _ => None
  }
}

///|
/// The tile's query padding in CSS pixels (MapLibre's `Tile.queryPadding`):
/// the most any feature reaches beyond its geometry, half a line's width or a
/// circle's radius and stroke, at camera zoom `zoom`.
fn TileProcessor::query_padding(
  self : TileProcessor,
  source : String,
  tile_zoom : Double,
  zoom : Double,
  features_of : (String) -> Features?,
) -> Double {
  let mut pad = 0.0
  for sl in self.style.layers {
    guard sl.kind is (Line | Circle) &&
      builds(sl, source, tile_zoom) &&
      features_of(sl.source_layer) is Some(layer) else {
      continue
    }
    let feature = FeatureRef::new(layer)
    for i in 0..<layer.length() {
      feature.index = i
      if passes(sl.filter, feature, tile_zoom) {
        let reach = match sl.kind {
          Line => number_at(sl.width, zoom, feature) / 2.0
          _ =>
            number_at(sl.radius, zoom, feature) +
            number_at(sl.stroke_width, zoom, feature)
        }
        pad = @cmp.maximum(pad, reach)
      }
    }
  }
  pad
}

///|
/// Answers `request` (docs/FORMATS.md, "Query") about tile `bytes` of `source`
/// at zoom `z`: the features of each layer asked for that meet the query, last
/// drawn first, then the labels named, as feature records ("Query result").
/// None, with the error set, if the tile or the request is malformed.
pub fn TileProcessor::query(
  self : TileProcessor,
  source : String,
  bytes : BytesView,
  z : Int32,
  request : BytesView,
) -> Bytes? {
  guard read_query(@core.ByteReader::new(request)) is Some(query) else {
    self.error = "malformed query"
    return None
  }
  guard self.read_tile(source, bytes) is Some(features_of) else { return None }
  let tile_zoom = z.to_double()
  let w = @core.ByteWriter::new()
  let hits = []
  let pad = query.pitch_factor *
    self.query_padding(source, tile_zoom, query.zoom, features_of) *
    query.pixels
  let (cx0, cy0, cx1, cy1) = box_of(query.camera)
  let extent = @core.TILE_EXTENT.to_double()
  let in_tile = cx0 - pad < extent &&
    cx1 + pad > 0.0 &&
    cy0 - pad < extent &&
    cy1 + pad > 0.0
  for index, sl in self.style.layers {
    if !in_tile || (query.layers is Some(ls) && !ls.contains(index)) {
      continue
    }
    guard !(sl.kind is Symbol) &&
      builds(sl, source, tile_zoom) &&
      features_of(sl.source_layer) is Some(layer) else {
      continue
    }
    let feature = FeatureRef::new(layer)
    for k in 0..<layer.length() {
      feature.index = layer.length() - 1 - k
      if !passes(sl.filter, feature, tile_zoom) ||
        !passes(query.filter, feature, tile_zoom) {
        continue
      }
      if self.hit(query, pad, sl, layer, feature) is Some(distance) {
        hits.push((index, feature.index, distance, layer))
      }
    }
  }
  for s in query.symbols {
    let (index, i) = s
    guard index >= 0 &&
      index < self.style.layers.length() &&
      features_of(self.style.layers[index].source_layer) is Some(layer) &&
      i >= 0 &&
      i < layer.length() else {
      continue
    }
    let feature = FeatureRef::new(layer)
    feature.index = i
    if passes(query.filter, feature, tile_zoom) {
      hits.push((index, i, @double.not_a_number, layer))
    }
  }
  w.u32(hits.length())
  for h in hits {
    let (index, i, distance, layer) = h
    w.u32(index)
    w.u32(i)
    w.f64(distance)
    if !self.write_feature(w, layer, i) {
      return None
    }
  }
  Some(w.to_bytes())
}

///|
/// Every feature of `source_layer` (any, for a GeoJSON source) in tile `bytes`
/// of `source` that passes `filter` (JSON, or "" for none) at zoom `z`, as
/// feature records (docs/FORMATS.md, "Query result"; layer -1). None, with the
/// error set, if the tile or the filter is malformed.
pub fn TileProcessor::source_features(
  self : TileProcessor,
  source : String,
  bytes : BytesView,
  z : Int32,
  source_layer : String,
  filter : String,
) -> Bytes? {
  let compiled = if filter == "" {
    None
  } else {
    Some(
      @style.compile(@json.parse(filter), expected=BoolType, path="filter") catch {
        _ => {
          self.error = "malformed filter"
          return None
        }
      },
    )
  }
  guard self.read_tile(source, bytes) is Some(features_of) else { return None }
  let w = @core.ByteWriter::new()
  guard features_of(source_layer) is Some(layer) else {
    w.u32(0)
    return Some(w.to_bytes())
  }
  let feature = FeatureRef::new(layer)
  let picked = []
  for i in 0..<layer.length() {
    feature.index = i
    if passes(compiled, feature, z.to_double()) {
      picked.push(i)
    }
  }
  w.u32(picked.length())
  for i in picked {
    w.u32(-1)
    w.u32(i)
    w.f64(@double.not_a_number)
    if !self.write_feature(w, layer, i) {
      return None
    }
  }
  Some(w.to_bytes())
}

///|
/// Feature `i` of `layer` as a record (docs/FORMATS.md, "Query result"): its
/// id, geometry type, extent, rings and properties. False if its geometry is
/// malformed.
fn TileProcessor::write_feature(
  self : TileProcessor,
  w : @core.ByteWriter,
  layer : Features,
  i : Int32,
) -> Bool {
  if !self.decode(layer, i) {
    return false
  }
  match layer {
    Mvt(l) =>
      match l.id(i) {
        Some(id) => write_value(w, Num(id.to_double()))
        None => w.u8(@core.PROP_NULL)
      }
    Columns(_) => w.u8(@core.PROP_NULL)
  }
  w.u8(
    match layer.geom_type(i) {
      Point => 1
      LineString => 2
      Polygon => 3
      Unknown => 0
    },
  )
  w.u32(layer.extent())
  let g = self.geometry
  w.u32(g.num_rings())
  for r in 0..<g.num_rings() {
    w.u32(g.ring_ends[r] - g.ring_start(r))
  }
  for c in g.coords[:g.num_points() * 2] {
    w.u32(c)
  }
  match layer {
    Mvt(l) => {
      // As a JS object: a repeated key keeps its first place and last value.
      let props : Array[(String, @mvt.Value)] = []
      for k in 0..<l.tag_count(i) {
        let (key, value) = l.tag(i, k)
        match props.search_by(p => p.0 == key) {
          Some(at) => props[at] = (key, value)
          None => props.push((key, value))
        }
      }
      w.u32(props.length())
      for p in props {
        w.utf8(p.0)
        write_value(w, style_value(p.1))
      }
    }
    Columns(c) => {
      let present = []
      for k, key in c.keys {
        if c.values[k][i] is Some(v) {
          present.push((key, v))
        }
      }
      w.u32(present.length())
      for kv in present {
        w.utf8(kv.0)
        write_value(w, kv.1)
      }
    }
  }
  true
}
