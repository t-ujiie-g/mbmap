// Rings ported from @terraformer/arcgis 2.2.2: MIT License, Copyright (c) 2012-2026 Environmental
// Systems Research Institute, Inc. See NOTICE.

///|
/// Reads an ArcGIS REST feature set (a query's `f=json`) as @terraformer/arcgis's
/// `arcgisToGeoJSON` makes GeoJSON of it: rings wound as RFC 7946 wants and holes
/// given to the outer ring that holds them; each feature's id from `objectIdFieldName`,
/// else `OBJECTID` or `FID`. Gives the table and whether `exceededTransferLimit` is set.
/// `slow_number` as `read_geojson`'s.
pub fn read_esri_json(
  bytes : BytesView,
  slow_number~ : (Int32, Int32) -> Double,
) -> (@geom.Table, Bool) raise ReadError {
  esri_json_table(
    bytes,
    slow_number,
    @geom.MAX_TABLE_POINTS,
    @geom.MAX_TABLE_CELLS,
  )
}

///|
fn esri_json_table(
  bytes : BytesView,
  slow_number : (Int32, Int32) -> Double,
  max_points : Int32,
  max_cells : Int32,
) -> (@geom.Table, Bool) raise ReadError {
  let p : Parser = {
    b: bytes,
    slow_number,
    pos: 0,
    error: None,
    depth: 0,
    out: @geom.TableBuilder::new(),
    keys: [],
    next_key: 0,
    max_points,
    max_cells,
  }
  let mut features = -1
  let mut id_field : String? = None
  let mut exceeded = false
  p.object((s, e, esc) => {
    if esc {
      p.skip()
    } else if p.matches(s, e, "features") {
      p.peek() |> ignore
      features = p.pos
      p.skip()
    } else if p.matches(s, e, "objectIdFieldName") {
      if p.prop() is Str(name) {
        id_field = Some(name)
      }
    } else if p.matches(s, e, "exceededTransferLimit") {
      exceeded = p.prop() is Bool(true)
    } else if p.matches(s, e, "error") {
      let at = p.pos
      let mut message = ""
      if p.peek() == '{'.to_int() {
        p.object((ks, ke, kesc) => {
          if !kesc && p.matches(ks, ke, "message") {
            if p.prop() is Str(m) {
              message = m
            }
          } else {
            p.skip()
          }
        })
      } else {
        p.skip()
      }
      p.pos = at
      p.fail("ArcGIS error: \{message}")
    } else {
      p.skip()
    }
  })
  if p.error is None && p.peek() != -1 {
    p.fail("unexpected data after the feature set")
  }
  if p.error is None && features < 0 {
    p.pos = 0
    p.fail("not an ArcGIS feature set")
  }
  if p.error is None {
    let shapes = Shapes::new()
    p.pos = features
    p.array(() => esri_feature(p, shapes, id_field))
  }
  match p.error {
    Some((pos, m)) => raise Invalid(format="ArcGIS JSON", pos~, m)
    None => (p.out.finish(), exceeded)
  }
}

///|
/// The id `arcgisToGeoJSON` gives a feature of `props`: the first of `id_field`,
/// `OBJECTID` and `FID` that holds a number or a string.
fn esri_id(
  props : Array[(String, @geom.Prop)],
  id_field : String?,
) -> @geom.Prop? {
  let keys = match id_field {
    Some(f) => [f, "OBJECTID", "FID"]
    None => ["OBJECTID", "FID"]
  }
  for key in keys {
    let mut last = None
    for p in props {
      if p.0 == key {
        last = Some(p.1)
      }
    }
    match last {
      Some(Num(_) as v) | Some(Str(_) as v) => return Some(v)
      _ => ()
    }
  }
  None
}

