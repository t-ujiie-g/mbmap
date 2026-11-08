///|
/// Turns one style's tiles into `PackedTile`s (an entry per group of features sharing
/// their paint's inputs); reuse one per worker. `text_number`, `number_text`, `intl`: the
/// host's `Number`, `String`, `Intl`; `ranges`: feature-state layers' (`feature_ranges`).
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
  priv dash_pool : Array[Dashes]
  priv label_pool : Array[Labels]
  priv geometry : @mvt.Geometry
  priv place : @style.TileGeometry
  priv mut globe : Bool
  priv subdivider : @tess.Subdivider
  priv line_points : Array[Int32]
  priv scratch : @mvt.Geometry
  priv inputs : Array[(Array[String], Bool)]
  priv vertex_paint : Array[Array[@style.VertexPaint]]
  priv runs : Array[Int32]
  priv keys : Array[Double]
  priv key_runs : Array[(Double, Int32)]
  priv text_number : (String) -> Double
  priv number_text : (Double) -> String
  priv intl : @style.Intl
  priv state_layers : Array[Bool]
  priv range_pool : Array[Array[Int32]]
  priv ranges : @core.ByteWriter
  priv mut range_entries : Int32
  priv mut budget : Double
  priv mut error : String
}

///|
fn TileProcessor::new(
  style : @style.Style,
  text_number~ : (String) -> Double = @style.js_number,
  number_text~ : (Double) -> String = Double::to_string,
  trig~ : @core.Trig = @core.Trig::moonbit(),
  intl~ : @style.Intl = @style.Intl::fallback(),
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
    dash_pool: [],
    label_pool: [],
    geometry: @mvt.Geometry::new(),
    place: @style.TileGeometry::new(),
    globe: false,
    subdivider: @tess.Subdivider::new(),
    line_points: [],
    scratch: @mvt.Geometry::new(),
    inputs: style.layers.map(l => {
      if per_vertex(l) {
        ([], false)
      } else {
        paint_inputs(l)
      }
    }),
    vertex_paint: style.layers.map(l => l.vertex_paint()),
    runs: [],
    keys: [],
    key_runs: [],
    text_number,
    number_text,
    intl,
    state_layers: style.layers.map(l => l.reads_state()),
    range_pool: [],
    ranges: @core.ByteWriter::new(),
    range_entries: 0,
    budget: 0.0,
    error: "",
  }
}

///|
/// A processor for the style compiled by the main thread
/// (`@style.Style::to_compiled`).
fn TileProcessor::from_compiled(
  bytes : BytesView,
  text_number~ : (String) -> Double = @style.js_number,
  number_text~ : (Double) -> String = Double::to_string,
  trig~ : @core.Trig = @core.Trig::moonbit(),
  intl~ : @style.Intl = @style.Intl::fallback(),
) -> TileProcessor raise @style.StyleError {
  TileProcessor::new(
    @style.Style::from_compiled(bytes),
    text_number~,
    number_text~,
    trig~,
    intl~,
  )
}

///|
/// A processor for the style whose JSON text is the UTF-8 `bytes`, parsed as the
/// main thread does and passed through the compiled form, as display workers get it.
pub fn TileProcessor::from_utf8(
  bytes : BytesView,
  text_number~ : (String) -> Double = @style.js_number,
  number_text~ : (Double) -> String = Double::to_string,
  trig~ : @core.Trig = @core.Trig::moonbit(),
  intl~ : @style.Intl = @style.Intl::fallback(),
) -> TileProcessor raise @style.StyleError {
  let json = @core.parse_json(bytes) catch {
    e => raise Invalid(path="", "not JSON: \{e.message()}")
  }
  let style = @style.Style::from_json(json, strict=false)
  TileProcessor::from_compiled(
    style.to_compiled(),
    text_number~,
    number_text~,
    trig~,
    intl~,
  )
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
/// casing) share one; layers sorted by a key or dashed by feature keep their own.
fn same_geometry(a : @style.StyleLayer, b : @style.StyleLayer) -> Bool {
  // Extrusions carry their heights in their vertices.
  !(a.kind is (Symbol | FillExtrusion)) &&
  a.kind == b.kind &&
  a.source == b.source &&
  a.source_layer == b.source_layer &&
  a.filter_id == b.filter_id &&
  a.sort_key is None &&
  b.sort_key is None &&
  a.feature_dashes() is None &&
  b.feature_dashes() is None &&
  (a.kind is (Fill | Circle | Heatmap) || a.same_line_layout(b))
}

///|
/// The order `sl` takes `layer`'s features in: by its sort key (evaluated at
/// `zoom`), ties in tile order, as MapLibre's buckets sort them; None for tile
/// order. `keys` gets each feature's key.
fn TileProcessor::feature_order(
  self : TileProcessor,
  sl : @style.StyleLayer,
  layer : Features,
  zoom : Double,
  keys : Array[Double],
) -> FixedArray[Int32]? {
  guard sl.sort_key is Some(e) else { return None }
  let feature = self.feature_ref(layer)
  keys.clear()
  for i in 0..<layer.length() {
    feature.index = i
    keys.push(number_at(e, zoom, feature))
  }
  Some(@core.stable_order(keys[:]))
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
  !(sl.kind is (Background | Hillshade | ColorRelief | Raster)) &&
  zoom >= sl.min_zoom.floor() &&
  zoom < sl.max_zoom
}

///|
/// Packs every layer of the style drawing from tile `bytes` of `source` (tile `z`, `x`,
/// `y`) into `out`, in style order (layers out of their zoom range are skipped, as
/// MapLibre does). False on a malformed tile or an oversized result.
pub fn TileProcessor::process(
  self : TileProcessor,
  source : String,
  bytes : BytesView,
  z : Int32,
  x~ : Int32 = 0,
  y~ : Int32 = 0,
  globe~ : Bool = false,
) -> Bool {
  self.locate(z, x, y)
  self.globe = globe
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
    self.budget = MAX_PACKED_BYTES.to_double()
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
    return self.exceeds()
  }
  true
}

