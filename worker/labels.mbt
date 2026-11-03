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
fn Labels::bytes(
  self : Labels,
  t : @style.TextLayout,
  icon : @style.IconLayout?,
) -> Bytes {
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
  let flag = (b : Bool) => h.u8(if b { 1 } else { 0 })
  flag(icon is Some(_))
  if icon is Some(i) {
    h.u8(anchor_code(i.anchor))
    for
      b in [
        i.allow_overlap,
        i.ignore_placement,
        i.optional,
        i.text_optional,
        i.rotate_with_map,
        i.pitch_with_map,
        i.keep_upright,
      ] {
      flag(b)
    }
    h.u8(
      match i.text_fit {
        NoFit => 0
        Width => 1
        Height => 2
        Both => 3
      },
    )
    let (pt, pr, pb, pl) = i.padding
    let (ft, fr, fb, fl) = i.text_fit_padding
    for v in [i.offset.0, i.offset.1, pt, pr, pb, pl, ft, fr, fb, fl] {
      h.f64(v)
    }
  }
  h.u32(self.count)
  for b in self.w.to_bytes() {
    h.u8(b.to_int())
  }
  h.to_bytes()
}

///|
/// Adds a label of feature `feature` at (x, y) in `TILE_EXTENT` units, with
/// its icon's name parts, size and rotation if the layer has an icon; false
/// (nothing added) when neither its text nor its icon has a part with a value.
fn Labels::add(
  self : Labels,
  feature : Int32,
  x : Int32,
  y : Int32,
  size : Double,
  sort_key : Double,
  parts : Array[@style.Value],
  icon : (Array[@style.Value], Double, Double)?,
) -> Bool {
  let empty = (ps : Array[@style.Value]) => {
    ps.iter().all(v => v is (Null | Str("")))
  }
  if empty(parts) && icon.map_or(true, i => empty(i.0)) {
    return false
  }
  let w = self.w
  w.u32(feature)
  w.i16(x)
  w.i16(y)
  w.f64(size)
  w.f64(sort_key)
  let values = (ps : Array[@style.Value]) => {
    w.u32(ps.length())
    for v in ps {
      write_value(w, v)
    }
  }
  values(parts)
  if icon is Some((name, size, rotate)) {
    values(name)
    w.f64(size)
    w.f64(rotate)
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
  guard sl.text is Some(text) && (text.field.length() > 0 || sl.icon is Some(_)) else {
    return true
  }
  for l in self.label_pool {
    l.w.clear()
    l.count = 0
  }
  let feature = self.feature_ref(layer)
  let extent = layer.extent()
  let parts = []
  let icon_parts = []
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
      parts.clear()
    }
    let size = match text.size.eval(zoom, feature) {
      Num(n) if n > 0.0 => n
      _ => {
        parts.clear()
        0.0
      }
    }
    // MapLibre lays icons out at `icon-size` one zoom deeper.
    let icon = match sl.icon {
      Some(l) => {
        icon_parts.clear()
        for e in l.image {
          icon_parts.push(e.eval(zoom, feature))
        }
        if icon_parts.iter().any(p => p is Failed) {
          icon_parts.clear()
        }
        let n = (e : @style.Expr, z : Double, d : Double) => {
          match e.eval(z, feature) {
            Num(n) if n == n => n
            _ => d
          }
        }
        Some((icon_parts, n(l.size, zoom + 1.0, 1.0), n(l.rotate, zoom, 0.0)))
      }
      None => None
    }
    if parts.is_empty() && icon is None {
      continue
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
      if out.add(i, 0, 0, size, sort_key, parts, icon) {
        out.lines(g, extent)
      }
      continue
    }
    for p in 0..<g.num_points() {
      let x = rescale(g.coords[p * 2], extent)
      let y = rescale(g.coords[p * 2 + 1], extent)
      if x >= 0 && y >= 0 && x < @core.TILE_EXTENT && y < @core.TILE_EXTENT {
        out.add(i, x, y, size, sort_key, parts, icon) |> ignore
      }
    }
  }
  for g in 0..<groups.count() {
    let l = self.labels(g)
    if l.count > 0 {
      if !self.out.add_labels(index, l.bytes(text, sl.icon)) {
        return false
      }
      if groups.active {
        self.out.set_props(groups.props(g))
      }
    }
  }
  true
}
