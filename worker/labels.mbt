///|
/// The labels of one symbol layer entry (docs/FORMATS.md, "Labels"), built
/// per group and reused across tiles; `fonts` the `text-font` stacks they use
/// (the map's own font first) and the faces written for them.
priv struct Labels {
  w : @core.ByteWriter
  mut count : Int32
  fonts : Map[String, Int32]
  faces : Array[String]
}

///|
fn Labels::new() -> Labels {
  { w: @core.ByteWriter::new(), count: 0, fonts: Map([]), faces: [], }
}

///|
/// Most fonts one entry names; labels past them take the map's own font.
const MAX_FONTS : Int32 = 32

///|
/// A font's index among the entry's (0 the map's own): `stack` as `text-font`
/// joins its names, its face (`@style.font_face`) written as style, weight and
/// family on lines of their own.
fn Labels::font(self : Labels, stack : String) -> Int32 {
  if stack == "" {
    return 0
  }
  match self.fonts.get(stack) {
    Some(i) => i
    None if self.faces.length() >= MAX_FONTS => 0
    None => {
      let (family, weight, style) = @style.font_face(stack)
      self.faces.push("\{style}\n\{weight}\n\{family}")
      self.fonts[stack] = self.faces.length()
      self.faces.length()
    }
  }
}

///|
/// Clears the labels and fonts for the next tile.
fn Labels::clear(self : Labels) -> Unit {
  self.w.clear()
  self.count = 0
  self.fonts.clear()
  self.faces.clear()
}

///|
/// The entry's bytes: the layer's layout, then the labels.
fn Labels::bytes(
  self : Labels,
  t : @style.TextLayout,
  icon : @style.IconLayout?,
) -> Bytes {
  let h = @core.ByteWriter::new()
  h.u8(t.anchor.code())
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
    h.u8(v.0.code())
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
    h.u8(i.anchor.code())
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
  h.u8(self.faces.length())
  for f in self.faces {
    h.utf8(f)
  }
  h.u32(self.count)
  h.append(self.w)
  h.to_bytes()
}

///|
/// Adds a label of feature `feature` at (x, y) in `TILE_EXTENT` units drawn as `look` says, with
/// its icon's name parts, size and rotation if the layer has one; false (nothing added) when
/// neither its text nor its icon has a part with a value.
fn Labels::add(
  self : Labels,
  feature : Int32,
  x : Int32,
  y : Int32,
  size : Double,
  sort_key : Double,
  parts : Array[@style.Value],
  look : Look,
  icon : (Array[@style.Value], Double, Double)?,
) -> Bool {
  let icon_empty = match icon {
    Some((name, _, _)) => no_value(name)
    None => true
  }
  if no_value(parts) && icon_empty {
    return false
  }
  let w = self.w
  w.u32(feature)
  w.i16(x)
  w.i16(y)
  w.f64(size)
  w.f64(sort_key)
  w.u8(self.font(look.font))
  w.u8(look.transform)
  w.f64(look.spacing)
  w.f64(look.rotate)
  self.write_values(parts)
  if icon is Some((name, size, rotate)) {
    self.write_values(name)
    w.f64(size)
    w.f64(rotate)
  }
  self.count += 1
  true
}

///|
/// Whether none of `parts` has a value: each is null or empty (a formatted
/// text as MapLibre's `Formatted::isEmpty`).
fn no_value(parts : Array[@style.Value]) -> Bool {
  for v in parts {
    match v {
      Null | Str("") => ()
      Formatted(sections) =>
        if sections.iter().any(s => s.text != "") {
          return false
        }
      _ => return false
    }
  }
  true
}

///|
/// Whether one of `parts` failed to evaluate.
fn any_failed(parts : Array[@style.Value]) -> Bool {
  for v in parts {
    if v is Failed {
      return true
    }
  }
  false
}

///|
/// How a label's text is drawn: its `text-font` joined by commas ("" for the
/// map's own), `text-transform` (0 none, 1 uppercase, 2 lowercase),
/// `text-letter-spacing` (ems) and `text-rotate` (degrees).
priv struct Look {
  mut font : String
  mut transform : Int32
  mut spacing : Double
  mut rotate : Double
}

