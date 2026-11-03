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
  h.u8(
    match t.justify {
      Auto => 0
      Left => 1
      Center => 2
      Right => 3
    },
  )
  let tries = @cmp.minimum(t.variable.length(), 255)
  h.u8(tries)
  for v in t.variable[:tries] {
    h.u8(anchor_code(v.0))
    h.f64(v.1)
    h.f64(v.2)
  }
  h.u8(
    match t.placement {
      Point => 0
      Line => 1
      LineCenter => 2
    },
  )
  h.u8(if t.keep_upright { 1 } else { 0 })
  h.f64(t.spacing)
  h.f64(t.max_angle)
  h.u32(self.count)
  for b in self.w.to_bytes() {
    h.u8(b.to_int())
  }
  h.to_bytes()
}

///|
/// Adds a label of feature `feature` at (x, y) in `TILE_EXTENT` units; false
/// (nothing added) when its text has no part with a value.
fn Labels::add(
  self : Labels,
  feature : Int32,
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
  w.u32(feature)
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
/// Adds the lines of `g` (`TILE_EXTENT` units, clamped to i16) to the label
/// just added: a count, then each line's point count and points.
fn Labels::lines(self : Labels, g : @mvt.Geometry, extent : Int32) -> Unit {
  let w = self.w
  let clamp = (v : Int32) => @cmp.minimum(32767, @cmp.maximum(-32768, v))
  w.u32(g.num_rings())
  for r in 0..<g.num_rings() {
    let start = g.ring_start(r)
    w.u32(g.ring_ends[r] - start)
    for p in start..<g.ring_ends[r] {
      w.i16(clamp(rescale(g.coords[p * 2], extent)))
      w.i16(clamp(rescale(g.coords[p * 2 + 1], extent)))
    }
  }
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
  let feature = self.feature_ref(layer)
  let extent = layer.extent()
  let parts = []
  let on_lines = !(text.placement is Point)
  for i in 0..<layer.length() {
    feature.index = i
    let kind_fits = match layer.geom_type(i) {
      Point => !on_lines
      LineString | Polygon => on_lines
      _ => false
    }
    if !(kind_fits && passes(sl.filter, feature, zoom)) {
      continue
    }
    parts.clear()
    for e in text.field {
      parts.push(e.eval(zoom, feature))
    }
    // A failing part fails the whole `text-field`, which then has no text.
    if parts.iter().any(p => p is Failed) {
      continue
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
    // The glue finds the anchors along lines (worker/js/line-labels.mjs).
    if on_lines {
      if out.add(i, 0, 0, size, sort_key, parts) {
        out.lines(g, extent)
      }
      continue
    }
    for p in 0..<g.num_points() {
      let x = rescale(g.coords[p * 2], extent)
      let y = rescale(g.coords[p * 2 + 1], extent)
      if x >= 0 && y >= 0 && x < @core.TILE_EXTENT && y < @core.TILE_EXTENT {
        out.add(i, x, y, size, sort_key, parts) |> ignore
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
