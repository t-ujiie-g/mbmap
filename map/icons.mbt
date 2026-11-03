///|
/// A symbol mesh's icons (a quad per label with one), its images' `names` (those
/// it lacked too) and layout; `sharp` when no image needs linear filtering
/// (MapLibre's `iconsNeedLinear`); `shown` and `glyphs` (along lines) as text's.
priv struct IconSet {
  mesh : @render_webgl2.Mesh
  names : Array[String]
  has_icons : Bool
  allow_overlap : Bool
  ignore_placement : Bool
  optional : Bool
  text_optional : Bool
  rotate_with_map : Bool
  pitch_with_map : Bool
  keep_upright : Bool
  text_fit : Bool
  offset : Bool
  sdf : Bool
  sharp : Bool
  shown : FixedArray[Bool]
  mut changed : Bool
  mut drawn : Int32
  glyphs : FixedArray[Double]
}

///|
/// A symbol entry's icons (`icon` in the worker's message), uploaded with their
/// images' places in the icon atlas, or None without; the names of images it
/// lacked are reported missing.
fn Map::icon_set(self : Map, l : JsValue, count : Int32) -> IconSet? {
  let ic = get_value(l, "icon")
  guard !is_null_value(ic) else { return None }
  let names = strings_of(ic, "images")
  let rects = FixedArray::make(names.length() * 4, 0)
  let mut ratios = true
  for i, name in names {
    if self.images.get(name) is Some(image) {
      ratios = ratios && image.pixel_ratio == device_pixel_ratio()
      if self.renderer.icon(name, image) is Some(p) {
        rects[i * 4] = p.tl.0 - 1
        rects[i * 4 + 1] = p.tl.1 - 1
        rects[i * 4 + 2] = p.br.0 - p.tl.0 + 2
        rects[i * 4 + 3] = p.br.1 - p.tl.1 + 2
      }
    }
  }
  let missing = strings_of(l, "missing")
  for name in missing {
    self.report_missing(name)
  }
  Some({
    mesh: self.renderer.upload_symbols(
      buffer_of(ic, "vertices"),
      buffer_of(ic, "indices"),
      get_int(ic, "indexBytes"),
      rects,
    ),
    names: [..names.iter(), ..missing.iter()],
    has_icons: get_int(ic, "count") > 0,
    allow_overlap: get_bool(ic, "allowOverlap"),
    ignore_placement: get_bool(ic, "ignorePlacement"),
    optional: get_bool(ic, "optional"),
    text_optional: get_bool(ic, "textOptional"),
    rotate_with_map: get_bool(ic, "rotateWithMap"),
    pitch_with_map: get_bool(ic, "pitchWithMap"),
    keep_upright: get_bool(ic, "keepUpright"),
    text_fit: get_int(ic, "textFit") > 0,
    offset: get_bool(ic, "hasOffset"),
    sdf: get_bool(ic, "sdf"),
    sharp: ratios && !get_bool(ic, "rotated"),
    shown: FixedArray::make(count, false),
    changed: false,
    drawn: -1,
    glyphs: FixedArray::make(
      get_int(ic, "count") / QUAD_INDICES * 3,
      HIDDEN_GLYPH,
    ),
  })
}

///|
/// Label `i`'s icon set if it has an icon.
fn icon_of(s : LabelSet, i : Int32) -> IconSet? {
  match s.icon {
    Some(ic) if f32_at(s.labels, i * LABEL_FLOATS + ICON_COUNT) > 0.0 =>
      Some(ic)
    _ => None
  }
}

///|
/// Whether a label's text and icon show when both were placed as `text` and
/// `icon`: MapLibre's `text-optional` and `icon-optional` rules.
fn joint(
  ic : IconSet,
  has_text : Bool,
  text : Bool,
  icon : Bool,
) -> (Bool, Bool) {
  let icon_alone = ic.text_optional || !has_text
  if !icon_alone && !ic.optional {
    (text && icon, text && icon)
  } else if !ic.optional {
    (text && icon, icon)
  } else if !icon_alone {
    (text, icon && text)
  } else {
    (text, icon)
  }
}

///|
/// Puts label `i`'s icon box (as recorded) in the grid if `placed` and shows
/// the icon; MapLibre shows one that may overlap even off the grid, where
/// queries do not find it.
fn show_icon(
  grid : @label.Grid,
  s : LabelSet,
  ic : IconSet,
  i : Int32,
  placed : Bool,
  visible : Bool,
) -> Unit {
  if placed && !ic.ignore_placement {
    insert_box(grid, s, i, 4)
  }
  let always = ic.allow_overlap &&
    (s.allow_overlap || !s.has_text || ic.text_optional)
  let show = placed || (always && visible && nan_box(s, i, 4))
  if show != ic.shown[i] {
    ic.shown[i] = show
    ic.changed = true
  }
}

///|
/// Draws the shown icons of style layer `index` in the tiles of `draws`, before
/// any of the layer's text (MapLibre draws a symbol layer's icons, then its text).
fn Map::draw_icons(
  self : Map,
  index : Int32,
  layer : @style.StyleLayer,
  draws : Array[Draw],
  dpr : Double,
  height_scale : Double,
) -> Unit {
  guard layer.icon is Some(l) && layer.icon_paint is Some(paint) else { return }
  let t = self.transform
  let zoom = t.camera.zoom
  let (keys, geometry) = l.size.feature_inputs()
  let size = if keys.is_empty() && !geometry {
    number_or(l.size.eval(zoom, JsProps::none()), 1.0)
  } else {
    -1.0
  }
  let pitch = t.camera.pitch
  for d in draws {
    for m in d.meshes {
      guard m.layer == index &&
        m.labels is Some({ icon: Some(ic), .. }) &&
        ic.drawn != self.frame_count else {
        continue
      }
      // An ancestor standing in for several tiles is drawn once.
      ic.drawn = self.frame_count
      let s = m.labels.unwrap()
      let along = s.line is Some(_) && ic.rotate_with_map
      if s.line is Some(l) {
        let tile_px = d.at.units_per_pixel * dpr
        self.lay_line_glyphs(m.mesh, d.at, s, l, tile_px, height_scale)
      }
      let ctx = m.props.unwrap_or(JsProps::none())
      let c = (e : @style.Expr) => rgba_of(color_of(e, zoom, ctx))
      let n = (e : @style.Expr, d : Double) => number_or(e.eval(zoom, ctx), d)
      self.renderer.draw_icons(
        ic.mesh,
        d.at,
        dpr,
        size~,
        perspective=!ic.offset,
        pitch=ic.pitch_with_map,
        rotate=ic.rotate_with_map,
        angle=if ic.pitch_with_map && !ic.rotate_with_map {
          t.camera.bearing * @math.PI / 180.0
        } else {
          0.0
        },
        sdf=ic.sdf,
        // MapLibre samples icons as they are unless they are scaled or turned.
        linear=ic.sdf ||
          pitch != 0.0 ||
          ic.pitch_with_map ||
          size != 1.0 ||
          !ic.sharp,
        opacity=n(paint.opacity, 1.0),
        color=c(paint.color),
        halo=c(paint.halo_color),
        halo_width=n(paint.halo_width, 0.0),
        halo_blur=n(paint.halo_blur, 0.0),
        gamma_scale=if ic.pitch_with_map {
          @math.cos(pitch * @math.PI / 180.0) * d.at.center_depth
        } else {
          1.0
        },
        height_scale~,
        along~,
      )
    }
  }
}
