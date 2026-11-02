///|
/// Whether a worker builds the same tile for `self` as for `other` (two
/// versions of a layer): the same kind, source, zoom range, filter, text and
/// line layout and extruded heights, and paint that reads the same feature
/// data (paint values themselves are applied on the main thread).
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
    ].map(e => e.feature_inputs())
  }
  self.id == other.id &&
  self.kind == other.kind &&
  self.source == other.source &&
  self.source_layer == other.source_layer &&
  self.min_zoom == other.min_zoom &&
  self.max_zoom == other.max_zoom &&
  self.filter == other.filter &&
  self.text == other.text &&
  self.extrusion == other.extrusion &&
  self.join == other.join &&
  self.cap == other.cap &&
  self.miter_limit == other.miter_limit &&
  self.round_limit == other.round_limit &&
  inputs(self) == inputs(other)
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
  self.tolerance == other.tolerance
}
