///|
/// Turns one style's tiles into `PackedTile`s, one entry per group of features
/// sharing the inputs their paint reads. Reuse one per worker: its buffers keep
/// their capacity. `number` parses the JSON numbers past
/// `@core.read_json_number`'s fast path (in a style or a query's filter).
/// For layers whose paint reads the feature state, `ranges` collects each
/// entry's features' index ranges (`feature_ranges`).
pub struct TileProcessor {
  style : @style.Style
  out : PackedTile
  priv fill : @tess.FillTessellator
  priv line : @tess.LineTessellator
  priv extrusion : @tess.ExtrusionTessellator
  priv fill_pool : Array[@tess.FillBuffers]
  priv extrusion_pool : Array[@tess.ExtrusionBuffers]
  priv line_pool : Array[@tess.LineBuffers]
  priv label_pool : Array[Labels]
  priv geometry : @mvt.Geometry
  priv inputs : Array[(Array[String], Bool)]
  priv number : (BytesView) -> Double
  priv state_layers : Array[Bool]
  priv range_pool : Array[Array[Int32]]
  priv ranges : @core.ByteWriter
  priv mut range_entries : Int32
  priv mut error : String
}

///|
pub fn TileProcessor::new(
  style : @style.Style,
  number~ : (BytesView) -> Double = @core.strconv_number,
) -> TileProcessor {
  {
    style,
    out: PackedTile::new(),
    fill: @tess.FillTessellator::new(),
    line: @tess.LineTessellator::new(),
    extrusion: @tess.ExtrusionTessellator::new(),
    fill_pool: [],
    extrusion_pool: [],
    line_pool: [],
    label_pool: [],
    geometry: @mvt.Geometry::new(),
    inputs: style.layers.map(paint_inputs),
    number,
    state_layers: style.layers.map(l => l.reads_state()),
    range_pool: [],
    ranges: @core.ByteWriter::new(),
    range_entries: 0,
    error: "",
  }
}

///|
/// A processor for the style whose JSON text is the UTF-8 `bytes`.
pub fn TileProcessor::from_utf8(
  bytes : BytesView,
  number~ : (BytesView) -> Double = @core.strconv_number,
) -> TileProcessor raise @style.StyleError {
  let json = parse_json(bytes, number) catch {
    e => raise Invalid(path="", "not JSON: \{e.message()}")
  }
  TileProcessor::new(@style.Style::from_json(json), number~)
}

///|
/// The JSON text `bytes`, its slow numbers parsed by `number`.
fn parse_json(
  bytes : BytesView,
  number : (BytesView) -> Double,
) -> Json raise @core.JsonError {
  @core.parse_json(bytes, slow_number=(s, e) => number(bytes[s:e]))
}

///|
/// Why the last `process` failed.
pub fn TileProcessor::error(self : TileProcessor) -> String {
  self.error
}

///|
/// `error` as UTF-8, for handing it to JS through linear memory.
pub fn TileProcessor::error_utf8(self : TileProcessor) -> Bytes {
  @utf8.encode(self.error)
}

///|
fn join_of(j : @style.Join) -> @tess.LineJoin {
  match j {
    Miter => Miter
    Bevel => Bevel
    Round => Round
  }
}

///|
fn cap_of(c : @style.Cap) -> @tess.LineCap {
  match c {
    Butt => Butt
    Square => Square
    Round => Round
  }
}

///|
/// Whether `feature` passes `filter` at tile zoom `zoom`.
fn passes(filter : @style.Expr?, feature : FeatureRef, zoom : Double) -> Bool {
  match filter {
    None => true
    Some(f) => f.eval(zoom, feature) is Bool(true)
  }
}

///|
/// Whether two layers produce identical buffers. Line extrusion is stored in
/// half widths, so layers that differ only in paint (like a road and its
/// casing) share one.
fn same_geometry(a : @style.StyleLayer, b : @style.StyleLayer) -> Bool {
  // Extrusions carry their heights in their vertices.
  !(a.kind is (Symbol | FillExtrusion)) &&
  a.kind == b.kind &&
  a.source == b.source &&
  a.source_layer == b.source_layer &&
  a.filter_id == b.filter_id &&
  (
    a.kind is Fill ||
    a.kind is Circle ||
    (
      a.join == b.join &&
      a.cap == b.cap &&
      a.miter_limit == b.miter_limit &&
      a.round_limit == b.round_limit
    )
  )
}