///|
/// Adds the feature at the parser's position: its attributes and its geometry.
fn esri_feature(p : Parser, shapes : Shapes, id_field : String?) -> Unit {
  let props = []
  shapes.clear()
  if p.peek() != '{'.to_int() {
    p.fail("expected a feature")
    return
  }
  p.object((s, e, esc) => {
    if esc {
      p.skip()
    } else if p.matches(s, e, "attributes") {
      if p.peek() == '{'.to_int() {
        p.object((ks, ke, kesc) => props.push((p.key(ks, ke, kesc), p.prop())))
      } else {
        p.skip()
      }
    } else if p.matches(s, e, "geometry") {
      if p.peek() == '{'.to_int() {
        esri_geometry(p, shapes)
      } else {
        p.skip()
      }
    } else {
      p.skip()
    }
  })
  if p.out.table.coords.length() / 2 + shapes.points() > p.max_points {
    p.fail("too many points")
  }
  if p.error is None {
    shapes.emit(
      p.out,
      props,
      None,
      id=esri_id(props, id_field),
      max_cells=p.max_cells,
    )
    p.check_properties()
  }
}

///|
/// The x and y of the position at the parser (more values ignored), pushed to `into`.
fn esri_position(p : Parser, into : Array[Double]) -> Unit {
  let mut n = 0
  p.array(() => {
    let v = p.number()
    if n < 2 {
      into.push(v)
    }
    n += 1
  })
  if n < 2 && p.error is None {
    p.fail("a position needs x and y")
  }
}

///|
/// The lists of positions at the parser (`paths`, `rings`), each flat x, y.
fn esri_paths(p : Parser) -> Array[Array[Double]] {
  let out = []
  p.array(() => {
    let path = []
    p.array(() => esri_position(p, path))
    out.push(path)
  })
  out
}

///|
/// Reads a geometry object into `shapes` as `arcgisToGeoJSON` reads it: an envelope
/// over rings over paths over points over a point when it has several.
fn esri_geometry(p : Parser, s : Shapes) -> Unit {
  let xy : FixedArray[Double?] = FixedArray::make(6, None)
  let mut points : Array[Double]? = None
  let mut paths : Array[Array[Double]]? = None
  let mut rings : Array[Array[Double]]? = None
  let slot = ["x", "y", "xmin", "ymin", "xmax", "ymax"]
  p.object((k, e, esc) => {
    let at = if esc {
      -1
    } else {
      slot.search_by(name => p.matches(k, e, name)).unwrap_or(-1)
    }
    if at >= 0 {
      if p.prop() is Num(v) {
        xy[at] = Some(v)
      }
    } else if !esc && p.matches(k, e, "points") {
      let flat = []
      p.array(() => esri_position(p, flat))
      points = Some(flat)
    } else if !esc && p.matches(k, e, "paths") {
      paths = Some(esri_paths(p))
    } else if !esc && p.matches(k, e, "rings") {
      rings = Some(esri_paths(p))
    } else {
      p.skip()
    }
  })
  if p.error is Some(_) {
    return
  }
  match (xy[2], xy[3], xy[4], xy[5], rings, paths, points, xy[0], xy[1]) {
    (Some(x0), Some(y0), Some(x1), Some(y1), _, _, _, _, _) => {
      for c in [x1, y1, x0, y1, x0, y0, x1, y0, x1, y1] {
        s.coords.push(c)
      }
      s.end_ring()
      s.end_part()
      s.end_member(Polygon)
    }
    (_, _, _, _, Some(r), _, _, _, _) => esri_rings(r, s)
    (_, _, _, _, _, Some(lines), _, _, _) => {
      for line in lines {
        for c in line {
          s.coords.push(c)
        }
        s.end_ring()
        s.end_part()
      }
      s.end_member(
        if lines.length() == 1 {
          LineString
        } else {
          MultiLineString
        },
      )
    }
    (_, _, _, _, _, _, Some(flat), _, _) => {
      for c in flat {
        s.coords.push(c)
      }
      s.end_ring()
      s.end_part()
      s.end_member(MultiPoint)
    }
    (_, _, _, _, _, _, _, Some(x), Some(y)) => {
      s.point(x, y)
      s.end_ring()
      s.end_part()
      s.end_member(Point)
    }
    _ => ()
  }
}

///|
/// terraformer's `ringIsClockwise` of the flat ring `r`.
fn ring_is_clockwise(r : Array[Double]) -> Bool {
  let mut total = 0.0
  let mut i = 0
  while i + 3 < r.length() {
    total += (r[i + 2] - r[i]) * (r[i + 3] + r[i + 1])
    i += 2
  }
  total >= 0.0
}

