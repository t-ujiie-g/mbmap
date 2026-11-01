///|
/// The labels of one symbol layer entry (docs/FORMATS.md, "Labels"), built
/// per group and reused across tiles.
priv struct Labels {
  w : @core.ByteWriter
  mut count : Int32
}

///|
fn Labels::new() -> Labels {
  { w: @core.ByteWriter::new(), count: 0, }
}

///|
fn anchor_code(a : @style.TextAnchor) -> Int32 {
  match a {
    Center => 0
    Left => 1
    Right => 2
    Top => 3
    Bottom => 4
    TopLeft => 5
    TopRight => 6
    BottomLeft => 7
    BottomRight => 8
  }
}

///|
/// The entry's bytes: the layer's layout, then the labels.
fn Labels::bytes(self : Labels, t : @style.TextLayout) -> Bytes {
  let h = @core.ByteWriter::new()
  h.u8(anchor_code(t.anchor))
  h.u8(if t.allow_overlap { 1 } else { 0 })
  h.u8(if t.ignore_placement { 1 } else { 0 })
  h.u8(if t.vertical { 1 } else { 0 })
  for v in [t.offset.0, t.offset.1, t.max_width, t.line_height, t.padding] {
    h.f64(v)
  }
  h.u32(self.count)
  for b in self.w.to_bytes() {
    h.u8(b.to_int())
  }
  h.to_bytes()
}

///|
/// Adds a label at (x, y) in `TILE_EXTENT` units; false (nothing added) when
/// its text has no part with a value.
fn Labels::add(
  self : Labels,
  x : Int32,
  y : Int32,
  size : Double,
  sort_key : Double,
  parts : Array[@style.Value],
) -> Bool {
  if parts.iter().all(v => v is (Null | Str(""))) {
    return false
  }
  let w = self.w
  w.i16(x)
  w.i16(y)
  w.f64(size)
  w.f64(sort_key)
  w.u32(parts.length())
  for v in parts {
    write_value(w, v)
  }
  self.count += 1
  true
}

///|
fn TileProcessor::labels(self : TileProcessor, g : Int32) -> Labels {
  while self.label_pool.length() <= g {
    self.label_pool.push(Labels::new())
  }
  self.label_pool[g]
}

///|
/// Labels of a symbol layer's points; anchors outside the tile are left to the
/// tile that holds them, as MapLibre does.
fn TileProcessor::symbol_layer(
  self : TileProcessor,
  index : Int32,
  sl : @style.StyleLayer,
  layer : Features,
  zoom : Double,
  groups : Groups,
) -> Bool {
  guard sl.text is Some(text) && text.field.length() > 0 else { return true }
  for l in self.label_pool {
    l.w.clear()
    l.count = 0
  }
  let feature = FeatureRef::new(layer)
  let extent = layer.extent()
  let parts = []
  for i in 0..<layer.length() {
    feature.index = i
    if !(layer.geom_type(i) is Point && passes(sl.filter, feature, zoom)) {
      continue
    }
    parts.clear()
    for e in text.field {
      parts.push(e.eval(zoom, feature))
    }
    let size = match text.size.eval(zoom, feature) {
      Num(n) if n > 0.0 => n
      _ => continue
    }
    let sort_key = match text.sort_key.map(e => e.eval(zoom, feature)) {
      Some(Num(n)) => n
      _ => 0.0
    }
    if !self.decode(layer, i) {
      return false
    }
    let g = self.geometry
    let out = self.labels(groups.of(feature))
    for p in 0..<g.num_points() {
      let x = rescale(g.coords[p * 2], extent)
      let y = rescale(g.coords[p * 2 + 1], extent)
      if x >= 0 && y >= 0 && x < @core.TILE_EXTENT && y < @core.TILE_EXTENT {
        out.add(x, y, size, sort_key, parts) |> ignore
      }
    }
  }
  for g in 0..<groups.count() {
    let l = self.labels(g)
    if l.count > 0 {
      if !self.out.add_labels(index, l.bytes(text)) {
        return false
      }
      if groups.active {
        self.out.set_props(groups.props(g))
      }
    }
  }
  true
}
