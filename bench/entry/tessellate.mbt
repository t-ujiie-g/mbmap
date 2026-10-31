///|
const MODE_FILL = 1

///|
const MODE_LINE = 2

///|
let fill_tess : @tess.FillTessellator = @tess.FillTessellator::new()

///|
let line_tess : @tess.LineTessellator = @tess.LineTessellator::new()

///|
let fills : @tess.FillBuffers = @tess.FillBuffers::new()

///|
let lines : @tess.LineBuffers = @tess.LineBuffers::new()

///|
let feature_geometry : @mvt.Geometry = @mvt.Geometry::new()

///|
fn number(v : @mvt.Value?) -> Double {
  match v {
    Some(Int(i) | SInt(i)) => i.to_double()
    Some(UInt(u)) => u.to_double()
    Some(Float(f)) => f.to_double()
    Some(Double(d)) => d
    _ => @double.not_a_number
  }
}

///|
/// How bench/maplibre/style.json draws a feature; `passes` counts the line
/// layers it belongs to (road features under road-casing are drawn twice).
priv enum Draw {
  Skip
  Fill
  Line(join~ : @tess.LineJoin, cap~ : @tess.LineCap, passes~ : Int32)
}

///|
/// The style's layers and filters for feature `i`, hard-coded.
fn draw_of(
  layer : @mvt.Layer,
  i : Int32,
  rd_ctg : Int32?,
  sngl_dbl : Int32?,
) -> Draw {
  let value = (key : Int32?) => {
    match key {
      Some(k) => number(layer.property(i, k))
      None => @double.not_a_number
    }
  }
  match (layer.name, layer.geom_type(i)) {
    ("waterarea" | "structurea" | "building", Polygon) => Fill
    ("building", LineString) | ("contour" | "river" | "boundary", _) =>
      Line(join=Miter, cap=Butt, passes=1)
    ("railway", _) => {
      let s = value(sngl_dbl)
      if s >= 1.0 && s <= 4.0 {
        Line(join=Miter, cap=Butt, passes=1)
      } else {
        Skip
      }
    }
    ("road", _) => {
      let c = value(rd_ctg)
      Line(
        join=Round,
        cap=Round,
        passes=if c == 0.0 || c == 1.0 { 2 } else { 1 },
      )
    }
    _ => Skip
  }
}

///|
/// Tessellates what bench/maplibre/style.json draws; `mode` bits pick fills
/// and lines (neither: decode only). Returns vertices (points for mode 0), or -1.
fn tessellate_tile(bytes : BytesView, mode : Int32) -> Int32 {
  fills.clear()
  lines.clear()
  let tile = @mvt.Tile::parse(bytes) catch { _ => return -1 }
  let mut decoded = 0
  for layer in tile.layers {
    let rd_ctg = layer.key_index("rdCtg")
    let sngl_dbl = layer.key_index("snglDbl")
    for i in 0..<layer.length() {
      let draw = draw_of(layer, i, rd_ctg, sngl_dbl)
      if draw is Skip {
        continue
      }
      if !layer.decode_geometry(i, feature_geometry) {
        return -1
      }
      let g = feature_geometry
      decoded += g.num_points()
      match draw {
        Fill if (mode & MODE_FILL) != 0 =>
          fill_tess.add_polygons(g.coords[:], g.ring_ends[:], fills)
        Line(join~, cap~, passes~) if (mode & MODE_LINE) != 0 =>
          for _ in 0..<passes {
            for r in 0..<g.num_rings() {
              line_tess.add_line(
                g.coords[:],
                g.ring_start(r),
                g.ring_ends[r],
                lines,
                join~,
                cap~,
              )
            }
          }
        _ => ()
      }
    }
  }
  if mode == 0 {
    decoded
  } else {
    fills.num_vertices() + lines.num_vertices()
  }
}

///|
fn fnv(h : Int32, v : Int32) -> Int32 {
  (h ^ v) * 0x01000193
}

///|
/// FNV-1a over every polygon feature's fill vertices then indices, in tile
/// order, for comparing against the JS pipeline (classifyRings + earcut).
/// Also appends each feature's own hash to `feature_hashes`.
fn fill_hash(bytes : BytesView, feature_hashes : Array[Int32]) -> Int32 {
  let tile = @mvt.Tile::parse(bytes) catch { _ => return 0 }
  let mut total = 0x811c9dc5
  for layer in tile.layers {
    for i in 0..<layer.length() {
      if layer.geom_type(i) is Polygon {
        if !layer.decode_geometry(i, feature_geometry) {
          return 0
        }
        fills.clear()
        let g = feature_geometry
        fill_tess.add_polygons(g.coords[:], g.ring_ends[:], fills)
        let mut h = 0x811c9dc5
        for v in fills.vertices {
          h = fnv(h, v)
        }
        for v in fills.indices {
          h = fnv(h, v)
        }
        feature_hashes.push(h)
        total = fnv(total, h)
      }
    }
  }
  total
}

///|
/// Vertex and index counts of the last `tessellate_tile` call, fills then lines.
#export_name("last_counts")
pub fn last_counts(which : Int32) -> Int32 {
  match which {
    0 => fills.num_vertices()
    1 => fills.indices.length()
    2 => lines.num_vertices()
    _ => lines.indices.length()
  }
}
