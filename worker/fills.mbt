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
  let order = self.feature_order(sl, layer, zoom, self.keys)
  let feature = self.feature_ref(layer)
  for k in 0..<layer.length() {
    let i = order.map_or(k, o => o[k])
    feature.index = i
    // As MapLibre's fill bucket: lines are filled as rings too.
    if layer.geom_type(i) is (Polygon | LineString) &&
      passes(sl.filter, feature, zoom) {
      if !self.decode(layer, i) {
        return false
      }
      self.on_globe(layer)
      let g = self.geometry
      let group = groups.of(feature)
      let out = self.fill_buffers(group)
      let first = out.indices.length()
      let edges = out.outline.length()
      let v0 = out.num_vertices()
      if !self.may_fit(g.num_points(), FILL_VERTEX_BYTES) {
        return false
      }
      self.fill.add_polygons(
        g.coords[:],
        g.ring_ends[:],
        out,
        subdivide?=self.subdivision(@tess.fill_granularity(self.place.z)),
      )
      if !self.spend(
          out.num_vertices() - v0,
          FILL_VERTEX_BYTES,
          out.indices.length() - first + out.outline.length() - edges,
        ) {
        return false
      }
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
      if !self.out.add_fill(index, b, extent=self.extent_of(layer)) ||
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
      self.on_globe(layer)
      let g = self.geometry
      let group = groups.of(feature)
      let out = self.extrusion_buffers(group)
      let first = out.indices.length()
      let v0 = out.num_vertices()
      if !self.may_fit(g.num_points(), @core.EXTRUSION_VERTEX_BYTES) {
        return false
      }
      self.extrusion.add_polygons(
        g.coords[:],
        g.ring_ends[:],
        heights,
        out,
        extent=self.extent_of(layer),
        subdivide?=self.subdivision(@tess.fill_granularity(self.place.z)),
      )
      if !self.spend(
          out.num_vertices() - v0,
          @core.EXTRUSION_VERTEX_BYTES,
          out.indices.length() - first,
        ) {
        return false
      }
      self.track(index, group, i, first, out.indices.length())
    }
  }
  for g in 0..<groups.count() {
    let b = self.extrusion_buffers(g)
    if b.num_vertices() > 0 {
      let entry = self.out.layer_count()
      if !self.out.add_extrusion(index, b, extent=self.extent_of(layer)) {
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
