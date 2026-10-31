///|
/// Turns tiles of one style's vector sources into `PackedTile`s. Reuse one
/// instance per worker: its tessellators and buffers keep their capacity.
/// Features of a layer whose paint reads feature data are split into groups
/// that share those inputs (see `MAX_GROUPS`); each group becomes an entry
/// carrying the shared properties, so the renderer evaluates paint per group.
pub struct TileProcessor {
  style : @style.Style
  out : PackedTile
  priv fill : @tess.FillTessellator
  priv line : @tess.LineTessellator
  priv fill_pool : Array[@tess.FillBuffers]
  priv line_pool : Array[@tess.LineBuffers]
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
  a.kind == b.kind &&
  a.source == b.source &&
  a.source_layer == b.source_layer &&
  a.filter == b.filter &&
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
/// Most groups per layer and tile; features beyond are drawn with the last
/// group's paint.
pub const MAX_GROUPS : Int32 = 64

///|
/// Feature inputs of a layer's paint: property names, and whether it reads
/// the geometry type.
fn paint_inputs(sl : @style.StyleLayer) -> (Array[String], Bool) {
  let keys = []
  let mut geometry = false
  let exprs = match sl.kind {
    Line => [sl.color, sl.opacity, sl.width]
    Circle =>
      [
        sl.color,
        sl.opacity,
        sl.radius,
        sl.stroke_width,
        sl.stroke_color,
        sl.stroke_opacity,
      ]
    _ => [sl.color, sl.opacity]
  }
  for e in exprs {
    let (ks, g) = e.feature_inputs()
    for k in ks {
      if !keys.contains(k) {
        keys.push(k)
      }
    }
    geometry = geometry || g
  }
  (keys, geometry)
}

///|
/// A layer's split of features by the values its paint reads; `active` is
/// false when the paint reads none, so every feature goes to group 0.
priv struct Groups {
  keys : Array[String]
  geometry : Bool
  active : Bool
  values : Array[Array[@style.Value?]]
  scratch : Array[@style.Value?]
}

///|
fn Groups::new(inputs : (Array[String], Bool)) -> Groups {
  {
    keys: inputs.0,
    geometry: inputs.1,
    active: grouped(inputs),
    values: [],
    scratch: [],
  }
}

///|
fn grouped(inputs : (Array[String], Bool)) -> Bool {
  inputs.0.length() > 0 || inputs.1
}

///|
/// The group of `feature` (at its current index), creating it if new.
fn Groups::of(self : Groups, feature : FeatureRef) -> Int32 {
  if !self.active {
    return 0
  }
  let s = self.scratch
  s.clear()
  for k in self.keys {
    s.push(@style.FeatureContext::property(feature, k))
  }
  if self.geometry {
    s.push(Some(Str(@style.FeatureContext::geometry_type(feature))))
  }
  for g, v in self.values {
    if v == s {
      return g
    }
  }
  if self.values.length() >= MAX_GROUPS {
    return MAX_GROUPS - 1
  }
  self.values.push(s.copy())
  self.values.length() - 1
}

///|
fn json_of(v : @style.Value) -> Json {
  match v {
    Num(n) => Json::number(n)
    Str(s) => Json::string(s)
    Bool(b) => Json::boolean(b)
    _ => Json::null()
  }
}

///|
/// Group `g`'s shared inputs as a JSON object: properties by name (absent
/// ones omitted, so `has` stays correct) and the geometry type as `@core.GEOMETRY_TYPE_KEY`.
fn Groups::props_json(self : Groups, g : Int32) -> Bytes {
  let obj : Map[String, Json] = Map([])
  let v = self.values[g]
  for i, k in self.keys {
    if v[i] is Some(x) {
      obj[k] = json_of(x)
    }
  }
  if self.geometry && v[self.keys.length()] is Some(Str(t)) {
    obj[@core.GEOMETRY_TYPE_KEY] = Json::string(t)
  }
  @utf8.encode(Json::object(obj).stringify())
}

///|
/// The number of groups to emit: at least one, even for an ungrouped layer.
fn Groups::count(self : Groups) -> Int32 {
  @cmp.maximum(1, self.values.length())
}

///|
/// Decodes `bytes`, a tile of source `source` at zoom `z`, and packs every fill
/// and line layer of the style that draws from it into `out`, in style order.
/// An ungrouped layer with the same geometry as an earlier ungrouped one
/// points at its buffers. Like MapLibre, a layer is skipped when `z` is
/// outside its zoom range. Returns false on a malformed tile or an oversized
/// result (see `error`).
pub fn TileProcessor::process(
  self : TileProcessor,
  source : String,
  bytes : BytesView,
  z : Int32,
) -> Bool {
  let tile = @mvt.Tile::parse(bytes) catch {
    e => {
      self.error = "malformed tile: \{e.message()}"
      return false
    }
  }
  let style_layers = self.style.layers
  let zoom = z.to_double()
  let drawn = style_layers.map(sl => {
    sl.source == source &&
    !(sl.kind is Background) &&
    zoom >= sl.min_zoom.floor() &&
    zoom < sl.max_zoom &&
    tile.layer(sl.source_layer) is Some(_)
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
    guard drawn[index] && tile.layer(sl.source_layer) is Some(layer) else {
      continue
    }
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
  layer : @mvt.Layer,
  i : Int32,
) -> Bool {
  if layer.decode_geometry(i, self.geometry) {
    return true
  }
  let why = match self.geometry.error() {
    Some(e) => e.message()
    None => "unknown"
  }
  self.error = "malformed geometry in \{layer.name}[\{i}]: \{why}"
  false
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
  layer : @mvt.Layer,
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
      if !self.out.add_fill(index, b, extent=layer.extent) {
        return false
      }
      if groups.active {
        self.out.set_props(groups.props_json(g))
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
  layer : @mvt.Layer,
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
      if !self.out.add_line(index, b, extent=layer.extent) {
        return false
      }
      if groups.active {
        self.out.set_props(groups.props_json(g))
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
  layer : @mvt.Layer,
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
        extent=layer.extent,
      )
    }
  }
  for g in 0..<groups.count() {
    let b = self.line_buffers(g)
    if b.num_vertices() > 0 {
      if !self.out.add_circles(index, b, extent=layer.extent) {
        return false
      }
      if groups.active {
        self.out.set_props(groups.props_json(g))
      }
    }
  }
  true
}
