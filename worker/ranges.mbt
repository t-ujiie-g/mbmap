///|
/// Notes that feature `i` of style layer `index` took indices `first..<end`
/// of group `group`'s buffers, if the layer is drawn feature by feature.
fn TileProcessor::track(
  self : TileProcessor,
  index : Int32,
  group : Int32,
  i : Int32,
  first : Int32,
  end : Int32,
) -> Unit {
  guard self.state_layers[index] && end > first else { return }
  while self.range_pool.length() <= group {
    self.range_pool.push([])
  }
  let r = self.range_pool[group]
  r.push(i)
  r.push(first)
  r.push(end - first)
}

///|
/// Writes the ranges of group `group` as those of packed entry `entry`
/// (docs/FORMATS.md, "Feature ranges") and empties the group's list.
fn TileProcessor::flush_ranges(
  self : TileProcessor,
  index : Int32,
  entry : Int32,
  group : Int32,
  layer : Features,
) -> Unit {
  guard self.state_layers[index] && group < self.range_pool.length() else {
    return
  }
  let sl = self.style.layers[index]
  let promoted = match self.style.source(sl.source) {
    Some(s) => s.promote_id.property(sl.source_layer)
    None => None
  }
  let r = self.range_pool[group]
  let w = self.ranges
  w.u32(entry)
  w.u32(r.length() / 3)
  for k = 0; k < r.length(); k = k + 3 {
    write_value(w, layer.id(r[k], promoted))
    w.u32(r[k + 1])
    w.u32(r[k + 2])
  }
  self.range_entries += 1
  r.clear()
}

///|
/// The feature ranges of the last tile processed (docs/FORMATS.md, "Feature
/// ranges"): where each feature's indices lie in the entries of layers whose
/// paint reads the feature state.
pub fn TileProcessor::feature_ranges(self : TileProcessor) -> Bytes {
  let w = @core.ByteWriter::new()
  w.u32(self.range_entries)
  for b in self.ranges.to_bytes() {
    w.u8(b.to_int())
  }
  w.to_bytes()
}