///|
/// The features of each source layer (by name) in tile `bytes` of `source` (a
/// vector tile, or a GeoJSON source's columnar tile, whose one layer all its
/// style layers use); None, with the error set, if the tile is malformed.
fn TileProcessor::read_tile(
  self : TileProcessor,
  source : String,
  bytes : BytesView,
) -> ((String) -> Features?)? {
  if self.style.source(source) is Some({ kind: GeoJSON, .. }) {
    guard ColumnTile::parse(bytes) is Some(c) else {
      self.error = "malformed GeoJSON tile"
      return None
    }
    return Some(_ => Some(Features::Columns(c)))
  }
  let tile = @mvt.Tile::parse(bytes) catch {
    e => {
      self.error = "malformed tile: \{e.message()}"
      return None
    }
  }
  Some(name => tile.layer(name).map(l => Features::Mvt(l)))
}

///|
/// Whether a tile of `source` at zoom `zoom` has geometry for `sl` (layers out
/// of their zoom range are skipped, as MapLibre does).
fn builds(sl : @style.StyleLayer, source : String, zoom : Double) -> Bool {
  sl.source == source &&
  !(sl.kind is (Background | Hillshade)) &&
  zoom >= sl.min_zoom.floor() &&
  zoom < sl.max_zoom
}

///|
/// Packs every layer of the style drawing from tile `bytes` of `source` at zoom
/// `z` into `out`, in style order (layers out of their zoom range are skipped,
/// as MapLibre does). False on a malformed tile or an oversized result.
pub fn TileProcessor::process(
  self : TileProcessor,
  source : String,
  bytes : BytesView,
  z : Int32,
) -> Bool {
  guard self.read_tile(source, bytes) is Some(features_of) else { return false }
  let style_layers = self.style.layers
  let zoom = z.to_double()
  let drawn = style_layers.map(sl => {
    builds(sl, source, zoom) && features_of(sl.source_layer) is Some(_)
  })
  let mut entries = 0
  for i, d in drawn {
    if d {
      entries += if grouped(self.inputs[i]) { MAX_GROUPS } else { 1 }
    }
  }
  self.out.begin(entries)
  self.ranges.clear()
  self.range_entries = 0
  for r in self.range_pool {
    r.clear()
  }
  // Ungrouped layers packed so far: (style layer, its single entry or -1).
  let done : Array[(Int32, Int32)] = []
  for index, sl in style_layers {
    guard drawn[index] && features_of(sl.source_layer) is Some(layer) else {
      continue
    }
    let groups = Groups::new(self.inputs[index])
    // A layer drawn feature by feature keeps its own buffers and ranges.
    if !groups.active &&
      !self.state_layers[index] &&
      done.search_by(d => {
        !self.state_layers[d.0] && same_geometry(style_layers[d.0], sl)
      })
      is Some(i) {
      if done[i].1 >= 0 {
        self.out.add_alias(index, done[i].1)
      }
      continue
    }
    let entries = self.out.layer_count()
    let ok = match sl.kind {
      Fill => self.fill_layer(index, sl, layer, zoom, groups)
      FillExtrusion => self.extrusion_layer(index, sl, layer, zoom, groups)
      Circle => self.circle_layer(index, sl, layer, zoom, groups)
      Symbol => self.symbol_layer(index, sl, layer, zoom, groups)
      _ => self.line_layer(index, sl, layer, zoom, groups)
    }
    if !ok {
      return false
    }
    if !groups.active {
      done.push(
        (index, if self.out.layer_count() > entries { entries } else { -1 }),
      )
    }
  }
  if self.out.overflowed() {
    self.error = "tile exceeds \{MAX_PACKED_BYTES} bytes"
    return false
  }
  true
}

///|
fn TileProcessor::decode(
  self : TileProcessor,
  layer : Features,
  i : Int32,
) -> Bool {
  match layer.load(i, self.geometry) {
    None => true
    Some(why) => {
      self.error = why
      false
    }
  }
}

///|
fn TileProcessor::fill_buffers(
  self : TileProcessor,
  g : Int32,
) -> @tess.FillBuffers {
  while self.fill_pool.length() <= g {
    self.fill_pool.push(@tess.FillBuffers::new())
  }
  self.fill_pool[g]
}

///|
fn TileProcessor::line_buffers(
  self : TileProcessor,
  g : Int32,
) -> @tess.LineBuffers {
  while self.line_pool.length() <= g {
    self.line_pool.push(@tess.LineBuffers::new())
  }
  self.line_pool[g]
}

///|
fn TileProcessor::fill_layer(
  self : TileProcessor,
  index : Int32,
  sl : @style.StyleLayer,
  layer : Features,
  zoom : Double,
  groups : Groups,
) -> Bool {
  for b in self.fill_pool {
    b.clear()
  }
  let feature = FeatureRef::new(layer)
  for i in 0..<layer.length() {
    feature.index = i
    // As MapLibre's fill bucket: lines are filled as rings too.
    if layer.geom_type(i) is (Polygon | LineString) &&
      passes(sl.filter, feature, zoom) {
      if !self.decode(layer, i) {
        return false
      }
      let g = self.geometry
      let group = groups.of(feature)
      let out = self.fill_buffers(group)
      let first = out.indices.length()
      self.fill.add_polygons(g.coords[:], g.ring_ends[:], out)
      self.track(index, group, i, first, out.indices.length())
    }
  }
  for g in 0..<groups.count() {
    let b = self.fill_buffers(g)
    if b.num_vertices() > 0 {
      let entry = self.out.layer_count()
      if !self.out.add_fill(index, b, extent=layer.extent()) {
        return false
      }
      self.flush_ranges(index, entry, g, layer)
      if groups.active {
        self.out.set_props(groups.props(g))
      }
    }
  }
  true
}