///|
/// Fails the tile as too big.
fn TileProcessor::exceeds(self : TileProcessor) -> Bool {
  self.error = "tile exceeds \{MAX_PACKED_BYTES} bytes"
  false
}

///|
/// Whether a layer's next feature, `points` that pack into at least `bytes`
/// each, may still fit a tile; checked before it is tessellated, so a hostile
/// tile stops before all of it is. Sets the error when not.
fn TileProcessor::may_fit(
  self : TileProcessor,
  points : Int32,
  bytes : Int32,
) -> Bool {
  points.to_double() * bytes.to_double() <= self.budget || self.exceeds()
}

///|
/// Takes a feature's `vertices` of `bytes` each and `indices` (at least 2 bytes
/// each) from the layer's budget; false, with the error set, past it.
fn TileProcessor::spend(
  self : TileProcessor,
  vertices : Int32,
  bytes : Int32,
  indices : Int32,
) -> Bool {
  self.budget -= vertices.to_double() * bytes.to_double() +
    2.0 * indices.to_double()
  self.budget >= 0.0 || self.exceeds()
}

///|
/// Sets the canonical tile the next features are read in.
fn TileProcessor::locate(
  self : TileProcessor,
  z : Int32,
  x : Int32,
  y : Int32,
) -> Unit {
  self.place.z = z
  self.place.x = x
  self.place.y = y
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
/// Whether `sl`'s data-driven paint goes per vertex rather than by groups:
/// fills, lines, circles and heatmaps that do not read feature state.
fn per_vertex(sl : @style.StyleLayer) -> Bool {
  sl.kind is (Fill | Line | Circle | Heatmap) && !sl.paints_by_group()
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
  // Their product may pass Int32: compare first.
  guard vertices <= MAX_PACKED_BYTES / 4 / @cmp.maximum(words, 1) &&
    self.out.begin_paint(vertices * words) is Some(at) else {
    return self.exceeds()
  }
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

///|
/// The extent a layer's geometry is packed in: on the globe every layer is
/// taken to `@core.TILE_EXTENT` first (`on_globe`), as MapLibre subdivides it.
fn TileProcessor::extent_of(self : TileProcessor, layer : Features) -> Int32 {
  if self.globe {
    @core.TILE_EXTENT
  } else {
    layer.extent()
  }
}

///|
/// On the globe, the decoded geometry in `@core.TILE_EXTENT` units, rounded as
/// MapLibre's `loadGeometry` scales it.
fn TileProcessor::on_globe(self : TileProcessor, layer : Features) -> Unit {
  let extent = layer.extent()
  if !self.globe || extent == @core.TILE_EXTENT {
    return
  }
  let k = @core.TILE_EXTENT.to_double() / extent.to_double()
  let c = self.geometry.coords
  for i in 0..<c.length() {
    c[i] = @core.js_round(c[i].to_double() * k).to_int()
  }
}

///|
/// The tile's place for subdivision on the globe, with `granularity` cells.
fn TileProcessor::subdivision(
  self : TileProcessor,
  granularity : Int32,
) -> (@tess.Subdivider, Int32, @core.TileId)? {
  guard self.globe else { return None }
  @core.TileId::new(self.place.z, self.place.x, self.place.y).map(tile => {
    (self.subdivider, granularity, tile)
  })
}
