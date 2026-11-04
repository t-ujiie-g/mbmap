///|
/// Whether a worker builds the same tile for both versions of a layer: same
/// kind, source, zoom range, filter, text and line layout, extruded heights and
/// feature inputs of paint (paint values are applied on the main thread).
pub fn StyleLayer::same_tiles(self : StyleLayer, other : StyleLayer) -> Bool {
  let inputs = (l : StyleLayer) => {
    [
      l.color,
      l.opacity,
      l.width,
      l.radius,
      l.stroke_width,
      l.stroke_color,
      l.stroke_opacity,
      l.halo_color,
      l.halo_width,
      l.gap_width,
      l.offset,
      ..l.icon_paint.map_or([], p => p.exprs()),
    ].map(e => e.feature_inputs())
  }
  self.id == other.id &&
  self.kind == other.kind &&
  self.source == other.source &&
  self.source_layer == other.source_layer &&
  self.min_zoom == other.min_zoom &&
  self.max_zoom == other.max_zoom &&
  self.filter == other.filter &&
  self.sort_key == other.sort_key &&
  self.text == other.text &&
  self.icon.map(i => i.layout) == other.icon.map(i => i.layout) &&
  self.extrusion == other.extrusion &&
  self.same_line_layout(other) &&
  self.reads_state() == other.reads_state() &&
  self.paints_by_group() == other.paints_by_group() &&
  self.pattern.map(p => p.feature_inputs()) ==
  other.pattern.map(p => p.feature_inputs()) &&
  inputs(self) == inputs(other) &&
  // Per-vertex paint is computed into the tiles.
  self.baked_paint() == other.baked_paint()
}

///|
/// Whether two versions of a source fetch and cut the same tiles.
pub fn Source::same(self : Source, other : Source) -> Bool {
  self.id == other.id &&
  self.kind == other.kind &&
  self.tiles == other.tiles &&
  self.min_zoom == other.min_zoom &&
  self.max_zoom == other.max_zoom &&
  self.tile_size == other.tile_size &&
  self.encoding == other.encoding &&
  self.buffer == other.buffer &&
  self.tolerance == other.tolerance &&
  self.promote_id == other.promote_id &&
  self.bounds == other.bounds &&
  self.tms == other.tms
}

///|
/// Whether the layer's paint reads the feature state, which the map draws
/// feature by feature (symbol layers' text ignores it for now).
pub fn StyleLayer::reads_state(self : StyleLayer) -> Bool {
  let exprs = match self.kind {
    Fill | FillExtrusion => [self.color, self.opacity]
    Line => [self.color, self.opacity, self.width, self.gap_width, self.offset]
    Circle =>
      [
        self.color,
        self.opacity,
        self.radius,
        self.stroke_width,
        self.stroke_color,
        self.stroke_opacity,
      ]
    _ => []
  }
  exprs.iter().any(e => e.reads_state())
}

///|
/// Whether two layers' lines are extruded alike: the layout tess reads, and
/// whether distances (dashes, patterns) and progress (gradients) are kept.
pub fn StyleLayer::same_line_layout(
  self : StyleLayer,
  other : StyleLayer,
) -> Bool {
  self.join == other.join &&
  self.cap == other.cap &&
  self.miter_limit == other.miter_limit &&
  self.round_limit == other.round_limit &&
  self.line_distances() == other.line_distances() &&
  self.line_offsets() == other.line_offsets() &&
  (self.gradient is Some(_)) == (other.gradient is Some(_))
}

///|
/// Whether a line layer's vertices keep their distances along their lines:
/// for dashes and patterns.
pub fn StyleLayer::line_distances(self : StyleLayer) -> Bool {
  self.kind is Line && (self.dasharray is Some(_) || self.pattern is Some(_))
}

///|
/// Whether a line layer is offset (`line-offset` other than 0), so its vertices
/// carry the direction an offset moves them.
pub fn StyleLayer::line_offsets(self : StyleLayer) -> Bool {
  self.kind is Line && !(self.offset is Lit(Num(0.0)))
}