///|
fn TileProcessor::extrusion_buffers(
  self : TileProcessor,
  g : Int32,
) -> @tess.ExtrusionBuffers {
  while self.extrusion_pool.length() <= g {
    self.extrusion_pool.push(@tess.ExtrusionBuffers::new())
  }
  self.extrusion_pool[g]
}

///|
/// A number from `e` for `feature`, or 0.
fn number_at(e : @style.Expr, zoom : Double, feature : FeatureRef) -> Double {
  match e.eval(zoom, feature) {
    Num(n) => n
    _ => 0.0
  }
}

///|
/// Extrudes a fill-extrusion layer's polygons. Each feature's base and height
/// are taken at the tile's zoom and one deeper, which the renderer
/// interpolates between as MapLibre does for zoom-and-feature expressions.
fn TileProcessor::extrusion_layer(
  self : TileProcessor,
  index : Int32,
  sl : @style.StyleLayer,
  layer : Features,
  zoom : Double,
  groups : Groups,
) -> Bool {
  guard sl.extrusion is Some(e) else { return true }
  for b in self.extrusion_pool {
    b.clear()
  }
  let feature = FeatureRef::new(layer)
  let heights = FixedArray::make(@tess.EXTRUSION_HEIGHTS, 0.0)
  for i in 0..<layer.length() {
    feature.index = i
    if layer.geom_type(i) is (Polygon | LineString) &&
      passes(sl.filter, feature, zoom) {
      if !self.decode(layer, i) {
        return false
      }
      heights[0] = number_at(e.base, zoom, feature)
      heights[1] = number_at(e.base, zoom + 1.0, feature)
      heights[2] = number_at(e.height, zoom, feature)
      heights[3] = number_at(e.height, zoom + 1.0, feature)
      let g = self.geometry
      let group = groups.of(feature)
      let out = self.extrusion_buffers(group)
      let first = out.indices.length()
      self.extrusion.add_polygons(
        g.coords[:],
        g.ring_ends[:],
        heights,
        out,
        extent=layer.extent(),
      )
      self.track(index, group, i, first, out.indices.length())
    }
  }
  for g in 0..<groups.count() {
    let b = self.extrusion_buffers(g)
    if b.num_vertices() > 0 {
      let entry = self.out.layer_count()
      if !self.out.add_extrusion(index, b, extent=layer.extent()) {
        return false
      }
      self.flush_ranges(index, entry, g, layer)
      if groups.active {
        self.out.set_props(groups.props(g))
      }
    }
  }
  true
}

///|
fn TileProcessor::line_layer(
  self : TileProcessor,
  index : Int32,
  sl : @style.StyleLayer,
  layer : Features,
  zoom : Double,
  groups : Groups,
) -> Bool {
  for b in self.line_pool {
    b.clear()
  }
  let feature = FeatureRef::new(layer)
  let join = join_of(sl.join)
  let cap = cap_of(sl.cap)
  for i in 0..<layer.length() {
    feature.index = i
    let ty = layer.geom_type(i)
    if (ty is LineString || ty is Polygon) && passes(sl.filter, feature, zoom) {
      if !self.decode(layer, i) {
        return false
      }
      let g = self.geometry
      let group = groups.of(feature)
      let out = self.line_buffers(group)
      let first = out.indices.length()
      for r in 0..<g.num_rings() {
        self.line.add_line(
          g.coords[:],
          g.ring_start(r),
          g.ring_ends[r],
          out,
          join~,
          cap~,
          miter_limit=sl.miter_limit,
          round_limit=sl.round_limit,
        )
      }
      self.track(index, group, i, first, out.indices.length())
    }
  }
  for g in 0..<groups.count() {
    let b = self.line_buffers(g)
    if b.num_vertices() > 0 {
      let entry = self.out.layer_count()
      if !self.out.add_line(index, b, extent=layer.extent()) {
        return false
      }
      self.flush_ranges(index, entry, g, layer)
      if groups.active {
        self.out.set_props(groups.props(g))
      }
    }
  }
  true
}