///|
/// terraformer's `edgeIntersectsEdge` of edges a1 a2 and b1 b2 (flat pairs).
fn edge_intersects_edge(
  a : Array[Double],
  i : Int32,
  b : Array[Double],
  j : Int32,
) -> Bool {
  let (a1x, a1y, a2x, a2y) = (a[i], a[i + 1], a[i + 2], a[i + 3])
  let (b1x, b1y, b2x, b2y) = (b[j], b[j + 1], b[j + 2], b[j + 3])
  let ua_t = (b2x - b1x) * (a1y - b1y) - (b2y - b1y) * (a1x - b1x)
  let ub_t = (a2x - a1x) * (a1y - b1y) - (a2y - a1y) * (a1x - b1x)
  let u_b = (b2y - b1y) * (a2x - a1x) - (b2x - b1x) * (a2y - a1y)
  if u_b != 0.0 {
    let ua = ua_t / u_b
    let ub = ub_t / u_b
    ua >= 0.0 && ua <= 1.0 && ub >= 0.0 && ub <= 1.0
  } else {
    false
  }
}

///|
/// terraformer's `arrayIntersectsArray`: whether an edge of `a` meets one of `b`.
fn rings_intersect(a : Array[Double], b : Array[Double]) -> Bool {
  let mut i = 0
  while i + 3 < a.length() {
    let mut j = 0
    while j + 3 < b.length() {
      if edge_intersects_edge(a, i, b, j) {
        return true
      }
      j += 2
    }
    i += 2
  }
  false
}

///|
/// terraformer's `coordinatesContainPoint` of ring `r` and point (x, y).
fn ring_contains_point(r : Array[Double], x : Double, y : Double) -> Bool {
  let n = r.length() / 2
  let mut contains = false
  let mut j = n - 1
  for i in 0..<n {
    let (xi, yi, xj, yj) = (r[i * 2], r[i * 2 + 1], r[j * 2], r[j * 2 + 1])
    if ((yi <= y && y < yj) || (yj <= y && y < yi)) &&
      x < (xj - xi) * (y - yi) / (yj - yi) + xi {
      contains = !contains
    }
    j = i
  }
  contains
}

///|
/// The flat ring `r` with its points in reverse order.
fn reversed_ring(r : Array[Double]) -> Array[Double] {
  let out = Array(capacity=r.length())
  let mut i = r.length() - 2
  while i >= 0 {
    out.push(r[i])
    out.push(r[i + 1])
    i -= 2
  }
  out
}

///|
/// terraformer's `convertRingsToGeoJSON`: rings closed; clockwise ones are outer
/// rings, wound counter-clockwise; the others holes, wound clockwise, given to the
/// last outer ring that holds them (else one they cross, else made outer rings).
fn esri_rings(rings : Array[Array[Double]], s : Shapes) -> Unit {
  let outers : Array[Array[Array[Double]]] = []
  let holes = []
  for ring in rings {
    let r = ring.copy()
    let n = r.length()
    if n >= 2 && (r[0] != r[n - 2] || r[1] != r[n - 1]) {
      r.push(r[0])
      r.push(r[1])
    }
    if r.length() < 8 {
      continue
    }
    if ring_is_clockwise(r) {
      outers.push([reversed_ring(r)])
    } else {
      holes.push(reversed_ring(r))
    }
  }
  let uncontained = []
  while holes.pop() is Some(hole) {
    let mut contained = false
    for x = outers.length() - 1; x >= 0; x = x - 1 {
      let outer = outers[x][0]
      if !rings_intersect(outer, hole) &&
        ring_contains_point(outer, hole[0], hole[1]) {
        outers[x].push(hole)
        contained = true
        break
      }
    }
    if !contained {
      uncontained.push(hole)
    }
  }
  while uncontained.pop() is Some(hole) {
    let mut crossing = false
    for x = outers.length() - 1; x >= 0; x = x - 1 {
      if rings_intersect(outers[x][0], hole) {
        outers[x].push(hole)
        crossing = true
        break
      }
    }
    if !crossing {
      outers.push([reversed_ring(hole)])
    }
  }
  for polygon in outers {
    for r in polygon {
      for c in r {
        s.coords.push(c)
      }
      s.end_ring()
    }
    s.end_part()
  }
  s.end_member(if outers.length() == 1 { Polygon } else { MultiPolygon })
}
