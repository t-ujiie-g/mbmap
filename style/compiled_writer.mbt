///|
/// The writer of docs/FORMATS.md "Compiled style".
priv struct StyleWriter {
  w : @core.ByteWriter
}

///|
fn StyleWriter::code(self : StyleWriter, v : Int32) -> Unit {
  self.w.u8(v)
}

///|
fn StyleWriter::flag(self : StyleWriter, b : Bool) -> Unit {
  self.w.u8(if b { 1 } else { 0 })
}

///|
fn StyleWriter::value(self : StyleWriter, v : Value) -> Unit {
  match v {
    Null => self.code(@core.PROP_NULL)
    Bool(b) => self.code(if b { @core.PROP_TRUE } else { @core.PROP_FALSE })
    Num(n) => {
      self.code(@core.PROP_NUMBER)
      self.w.f64(n)
    }
    Str(s) => {
      self.code(@core.PROP_STRING)
      self.w.utf8(s)
    }
    Color(c) => {
      self.code(VALUE_COLOR)
      self.w.f64(c.r)
      self.w.f64(c.g)
      self.w.f64(c.b)
      self.w.f64(c.a)
    }
    List(vs) => {
      self.code(VALUE_LIST)
      self.w.u32(vs.length())
      vs.each(v => self.value(v))
    }
    // Expressions make these; literals never hold them.
    Failed | Formatted(_) | Collator(_, _, _) => self.code(VALUE_FAILED)
  }
}

///|
fn StyleWriter::expected(self : StyleWriter, e : Expected) -> Unit {
  match e {
    AnyType => self.code(0)
    ColorType => self.code(1)
    NumberType => self.code(2)
    BoolType => self.code(3)
    StringType => self.code(4)
    ArrayOf(item, n) => {
      self.code(5)
      self.expected(item)
      self.w.u32(n)
    }
  }
}

///|
fn StyleWriter::exprs(self : StyleWriter, es : Array[Expr]) -> Unit {
  self.w.u32(es.length())
  es.each(e => self.expr(e))
}

///|
fn StyleWriter::stops(
  self : StyleWriter,
  stops : Array[(Double, Expr)],
) -> Unit {
  self.w.u32(stops.length())
  for s in stops {
    self.w.f64(s.0)
    self.expr(s.1)
  }
}

///|
fn StyleWriter::expr(self : StyleWriter, e : Expr) -> Unit {
  match e {
    Lit(v) => {
      self.code(EXPR_LIT)
      self.value(v)
    }
    Get(k) => {
      self.code(EXPR_GET)
      self.w.utf8(k)
    }
    Has(k) => {
      self.code(EXPR_HAS)
      self.w.utf8(k)
    }
    Id => self.code(EXPR_ID)
    GeometryType => self.code(EXPR_GEOMETRY_TYPE)
    Zoom => self.code(EXPR_ZOOM)
    LineProgress => self.code(EXPR_LINE_PROGRESS)
    HeatmapDensity => self.code(EXPR_HEATMAP_DENSITY)
    Elevation => self.code(EXPR_ELEVATION)
    Not(a) => {
      self.code(EXPR_NOT)
      self.expr(a)
    }
    All(es) => {
      self.code(EXPR_ALL)
      self.exprs(es)
    }
    Any(es) => {
      self.code(EXPR_ANY)
      self.exprs(es)
    }
    Compare(op, a, b) => {
      self.code(EXPR_COMPARE)
      self.code(code_of(cmp_ops, op))
      self.expr(a)
      self.expr(b)
    }
    In(a, b) => {
      self.code(EXPR_IN)
      self.expr(a)
      self.expr(b)
    }
    Match(input, arms, other) => {
      self.code(EXPR_MATCH)
      self.expr(input)
      self.w.u32(arms.length())
      for arm in arms {
        self.w.u32(arm.0.length())
        arm.0.each(v => self.value(v))
        self.expr(arm.1)
      }
      self.expr(other)
    }
    Case(arms, other) => {
      self.code(EXPR_CASE)
      self.w.u32(arms.length())
      for arm in arms {
        self.expr(arm.0)
        self.expr(arm.1)
      }
      self.expr(other)
    }
    Coalesce(es) => {
      self.code(EXPR_COALESCE)
      self.exprs(es)
    }
    Interpolate(how, space, input, stops) => {
      self.code(EXPR_INTERPOLATE)
      match how {
        Exponential(base) => {
          self.code(0)
          self.w.f64(base)
        }
        CubicBezier(a, b, c, d) => {
          self.code(1)
          self.w.f64(a)
          self.w.f64(b)
          self.w.f64(c)
          self.w.f64(d)
        }
      }
      self.code(code_of(spaces, space))
      self.expr(input)
      self.stops(stops)
    }
    Step(input, first, stops) => {
      self.code(EXPR_STEP)
      self.expr(input)
      self.expr(first)
      self.stops(stops)
    }
    FeatureState(k) => {
      self.code(EXPR_FEATURE_STATE)
      self.w.utf8(k)
    }
    Assert(t, es) => {
      self.code(EXPR_ASSERT)
      self.expected(t)
      self.exprs(es)
    }
    Coerce(t, es) => {
      self.code(EXPR_COERCE)
      self.expected(t)
      self.exprs(es)
    }
    Call(op, es) => {
      self.code(EXPR_CALL)
      self.code(code_of(ops, op))
      self.exprs(es)
    }
    Collate(op, a, b, c) => {
      self.code(EXPR_COLLATE)
      self.code(code_of(cmp_ops, op))
      self.expr(a)
      self.expr(b)
      self.expr(c)
    }
    Accumulated => self.code(EXPR_ACCUMULATED)
    Within(polygons) => {
      self.code(EXPR_WITHIN)
      self.w.u32(polygons.length())
      polygons.each(p => self.rings(p))
    }
    Distance(shapes) => {
      self.code(EXPR_DISTANCE)
      self.w.u32(shapes.length())
      for s in shapes {
        match s {
          Point(x, y) => {
            self.code(0)
            self.w.f64(x)
            self.w.f64(y)
          }
          Line(c) => {
            self.code(1)
            self.coords(c)
          }
          Polygon(rings) => {
            self.code(2)
            self.rings(rings)
          }
          Other => self.code(3)
        }
      }
    }
  }
}

