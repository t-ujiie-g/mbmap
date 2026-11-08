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
  let feature_dashes = sl.feature_dashes()
  for d in self.dash_pool {
    d.clear()
  }
  let order = self.feature_order(sl, layer, zoom, self.keys)
  for k in 0..<layer.length() {
    let i = order.map_or(k, o => o[k])
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
      if !self.may_fit(2 * g.num_points(), LINE_VERTEX_BYTES) {
        return false
      }
      // A round join makes many vertices of one point: stop once past the budget.
      out.limit(v0 + (self.budget / LINE_VERTEX_BYTES.to_double()).to_int() + 1)
      self.on_globe(layer)
      let extent = self.extent_of(layer)
      for r in 0..<g.num_rings() {
        let before = out.num_vertices()
        // On the globe each line is cut at grid lines first (`subdivideVertexLine`).
        let (coords, start, end) = if self.globe {
          let p = self.line_points
          p.clear()
          @tess.subdivide_vertex_line(
            g.coords[g.ring_start(r) * 2:g.ring_ends[r] * 2],
            @tess.line_granularity(self.place.z),
            p,
          )
          (p, 0, p.length() / 2)
        } else {
          (g.coords, g.ring_start(r), g.ring_ends[r])
        }
        self.line.add_line(
          coords[:],
          start,
          end,
          out,
          join~,
          cap~,
          miter_limit=sl.miter_limit,
          round_limit=sl.round_limit,
          dashed=sl.line_distances(),
          progress=gradient,
          offset=sl.line_offsets(),
          extent~,
        )
        if gradient && out.num_vertices() > before {
          self
          .gradient_rows(group)
          .add(
            out.num_vertices() - before,
            clip,
            ring_length(coords, start, end) / extent.to_double(),
          )
        }
      }
      if out.full() {
        return self.exceeds()
      }
      if !self.spend(
          out.num_vertices() - v0,
          LINE_VERTEX_BYTES,
          out.indices.length() - first,
        ) {
        return false
      }
      if feature_dashes is Some(e) {
        self.dashes(group).add(e, zoom, feature, out.num_vertices() - v0)
      }
      self.track(index, group, i, first, out.indices.length())
      self.run(i, out.num_vertices() - v0)
    }
  }
  for g in 0..<groups.count() {
    let b = self.line_buffers(g)
    if b.num_vertices() > 0 {
      let entry = self.out.layer_count()
      if !self.out.add_line(index, b, extent=self.extent_of(layer)) ||
        (gradient && !self.out.put_progress(b, self.gradient_rows(g))) ||
        (feature_dashes is Some(_) && !self.out.put_dashes(self.dashes(g))) ||
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
fn TileProcessor::dashes(self : TileProcessor, g : Int32) -> Dashes {
  while self.dash_pool.length() <= g {
    self.dash_pool.push(Dashes::new())
  }
  self.dash_pool[g]
}

///|
/// Most patterns one entry's features may have, and most numbers in one; the
/// rest draw solid.
const MAX_FEATURE_DASHES : Int32 = 1024

///|
const MAX_FEATURE_DASH_PARTS : Int32 = 64

///|
/// No pattern: the line is drawn solid.
const NO_DASH : Int32 = 0xffff

///|
/// A line layer's dash patterns by feature (MapLibre's `dashDependencies`): the
/// distinct `patterns` and, per vertex, the pattern at the tile's zoom minus
/// one, at it and plus one (four u16s, the last 0).
priv struct Dashes {
  patterns : Array[Array[Double]]
  marks : Array[Int32]
}

///|
fn Dashes::new() -> Dashes {
  { patterns: [], marks: [], }
}

///|
fn Dashes::clear(self : Dashes) -> Unit {
  self.patterns.clear()
  self.marks.clear()
}

///|
/// The index of the pattern `e` gives `feature` at `zoom`, or `NO_DASH`.
fn Dashes::index(
  self : Dashes,
  e : @style.Expr,
  zoom : Double,
  feature : FeatureRef,
) -> Int32 {
  guard e.eval(zoom, feature) is List(items) &&
    items.length() <= MAX_FEATURE_DASH_PARTS else {
    return NO_DASH
  }
  let pattern = []
  for v in items {
    guard v is Num(n) && n >= 0.0 && n < @double.infinity else {
      return NO_DASH
    }
    pattern.push(n)
  }
  match self.patterns.search(pattern) {
    Some(k) => k
    None if self.patterns.length() < MAX_FEATURE_DASHES => {
      self.patterns.push(pattern)
      self.patterns.length() - 1
    }
    None => NO_DASH
  }
}

///|
/// Records `feature`'s patterns for its `n` vertices.
fn Dashes::add(
  self : Dashes,
  e : @style.Expr,
  zoom : Double,
  feature : FeatureRef,
  n : Int32,
) -> Unit {
  let lo = self.index(e, zoom - 1.0, feature)
  let mid = self.index(e, zoom, feature)
  let hi = self.index(e, zoom + 1.0, feature)
  for _ in 0..<n {
    self.marks.push(lo)
    self.marks.push(mid)
    self.marks.push(hi)
    self.marks.push(0)
  }
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
