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
  let order = self.feature_order(sl, layer, zoom, self.keys)
  // Runs of equal sort keys (key, first index, count), drawn across tiles in
  // key order as MapLibre's segments are.
  let runs = self.key_runs
  runs.clear()
  let feature = self.feature_ref(layer)
  for k in 0..<layer.length() {
    let i = order.map_or(k, o => o[k])
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
      if order is Some(_) && !groups.active {
        let key = self.keys[i]
        match runs.last() {
          Some(r) if r.0 == key => ()
          _ => runs.push((key, first))
        }
      }
      let v0 = out.num_vertices()
      if !self.may_fit(4 * g.num_points(), LINE_VERTEX_BYTES) {
        return false
      }
      @tess.add_points(
        g.coords[:g.num_points() * 2],
        out,
        extent=layer.extent(),
      )
      if !self.spend(
          out.num_vertices() - v0,
          LINE_VERTEX_BYTES,
          out.indices.length() - first,
        ) {
        return false
      }
      self.track(index, group, i, first, out.indices.length())
      self.run(i, out.num_vertices() - v0)
    }
  }
  for g in 0..<groups.count() {
    let b = self.line_buffers(g)
    if b.num_vertices() > 0 {
      let entry = self.out.layer_count()
      if !self.out.add_circles(index, b, extent=layer.extent()) ||
        !self.out.put_key_runs(runs, b.indices.length()) ||
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