///|
fn StyleWriter::coords(self : StyleWriter, c : Array[Double]) -> Unit {
  self.w.u32(c.length())
  c.each(x => self.w.f64(x))
}

///|
fn StyleWriter::rings(self : StyleWriter, rings : Array[Array[Double]]) -> Unit {
  self.w.u32(rings.length())
  rings.each(r => self.coords(r))
}

///|
fn StyleWriter::opt_expr(self : StyleWriter, e : Expr?) -> Unit {
  match e {
    None => self.flag(false)
    Some(e) => {
      self.flag(true)
      self.expr(e)
    }
  }
}

///|
fn StyleWriter::pair(self : StyleWriter, p : (Double, Double)) -> Unit {
  self.w.f64(p.0)
  self.w.f64(p.1)
}

///|
fn StyleWriter::sides(
  self : StyleWriter,
  p : (Double, Double, Double, Double),
) -> Unit {
  self.w.f64(p.0)
  self.w.f64(p.1)
  self.w.f64(p.2)
  self.w.f64(p.3)
}

///|
fn StyleWriter::anchors(
  self : StyleWriter,
  list : Array[(TextAnchor, Double, Double)],
) -> Unit {
  self.w.u32(list.length())
  for v in list {
    self.code(code_of(anchor_values, v.0))
    self.w.f64(v.1)
    self.w.f64(v.2)
  }
}

///|
fn StyleWriter::text(self : StyleWriter, t : TextLayout) -> Unit {
  self.exprs(t.field)
  self.expr(t.size)
  self.code(code_of(placements, t.placement))
  self.w.f64(t.spacing)
  self.w.f64(t.max_angle)
  self.flag(t.keep_upright)
  self.code(code_of(anchor_values, t.anchor))
  self.pair(t.offset)
  self.code(code_of(justify_values, t.justify))
  self.anchors(t.variable)
  self.w.u32(t.variable_stops.length())
  for s in t.variable_stops {
    self.w.f64(s.0)
    self.anchors(s.1)
  }
  self.w.f64(t.max_width)
  self.w.f64(t.line_height)
  self.expr(t.padding)
  self.flag(t.allow_overlap)
  self.flag(t.ignore_placement)
  self.flag(t.vertical)
  self.opt_expr(t.sort_key)
  self.opt_expr(t.font)
  self.exprs([t.letter_spacing, t.transform, t.rotate])
  self.flag(t.cooperative)
  self.code(code_of(z_orders, t.z_order))
}

///|
fn StyleWriter::icon(self : StyleWriter, i : IconLayout) -> Unit {
  self.exprs(i.image)
  self.expr(i.size)
  self.expr(i.rotate)
  self.code(code_of(anchor_values, i.anchor))
  self.pair(i.offset)
  self.expr(i.padding)
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
    self.flag(b)
  }
  self.code(code_of(fits, i.text_fit))
  self.sides(i.text_fit_padding)
  self.flag(i.cooperative)
}