///|
/// A count, then each of `parts`: a property value, or a formatted text
/// (docs/FORMATS.md "Labels").
fn Labels::write_values(self : Labels, parts : Array[@style.Value]) -> Unit {
  let w = self.w
  w.u32(parts.length())
  for v in parts {
    guard v is Formatted(sections) else {
      write_value(w, v)
      continue
    }
    w.u8(LABEL_SECTIONS)
    w.u32(sections.length())
    for s in sections {
      w.utf8(s.text)
      w.f64(s.scale.unwrap_or(@double.not_a_number))
      w.u8(
        match s.align {
          Some("center") => 1
          Some("top") => 2
          _ => 0
        },
      )
      w.u8(
        match s.font {
          Some(f) => self.font(f)
          None => NO_FONT
        },
      )
      match s.color {
        Some(c) => {
          w.u8(1)
          for v in [c.r, c.g, c.b, c.a] {
            w.u8((v * 255.0).round().to_int())
          }
        }
        None => w.u8(0)
      }
    }
  }
}

///|
/// The tag of a formatted text among a label's parts, past `@core.PROP_ABSENT`.
const LABEL_SECTIONS : Int32 = 6

///|
/// A section's font index when it takes the label's.
const NO_FONT : Int32 = 255

///|
/// `e`'s number at zoom `z` for `feature`, or `default` if it gives none.
fn number_or(
  e : @style.Expr,
  z : Double,
  feature : FeatureRef,
  default : Double,
) -> Double {
  match e.eval(z, feature) {
    Num(n) if n == n => n
    _ => default
  }
}

///|
/// Adds the lines of `g` (`TILE_EXTENT` units, clamped to i16) to the label
/// just added: a count, then each line's point count and points.
fn Labels::lines(self : Labels, g : @mvt.Geometry, extent : Int32) -> Unit {
  let w = self.w
  w.u32(g.num_rings())
  for r in 0..<g.num_rings() {
    let start = g.ring_start(r)
    w.u32(g.ring_ends[r] - start)
    for p in start..<g.ring_ends[r] {
      w.i16(rescale(g.coords[p * 2], extent))
      w.i16(rescale(g.coords[p * 2 + 1], extent))
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
/// Labels of a symbol layer: at its points, whose anchors outside the tile are
/// left to the tile that holds them as MapLibre does, or along its lines.
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
    l.clear()
  }
  let feature = self.feature_ref(layer)
  let extent = layer.extent()
  let parts = []
  let icon_parts = []
  let look = { font: "", transform: 0, spacing: 0.0, rotate: 0.0, }
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
    if any_failed(parts) {
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
        if any_failed(icon_parts) {
          icon_parts.clear()
        }
        Some(
          (
            icon_parts,
            number_or(l.size, zoom + 1.0, feature, 1.0),
            number_or(l.rotate, zoom, feature, 0.0),
          ),
        )
      }
      None => None
    }
    if parts.is_empty() && icon is None {
      continue
    }
    let sort_key = match text.sort_key {
      Some(e) => number_at(e, zoom, feature)
      None => 0.0
    }
    look.font = match text.font.map(e => e.eval(zoom, feature)) {
      Some(List(names)) =>
        names.map(v => if v is Str(s) { s } else { "" }).join(",")
      _ => ""
    }
    look.transform = match text.transform.eval(zoom, feature) {
      Str("uppercase") => 1
      Str("lowercase") => 2
      _ => 0
    }
    look.spacing = number_or(text.letter_spacing, zoom, feature, 0.0)
    look.rotate = number_or(text.rotate, zoom, feature, 0.0)
    if !self.decode(layer, i) {
      return false
    }
    let g = self.geometry
    let out = self.labels(groups.of(feature))
    // The glue finds the anchors along lines (worker/js/line-labels.mjs).
    if on_lines {
      if out.add(i, 0, 0, size, sort_key, parts, look, icon) {
        out.lines(g, extent)
      }
      continue
    }
    for p in 0..<g.num_points() {
      let x = rescale(g.coords[p * 2], extent)
      let y = rescale(g.coords[p * 2 + 1], extent)
      if x >= 0 && y >= 0 && x < @core.TILE_EXTENT && y < @core.TILE_EXTENT {
        out.add(i, x, y, size, sort_key, parts, look, icon) |> ignore
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
