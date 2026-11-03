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
  for r in self.gradient_pool {
    r.clear()
  }
  let feature = self.feature_ref(layer)
  let join = join_of(sl.join)
  let cap = cap_of(sl.cap)
  let gradient = sl.gradient is Some(_)
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
      let v0 = out.num_vertices()
      let clip = if gradient { clip_of(feature) } else { (0.0, 1.0) }
      for r in 0..<g.num_rings() {
        let before = out.num_vertices()
        self.line.add_line(
          g.coords[:],
          g.ring_start(r),
          g.ring_ends[r],
          out,
          join~,
          cap~,
          miter_limit=sl.miter_limit,
          round_limit=sl.round_limit,
          dashed=sl.line_distances(),
          progress=gradient,
          extent=layer.extent(),
        )
        if gradient && out.num_vertices() > before {
          self
          .gradient_rows(group)
          .add(
            out.num_vertices() - before,
            clip,
            ring_length(g.coords, g.ring_start(r), g.ring_ends[r]) /
            layer.extent().to_double(),
          )
        }
      }
      self.track(index, group, i, first, out.indices.length())
      self.run(i, out.num_vertices() - v0)
    }
  }
  for g in 0..<groups.count() {
    let b = self.line_buffers(g)
    if b.num_vertices() > 0 {
      let entry = self.out.layer_count()
      if !self.out.add_line(index, b, extent=layer.extent()) ||
        (gradient && !self.out.put_progress(b, self.gradient_rows(g))) ||
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
fn TileProcessor::gradient_rows(
  self : TileProcessor,
  g : Int32,
) -> GradientRows {
  while self.gradient_pool.length() <= g {
    self.gradient_pool.push(GradientRows::new())
  }
  self.gradient_pool[g]
}

///|
/// The properties a GeoJSON source's line metrics add (`@tiler.CLIP_START`
/// and `CLIP_END`; the worker does not import the tiler).
const CLIP_START : String = "geojsonvt_clip_start"

///|
const CLIP_END : String = "geojsonvt_clip_end"

///|
/// Where a feature lies along its line (a GeoJSON source's line metrics);
/// all of it without them.
fn clip_of(feature : FeatureRef) -> (Double, Double) {
  let prop = (k : String) => @style.FeatureContext::property(feature, k)
  match (prop(CLIP_START), prop(CLIP_END)) {
    (Some(Num(a)), Some(Num(b))) => (a, b)
    _ => (0.0, 1.0)
  }
}

///|
/// The length of the line through points `[start, end)` of `coords`.
fn ring_length(coords : Array[Int32], start : Int32, end : Int32) -> Double {
  let mut total = 0.0
  for i in (start + 1)..<end {
    let dx = (coords[i * 2] - coords[i * 2 - 2]).to_double()
    let dy = (coords[i * 2 + 1] - coords[i * 2 - 1]).to_double()
    total += (dx * dx + dy * dy).sqrt()
  }
  total
}

///|
/// A gradient line layer's rows (MapLibre's `lineClipsArray`): each vertex's
/// row, each row's start and end along its line, and the longest line in tiles.
priv struct GradientRows {
  rows : Array[Int32]
  clips : Array[Double]
  mut longest : Double
}

///|
fn GradientRows::new() -> GradientRows {
  { rows: [], clips: [], longest: 0.0, }
}

///|
fn GradientRows::clear(self : GradientRows) -> Unit {
  self.rows.clear()
  self.clips.clear()
  self.longest = 0.0
}

///|
/// A line of `vertices` vertices lying from `clip.0` to `clip.1` along its
/// whole, `length` tiles long, as a row of its own.
fn GradientRows::add(
  self : GradientRows,
  vertices : Int32,
  clip : (Double, Double),
  length : Double,
) -> Unit {
  let row = self.clips.length() / 2
  for _ in 0..<vertices {
    self.rows.push(row)
  }
  self.clips.push(clip.0)
  self.clips.push(clip.1)
  self.longest = @cmp.maximum(self.longest, length)
}
