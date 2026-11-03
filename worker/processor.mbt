///|
/// Turns one style's tiles into `PackedTile`s (an entry per group of features
/// sharing their paint's inputs); reuse one per worker. `number` parses long JSON
/// numbers, `text_number` / `number_text` are the host's `Number` / `String`;
/// `ranges` holds feature-state layers' ranges (`feature_ranges`).
pub struct TileProcessor {
  style : @style.Style
  priv trig : @core.Trig
  out : PackedTile
  priv fill : @tess.FillTessellator
  priv line : @tess.LineTessellator
  priv extrusion : @tess.ExtrusionTessellator
  priv fill_pool : Array[@tess.FillBuffers]
  priv extrusion_pool : Array[@tess.ExtrusionBuffers]
  priv line_pool : Array[@tess.LineBuffers]
  priv gradient_pool : Array[GradientRows]
  priv label_pool : Array[Labels]
  priv geometry : @mvt.Geometry
  priv inputs : Array[(Array[String], Bool)]
  priv vertex_paint : Array[Array[@style.VertexPaint]]
  priv runs : Array[Int32]
  priv number : (BytesView) -> Double
  priv text_number : (String) -> Double
  priv number_text : (Double) -> String
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
  text_number~ : (String) -> Double = @style.js_number,
  number_text~ : (Double) -> String = Double::to_string,
  trig~ : @core.Trig = @core.Trig::moonbit(),
) -> TileProcessor {
  {
    style,
    trig,
    out: PackedTile::new(),
    fill: @tess.FillTessellator::new(),
    line: @tess.LineTessellator::new(trig~),
    extrusion: @tess.ExtrusionTessellator::new(),
    fill_pool: [],
    extrusion_pool: [],
    line_pool: [],
    gradient_pool: [],
    label_pool: [],
    geometry: @mvt.Geometry::new(),
    inputs: style.layers.map(l => {
      if per_vertex(l) {
        ([], false)
      } else {
        paint_inputs(l)
      }
    }),
    vertex_paint: style.layers.map(l => l.vertex_paint()),
    runs: [],
    number,
    text_number,
    number_text,
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
  text_number~ : (String) -> Double = @style.js_number,
  number_text~ : (Double) -> String = Double::to_string,
  trig~ : @core.Trig = @core.Trig::moonbit(),
) -> TileProcessor raise @style.StyleError {
  let json = parse_json(bytes, number) catch {
    e => raise Invalid(path="", "not JSON: \{e.message()}")
  }
  TileProcessor::new(
    @style.Style::from_json(json),
    number~,
    text_number~,
    number_text~,
    trig~,
  )
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
  (a.kind is (Fill | Circle | Heatmap) || a.same_line_layout(b))
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
  !(sl.kind is (Background | Hillshade | Raster)) &&
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
  // Ungrouped layers packed so far: (style layer, its single entry or -1, its runs).
  let done : Array[(Int32, Int32, Array[Int32])] = []
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
        if !self.write_paint(index, layer, done[i].2, zoom) {
          return false
        }
      }
      continue
    }
    self.runs.clear()
    let entries = self.out.layer_count()
    let ok = match sl.kind {
      Fill => self.fill_layer(index, sl, layer, zoom, groups)
      FillExtrusion => self.extrusion_layer(index, sl, layer, zoom, groups)
      Circle | Heatmap => self.circle_layer(index, sl, layer, zoom, groups)
      Symbol => self.symbol_layer(index, sl, layer, zoom, groups)
      _ => self.line_layer(index, sl, layer, zoom, groups)
    }
    if !ok {
      return false
    }
    if !groups.active {
      let entry = if self.out.layer_count() > entries { entries } else { -1 }
      done.push((index, entry, self.runs.copy()))
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
  let feature = self.feature_ref(layer)
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
      let edges = out.outline.length()
      let v0 = out.num_vertices()
      self.fill.add_polygons(g.coords[:], g.ring_ends[:], out)
      self.track(
        index,
        group,
        i,
        first,
        out.indices.length(),
        outline=(edges, out.outline.length()),
      )
      self.run(i, out.num_vertices() - v0)
    }
  }
  for g in 0..<groups.count() {
    let b = self.fill_buffers(g)
    if b.num_vertices() > 0 {
      let entry = self.out.layer_count()
      if !self.out.add_fill(index, b, extent=layer.extent()) ||
        !self.write_paint(index, layer, self.runs, zoom) {
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
  let feature = self.feature_ref(layer)
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
  let feature = self.feature_ref(layer)
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
      let v0 = out.num_vertices()
      @tess.add_points(
        g.coords[:g.num_points() * 2],
        out,
        extent=layer.extent(),
      )
      self.track(index, group, i, first, out.indices.length())
      self.run(i, out.num_vertices() - v0)
    }
  }
  for g in 0..<groups.count() {
    let b = self.line_buffers(g)
    if b.num_vertices() > 0 {
      let entry = self.out.layer_count()
      if !self.out.add_circles(index, b, extent=layer.extent()) ||
        !self.write_paint(index, layer, self.runs, zoom) {
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
/// Whether `sl`'s data-driven paint goes per vertex rather than by groups:
/// fills, lines, circles and heatmaps that do not read feature state.
fn per_vertex(sl : @style.StyleLayer) -> Bool {
  sl.kind is (Fill | Line | Circle | Heatmap) && !sl.reads_state()
}

///|
/// Records that feature `i` took the last `n` vertices of an ungrouped layer.
fn TileProcessor::run(self : TileProcessor, i : Int32, n : Int32) -> Unit {
  if n > 0 {
    self.runs.push(i)
    self.runs.push(n)
  }
}

///|
/// Writes the per-vertex paint of style layer `index` (docs/FORMATS.md, "Vertex
/// paint") for the last entry, whose vertices came from `runs` (feature,
/// vertex count) of `layer`; true when it has none. False without room.
fn TileProcessor::write_paint(
  self : TileProcessor,
  index : Int32,
  layer : Features,
  runs : Array[Int32],
  zoom : Double,
) -> Bool {
  let paint = self.vertex_paint[index]
  if paint.is_empty() {
    return true
  }
  let words = @style.vertex_paint_words(paint)
  let mut vertices = 0
  for k = 1; k < runs.length(); k = k + 2 {
    vertices += runs[k]
  }
  guard self.out.begin_paint(vertices * words) is Some(at) else { return false }
  let scratch = FixedArray::make(words, 0)
  let feature = self.feature_ref(layer)
  let mut w = at
  for k = 0; k + 1 < runs.length(); k = k + 2 {
    feature.index = runs[k]
    let mut o = 0
    for p in paint {
      o = p.encode(zoom, feature, scratch, o)
    }
    for x in scratch {
      self.out.store.set_u32(w, x)
      w += 4
    }
    let n = runs[k + 1] * words * 4
    self.out.store.repeat(w - words * 4, words * 4, n)
    w += n - words * 4
  }
  true
}