///|
fn TileProcessor::circle_layer(
  self : TileProcessor,
  index : Int32,
  sl : @style.StyleLayer,
  layer : Features,
  zoom : Double,
  groups : Groups,
) -> Bool {
  for b in self.line_pool {
    b.clear()
  }
  let feature = FeatureRef::new(layer)
  for i in 0..<layer.length() {
    feature.index = i
    // As MapLibre's circle bucket: a circle at every vertex of any geometry.
    if !(layer.geom_type(i) is Unknown) && passes(sl.filter, feature, zoom) {
      if !self.decode(layer, i) {
        return false
      }
      let g = self.geometry
      let group = groups.of(feature)
      let out = self.line_buffers(group)
      let first = out.indices.length()
      @tess.add_points(
        g.coords[:g.num_points() * 2],
        out,
        extent=layer.extent(),
      )
      self.track(index, group, i, first, out.indices.length())
    }
  }
  for g in 0..<groups.count() {
    let b = self.line_buffers(g)
    if b.num_vertices() > 0 {
      let entry = self.out.layer_count()
      if !self.out.add_circles(index, b, extent=layer.extent()) {
        return false
      }
      self.flush_ranges(index, entry, g, layer)
      if groups.active {
        self.out.set_props(groups.props(g))
      }
    }
  }
  true
}

///|
/// The RGB unpacking of a `raster-dem` source's encoding.
fn unpack_of(e : @style.DemEncoding) -> @raster.Unpack {
  match e {
    Mapbox => @raster.Unpack::mapbox()
    Terrarium => @raster.Unpack::terrarium()
    Gsi => @raster.Unpack::gsi()
    Custom(r, g, b, base) => { r, g, b, base, gsi: false, }
  }
}

///|
/// A `size` x `size` RGBA tile `rgba` of the `raster-dem` source with index
/// `source` at zoom `z`, for its hillshade layers: the slopes
/// (`@raster.hillshade_slopes`), the border elevations (`@raster.dem_edges`) as
/// f64s, then every elevation as an f32 (no data as 0 m), for terrain. None (see
/// `error`) for another source or a malformed tile.
pub fn TileProcessor::dem_tile(
  self : TileProcessor,
  source : Int32,
  rgba : BytesView,
  size : Int32,
  z : Int32,
) -> Bytes? {
  guard source >= 0 &&
    source < self.style.sources.length() &&
    self.style.sources[source] is { kind: RasterDem, encoding, .. } else {
    self.error = "no DEM source \{source}"
    return None
  }
  if size <= 0 || size > 1024 || rgba.length() != size * size * 4 {
    self.error = "DEM tile is not \{size} x \{size} RGBA"
    return None
  }
  let elev = @raster.elevations(rgba, unpack_of(encoding))
  let w = @core.ByteWriter::new()
  for b in @raster.hillshade_slopes(elev, size, z) {
    w.u8(b.to_int())
  }
  for v in @raster.dem_edges(elev, size) {
    w.f64(v)
  }
  for v in elev {
    w.f32(if v.is_nan() { 0.0 } else { v })
  }
  Some(w.to_bytes())
}

///|
/// Notes that feature `i` of style layer `index` took indices `first..<end`
/// of group `group`'s buffers, if the layer is drawn feature by feature.
fn TileProcessor::track(
  self : TileProcessor,
  index : Int32,
  group : Int32,
  i : Int32,
  first : Int32,
  end : Int32,
) -> Unit {
  guard self.state_layers[index] && end > first else { return }
  while self.range_pool.length() <= group {
    self.range_pool.push([])
  }
  let r = self.range_pool[group]
  r.push(i)
  r.push(first)
  r.push(end - first)
}

///|
/// Writes the ranges of group `group` as those of packed entry `entry`
/// (docs/FORMATS.md, "Feature ranges") and empties the group's list.
fn TileProcessor::flush_ranges(
  self : TileProcessor,
  index : Int32,
  entry : Int32,
  group : Int32,
  layer : Features,
) -> Unit {
  guard self.state_layers[index] && group < self.range_pool.length() else {
    return
  }
  let sl = self.style.layers[index]
  let promoted = match self.style.source(sl.source) {
    Some(s) => s.promote_id.property(sl.source_layer)
    None => None
  }
  let r = self.range_pool[group]
  let w = self.ranges
  w.u32(entry)
  w.u32(r.length() / 3)
  for k = 0; k < r.length(); k = k + 3 {
    write_value(w, layer.id(r[k], promoted))
    w.u32(r[k + 1])
    w.u32(r[k + 2])
  }
  self.range_entries += 1
  r.clear()
}

///|
/// The feature ranges of the last tile processed (docs/FORMATS.md, "Feature
/// ranges"): where each feature's indices lie in the entries of layers whose
/// paint reads the feature state.
pub fn TileProcessor::feature_ranges(self : TileProcessor) -> Bytes {
  let w = @core.ByteWriter::new()
  w.u32(self.range_entries)
  for b in self.ranges.to_bytes() {
    w.u8(b.to_int())
  }
  w.to_bytes()
}