///|
fn[T] StyleWriter::opt(self : StyleWriter, v : T?, write : (T) -> Unit) -> Unit {
  match v {
    None => self.flag(false)
    Some(v) => {
      self.flag(true)
      write(v)
    }
  }
}

///|
fn StyleWriter::layer(self : StyleWriter, l : StyleLayer) -> Unit {
  self.w.utf8(l.id)
  self.code(code_of(layer_kinds, l.kind))
  self.w.utf8(l.source)
  self.w.utf8(l.source_layer)
  self.w.f64(l.min_zoom)
  self.w.f64(l.max_zoom)
  self.opt_expr(l.filter)
  self.w.u32(l.filter_id)
  for
    e in [
      l.color,
      l.opacity,
      l.width,
      l.radius,
      l.stroke_width,
      l.stroke_color,
      l.stroke_opacity,
      l.halo_color,
      l.halo_width,
    ] {
    self.expr(e)
  }
  self.opt(l.text, t => self.text(t))
  self.opt(l.icon, i => self.icon(i))
  self.opt(l.icon_paint, p => self.exprs(p.exprs()))
  self.opt(l.extrusion, x => {
    self.expr(x.height)
    self.expr(x.base)
    self.flag(x.vertical_gradient)
  })
  self.opt(l.heatmap, h => self.exprs([h.weight, h.intensity, h.color]))
  self.code(code_of(joins, l.join))
  self.code(code_of(caps, l.cap))
  self.w.f64(l.miter_limit)
  self.w.f64(l.round_limit)
  self.flag(l.antialias)
  self.opt_expr(l.outline_color)
  self.opt_expr(l.dasharray)
  self.opt_expr(l.gradient)
  self.opt_expr(l.pattern)
  self.expr(l.gap_width)
  self.expr(l.offset)
  self.expr(l.blur)
  self.expr(l.translate)
  self.flag(l.translate_viewport)
  self.flag(l.scale_with_map)
  self.flag(l.pitch_with_map)
  self.opt_expr(l.sort_key)
}

///|
fn StyleWriter::source(self : StyleWriter, s : Source) -> Unit {
  self.w.utf8(s.id)
  self.code(code_of(source_kinds, s.kind))
  self.w.u32(s.min_zoom)
  self.w.u32(s.max_zoom)
  self.w.u32(s.tile_size)
  match s.encoding {
    Mapbox => self.code(0)
    Terrarium => self.code(1)
    Gsi => self.code(2)
    Custom(r, g, b, base) => {
      self.code(3)
      self.sides((r, g, b, base))
    }
  }
  self.w.u32(s.buffer)
  self.w.f64(s.tolerance)
  match s.promote_id {
    FeatureId => self.code(0)
    Property(p) => {
      self.code(1)
      self.w.utf8(p)
    }
    ByLayer(m) => {
      self.code(2)
      self.w.u32(m.length())
      for k, v in m {
        self.w.utf8(k)
        self.w.utf8(v)
      }
    }
  }
}

///|
/// Writes `e` (None as a 0 byte) in docs/FORMATS.md "Compiled style"'s form,
/// for `read_expr`.
pub fn write_expr(w : @core.ByteWriter, e : Expr?) -> Unit {
  ({ w, } : StyleWriter).opt_expr(e)
}

///|
/// The style as display workers take it (docs/FORMATS.md "Compiled style"):
/// what tiles are made from, without the paint only the main thread draws.
pub fn Style::to_compiled(self : Style) -> Bytes {
  let out : StyleWriter = { w: @core.ByteWriter::new(), }
  out.w.u32(self.sources.length())
  self.sources.each(s => out.source(s))
  out.w.u32(self.layers.length())
  self.layers.each(l => out.layer(l))
  out.w.to_bytes()
}

///|
/// Writes cluster properties (`compile_cluster_properties`) for the GeoJSON worker
/// (docs/FORMATS.md "Compiled style"): a count, then per key its name and its map
/// and reduce expressions.
pub fn write_cluster_properties(props : Array[(String, Expr, Expr)]) -> Bytes {
  let w = StyleWriter::{ w: @core.ByteWriter::new(), }
  w.w.u32(props.length())
  for p in props {
    w.w.utf8(p.0)
    w.expr(p.1)
    w.expr(p.2)
  }
  w.w.to_bytes()
}
