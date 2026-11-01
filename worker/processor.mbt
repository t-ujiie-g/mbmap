///|
/// Turns one style's tiles into `PackedTile`s, one entry per group of features
/// sharing the inputs their paint reads. Reuse one per worker: its buffers keep
/// their capacity.
pub struct TileProcessor {
  style : @style.Style
  out : PackedTile
  priv fill : @tess.FillTessellator
  priv line : @tess.LineTessellator
  priv fill_pool : Array[@tess.FillBuffers]
  priv line_pool : Array[@tess.LineBuffers]
  priv label_pool : Array[Labels]
  priv geometry : @mvt.Geometry
  priv inputs : Array[(Array[String], Bool)]
  priv mut error : String
}

///|
pub fn TileProcessor::new(style : @style.Style) -> TileProcessor {
  {
    style,
    out: PackedTile::new(),
    fill: @tess.FillTessellator::new(),
    line: @tess.LineTessellator::new(),
    fill_pool: [],
    line_pool: [],
    label_pool: [],
    geometry: @mvt.Geometry::new(),
    inputs: style.layers.map(paint_inputs),
    error: "",
  }
}

///|
/// A processor for the style whose JSON text is the UTF-8 `bytes`.
pub fn TileProcessor::from_utf8(
  bytes : BytesView,
) -> TileProcessor raise @style.StyleError {
  TileProcessor::new(@style.Style::parse(@utf8.decode_lossy(bytes)))
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
  !(a.kind is Symbol) &&
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
/// Packs every layer of the style drawing from tile `bytes` of `source` at zoom
/// `z` into `out`, in style order (layers out of their zoom range are skipped,
/// as MapLibre does). False on a malformed tile or an oversized result.
pub fn TileProcessor::process(
  self : TileProcessor,
  source : String,
  bytes : BytesView,
  z : Int32,
) -> Bool {
  // A GeoJSON source's columnar tile has one layer, which all its style layers use.
  let geojson = self.style.source(source) is Some({ kind: GeoJSON, .. })
  let mut tile = None
  let mut columns = None
  if geojson {
    columns = ColumnTile::parse(bytes)
    if columns is None {
      self.error = "malformed GeoJSON tile"
      return false
    }
  } else {
    tile = Some(
      @mvt.Tile::parse(bytes) catch {
        e => {
          self.error = "malformed tile: \{e.message()}"
          return false
        }
      },
    )
  }
  let features_of = (sl : @style.StyleLayer) => {
    match (tile, columns) {
      (Some(t), _) => t.layer(sl.source_layer).map(l => Features::Mvt(l))
      (_, Some(c)) => Some(Features::Columns(c))
      _ => None
    }
  }
  let style_layers = self.style.layers
  let zoom = z.to_double()
  let drawn = style_layers.map(sl => {
    sl.source == source &&
    !(sl.kind is (Background | Hillshade)) &&
    zoom >= sl.min_zoom.floor() &&
    zoom < sl.max_zoom &&
    features_of(sl) is Some(_)
  })
  let mut entries = 0
  for i, d in drawn {
    if d {
      entries += if grouped(self.inputs[i]) { MAX_GROUPS } else { 1 }
    }
  }
  self.out.begin(entries)
  // Ungrouped layers packed so far: (style layer, its single entry or -1).
  let done : Array[(Int32, Int32)] = []
  for index, sl in style_layers {
    guard drawn[index] && features_of(sl) is Some(layer) else { continue }
    let groups = Groups::new(self.inputs[index])
    if !groups.active &&
      done.search_by(d => same_geometry(style_layers[d.0], sl)) is Some(i) {
      if done[i].1 >= 0 {
        self.out.add_alias(index, done[i].1)
      }
      continue
    }
    let entries = self.out.layer_count()
    let ok = match sl.kind {
      Fill => self.fill_layer(index, sl, layer, zoom, groups)
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
    if layer.geom_type(i) is Polygon && passes(sl.filter, feature, zoom) {
      if !self.decode(layer, i) {
        return false
      }
      let g = self.geometry
      let out = self.fill_buffers(groups.of(feature))
      self.fill.add_polygons(g.coords[:], g.ring_ends[:], out)
    }
  }
  for g in 0..<groups.count() {
    let b = self.fill_buffers(g)
    if b.num_vertices() > 0 {
      if !self.out.add_fill(index, b, extent=layer.extent()) {
        return false
      }
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
      let out = self.line_buffers(groups.of(feature))
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
    }
  }
  for g in 0..<groups.count() {
    let b = self.line_buffers(g)
    if b.num_vertices() > 0 {
      if !self.out.add_line(index, b, extent=layer.extent()) {
        return false
      }
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
    if layer.geom_type(i) is Point && passes(sl.filter, feature, zoom) {
      if !self.decode(layer, i) {
        return false
      }
      let g = self.geometry
      @tess.add_points(
        g.coords[:g.num_points() * 2],
        self.line_buffers(groups.of(feature)),
        extent=layer.extent(),
      )
    }
  }
  for g in 0..<groups.count() {
    let b = self.line_buffers(g)
    if b.num_vertices() > 0 {
      if !self.out.add_circles(index, b, extent=layer.extent()) {
        return false
      }
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
