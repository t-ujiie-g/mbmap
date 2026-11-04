///|
/// Coordinates of `within` and `distance` must lie within this many degrees,
/// which bounds cheap-ruler's wrapping loops.
const MAX_GEOJSON_DEGREES : Double = 1.0e6

///|
/// A GeoJSON position's longitude and latitude, pushed onto `out`.
fn read_position(json : Json, out : Array[Double]) -> Bool {
  guard json is Array([Number(x, ..), Number(y, ..), ..]) &&
    x.abs() <= MAX_GEOJSON_DEGREES &&
    y.abs() <= MAX_GEOJSON_DEGREES else {
    return false
  }
  out.push(x)
  out.push(y)
  true
}

///|
/// A list of positions as longitude, latitude pairs.
fn read_positions(json : Json) -> Array[Double]? {
  guard json is Array(items) else { return None }
  let out = []
  for p in items {
    if !read_position(p, out) {
      return None
    }
  }
  Some(out)
}

///|
/// A polygon's rings, each with at least one position.
fn read_rings(json : Json) -> Array[Array[Double]]? {
  guard json is Array(items) && items.length() > 0 else { return None }
  let out = []
  for r in items {
    match read_positions(r) {
      Some(ring) if ring.length() > 0 => out.push(ring)
      _ => return None
    }
  }
  Some(out)
}

///|
fn read_polygons(json : Json) -> Array[Array[Array[Double]]]? {
  guard json is Array(items) else { return None }
  let out = []
  for p in items {
    guard read_rings(p) is Some(rings) else { return None }
    out.push(rings)
  }
  Some(out)
}

///|
/// A GeoJSON geometry's `type` and `coordinates`.
fn geometry_parts(json : Json) -> (String, Json)? {
  guard json is Object(o) &&
    o.get("type") is Some(String(t)) &&
    o.get("coordinates") is Some(c) else {
    return None
  }
  Some((t, c))
}

///|
/// The polygons of a Polygon or MultiPolygon geometry; None for other types.
fn polygons_of(json : Json) -> Array[Array[Array[Double]]]? {
  match geometry_parts(json) {
    Some(("Polygon", c)) => read_rings(c).map(r => [r])
    Some(("MultiPolygon", c)) => read_polygons(c)
    _ => None
  }
}

///|
/// The polygons of `within`'s argument as MapLibre's `Within.parse` takes them:
/// a Polygon or MultiPolygon, a Feature with one, or a FeatureCollection's.
fn within_polygons(json : Json) -> Array[Array[Array[Double]]]? {
  guard json is Object(o) && o.get("type") is Some(String(t)) else {
    return None
  }
  match t {
    "FeatureCollection" => {
      guard o.get("features") is Some(Array(features)) else { return None }
      let out = []
      for f in features {
        guard f is Object(fo) &&
          fo.get("geometry") is Some(g) &&
          geometry_parts(g) is Some((kind, _)) else {
          return None
        }
        if kind is ("Polygon" | "MultiPolygon") {
          guard polygons_of(g) is Some(ps) else { return None }
          out.append(ps)
        }
      }
      if out.is_empty() {
        None
      } else {
        Some(out)
      }
    }
    "Feature" =>
      match o.get("geometry") {
        Some(g) => polygons_of(g)
        None => None
      }
    _ => polygons_of(json)
  }
}

///|
/// MapLibre's `toSimpleGeometry`: a geometry's parts; None when malformed.
fn simple_shapes(json : Json) -> Array[Shape]? {
  guard json is Object(o) && o.get("type") is Some(String(t)) else {
    return None
  }
  guard o.get("coordinates") is Some(coordinates) else { return Some([Other]) }
  let point = (c : Json) => {
    let p = []
    if read_position(c, p) {
      Some(Shape::Point(p[0], p[1]))
    } else {
      None
    }
  }
  let line = (c : Json) => {
    match read_positions(c) {
      Some(l) if l.length() > 0 => Some(Shape::Line(l))
      _ => None
    }
  }
  let polygon = (c : Json) => read_rings(c).map(r => Shape::Polygon(r))
  let parts = (c : Json, part : (Json) -> Shape?) => {
    guard c is Array(items) else { return None }
    let out = []
    for i in items {
      guard part(i) is Some(s) else { return None }
      out.push(s)
    }
    Some(out)
  }
  match t {
    "Point" => point(coordinates).map(s => [s])
    "LineString" => line(coordinates).map(s => [s])
    "Polygon" => polygon(coordinates).map(s => [s])
    "MultiPoint" => parts(coordinates, point)
    "MultiLineString" => parts(coordinates, line)
    "MultiPolygon" => parts(coordinates, polygon)
    _ => Some([Other])
  }
}

///|
/// The geometries of `distance`'s argument as MapLibre's `Distance.parse` takes
/// them: a geometry, a Feature's, or every feature's of a FeatureCollection.
fn distance_shapes(json : Json) -> Array[Shape]? {
  guard json is Object(o) else { return None }
  match o.get("type") {
    Some(String("FeatureCollection")) => {
      guard o.get("features") is Some(Array(features)) else { return None }
      let out = []
      for f in features {
        guard f is Object(fo) &&
          fo.get("geometry") is Some(g) &&
          simple_shapes(g) is Some(s) else {
          return None
        }
        out.append(s)
      }
      Some(out)
    }
    Some(String("Feature")) =>
      match o.get("geometry") {
        Some(g) => simple_shapes(g)
        None => None
      }
    Some(_) if o.get("coordinates") is Some(_) => simple_shapes(json)
    _ => None
  }
}
