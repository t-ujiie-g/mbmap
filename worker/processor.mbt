///|
/// Turns tiles of one style's vector sources into `PackedTile`s. Reuse one
/// instance per worker: its tessellators and buffers keep their capacity.
pub struct TileProcessor {
  style : @style.Style
  out : PackedTile
  priv fill : @tess.FillTessellator
  priv line : @tess.LineTessellator
  priv fills : @tess.FillBuffers
  priv lines : @tess.LineBuffers
  priv geometry : @mvt.Geometry
  priv mut error : String
}

///|
pub fn TileProcessor::new(style : @style.Style) -> TileProcessor {
  {
    style,
    out: PackedTile::new(),
    fill: @tess.FillTessellator::new(),
    line: @tess.LineTessellator::new(),
    fills: @tess.FillBuffers::new(),
    lines: @tess.LineBuffers::new(),
    geometry: @mvt.Geometry::new(),
    error: "",
  }
}

///|
/// A processor for the style whose JSON text is the UTF-8 `bytes`.
pub fn TileProcessor::from_utf8(
  bytes : BytesView,
) -> TileProcessor raise @style.StyleError {
  TileProcessor::new(@style.Style::parse(@utf8.decode_lossy(bytes)))
}

///|
/// Why the last `process` failed.
pub fn TileProcessor::error(self : TileProcessor) -> String {
  self.error
}

///|
/// `error` as UTF-8, for handing it to JS through linear memory.
pub fn TileProcessor::error_utf8(self : TileProcessor) -> Bytes {
  @utf8.encode(self.error)
}

///|
fn join_of(j : @style.Join) -> @tess.LineJoin {
  match j {
    Miter => Miter
    Bevel => Bevel
    Round => Round
  }
}

///|
fn cap_of(c : @style.Cap) -> @tess.LineCap {
  match c {
    Butt => Butt
    Square => Square
    Round => Round
  }
}

///|
fn accepts(filter : @style.GeometryFilter, ty : @mvt.GeomType) -> Bool {
  match (filter, ty) {
    (AnyGeometry, _) => true
    (OnlyPoint, Point)
    | (OnlyLineString, LineString)
    | (OnlyPolygon, Polygon) => true
    _ => false
  }
}

///|
/// Whether two layers produce identical buffers. Line extrusion is stored in
/// half widths, so layers that differ only in paint (like a road and its
/// casing) share one.
fn same_geometry(a : @style.StyleLayer, b : @style.StyleLayer) -> Bool {
  a.kind == b.kind &&
  a.source == b.source &&
  a.source_layer == b.source_layer &&
  a.filter == b.filter &&
  (
    a.kind is Fill ||
    (
      a.join == b.join &&
      a.cap == b.cap &&
      a.miter_limit == b.miter_limit &&
      a.round_limit == b.round_limit
    )
  )
}

///|
/// Decodes `bytes`, a tile of source `source` at zoom `z`, and packs every fill
/// and line layer of the style that draws from it into `out`, in style order;
/// a layer with the same geometry as an earlier one points at its buffers.
/// Like MapLibre, a layer is skipped when `z` is outside its zoom range.
/// Returns false on a malformed tile or an oversized result (see `error`).
pub fn TileProcessor::process(
  self : TileProcessor,
  source : String,
  bytes : BytesView,
  z : Int32,
) -> Bool {
  let tile = @mvt.Tile::parse(bytes) catch {
    e => {
      self.error = "malformed tile: \{Repr(e)}"
      return false
    }
  }
  let style_layers = self.style.layers
  self.out.begin(style_layers.length())
  let zoom = z.to_double()
  // (style layer, its entry in `out` or -1 if it had no geometry)
  let done : Array[(Int32, Int32)] = []
  for index, sl in style_layers {
    if sl.source != source ||
      sl.kind is Background ||
      zoom < sl.min_zoom.floor() ||
      zoom >= sl.max_zoom {
      continue
    }
    guard tile.layer(sl.source_layer) is Some(layer) else { continue }
    let entries = self.out.layer_count()
    match done.search_by(d => same_geometry(style_layers[d.0], sl)) {
      Some(i) => {
        let entry = done[i].1
        if entry >= 0 {
          self.out.add_alias(index, entry)
        }
      }
      None => {
        let ok = match sl.kind {
          Fill => self.fill_layer(index, sl, layer)
          _ => self.line_layer(index, sl, layer)
        }
        if !ok {
          return false
        }
      }
    }
    done.push(
      (index, if self.out.layer_count() > entries { entries } else { -1 }),
    )
  }
  if self.out.overflowed() {
    self.error = "tile exceeds \{MAX_PACKED_BYTES} bytes"
    return false
  }
  true
}

///|
fn TileProcessor::decode(
  self : TileProcessor,
  layer : @mvt.Layer,
  i : Int32,
) -> Bool {
  if layer.decode_geometry(i, self.geometry) {
    return true
  }
  self.error = "malformed geometry in \{layer.name}[\{i}]: \{Repr(self.geometry.error())}"
  false
}

///|
fn TileProcessor::fill_layer(
  self : TileProcessor,
  index : Int32,
  sl : @style.StyleLayer,
  layer : @mvt.Layer,
) -> Bool {
  self.fills.clear()
  for i in 0..<layer.length() {
    let ty = layer.geom_type(i)
    if ty is Polygon && accepts(sl.filter, ty) {
      if !self.decode(layer, i) {
        return false
      }
      let g = self.geometry
      self.fill.add_polygons(g.coords[:], g.ring_ends[:], self.fills)
    }
  }
  self.fills.num_vertices() == 0 ||
  self.out.add_fill(index, self.fills, extent=layer.extent)
}

///|
fn TileProcessor::line_layer(
  self : TileProcessor,
  index : Int32,
  sl : @style.StyleLayer,
  layer : @mvt.Layer,
) -> Bool {
  self.lines.clear()
  let join = join_of(sl.join)
  let cap = cap_of(sl.cap)
  for i in 0..<layer.length() {
    let ty = layer.geom_type(i)
    if (ty is LineString || ty is Polygon) && accepts(sl.filter, ty) {
      if !self.decode(layer, i) {
        return false
      }
      let g = self.geometry
      for r in 0..<g.num_rings() {
        self.line.add_line(
          g.coords[:],
          g.ring_start(r),
          g.ring_ends[r],
          self.lines,
          join~,
          cap~,
          miter_limit=sl.miter_limit,
          round_limit=sl.round_limit,
        )
      }
    }
  }
  self.lines.num_vertices() == 0 ||
  self.out.add_line(index, self.lines, extent=layer.extent)
}
