// Port of GeographicLib's geographiclib-geodesic 2.2.0 (src/PolygonArea.js),
// MIT License, Copyright (c) Charles Karney (2011-2022). See NOTICE. Edges
// are added by their end points only (no `AddEdge`).

///|
/// 1 or -1 when the edge from `lon1` to `lon2` crosses the prime meridian
/// eastward or westward, else 0.
fn transit(lon1 : Double, lon2 : Double) -> Int32 {
  let (lon12, _) = ang_diff(lon1, lon2)
  let lon1 = ang_normalize(lon1)
  let lon2 = ang_normalize(lon2)
  if lon12 > 0.0 && ((lon1 < 0.0 && lon2 >= 0.0) || (lon1 > 0.0 && lon2 == 0.0)) {
    1
  } else if lon12 < 0.0 && lon1 >= 0.0 && lon2 < 0.0 {
    -1
  } else {
    0
  }
}

///|
/// The perimeter (meters) and area (square meters) of a geodesic polygon, or
/// the length of a polyline, built a vertex at a time.
pub struct PolygonArea {
  priv geod : Geodesic
  polyline : Bool
  priv area0 : Double
  priv areasum : Accumulator
  priv perimetersum : Accumulator
  priv mut crossings : Int32
  priv mut lat0 : Double
  priv mut lon0 : Double
  priv mut lat : Double
  priv mut lon : Double
  priv mut num : Int32
}

///|
/// An empty polygon (or polyline) on `self`.
pub fn Geodesic::polygon(
  self : Geodesic,
  polyline~ : Bool = false,
) -> PolygonArea {
  {
    geod: self,
    polyline,
    area0: 4.0 * PI * self.c2,
    areasum: Accumulator::new(0.0),
    perimetersum: Accumulator::new(0.0),
    crossings: 0,
    lat0: nan,
    lon0: nan,
    lat: nan,
    lon: nan,
    num: 0,
  }
}

///|
/// Adds the vertex (`lat`, `lon`) in degrees, and the edge to it from the
/// previous one.
pub fn PolygonArea::add_point(
  self : PolygonArea,
  lat : Double,
  lon : Double,
) -> Unit {
  if self.num == 0 {
    self.lat0 = lat
    self.lat = lat
    self.lon0 = lon
    self.lon = lon
  } else {
    let t = self.geod.inverse_int(self.lat, self.lon, lat, lon, !self.polyline)
    self.perimetersum.add(t.s12)
    if !self.polyline {
      self.areasum.add(t.area)
      self.crossings += transit(self.lon, lon)
    }
    self.lat = lat
    self.lon = lon
  }
  self.num += 1
}

///|
/// The perimeter of the polygon (closed back to its first vertex) or the
/// length of the polyline in meters, and the polygon's area in square meters
/// (NaN for a polyline). Counter-clockwise rings count positive unless
/// `reverse`; with `sign`, a ring the other way gives a negative area instead
/// of the rest of the earth's.
pub fn PolygonArea::compute(
  self : PolygonArea,
  reverse~ : Bool = false,
  sign~ : Bool = true,
) -> (Double, Double) {
  if self.num < 2 {
    return (0.0, if self.polyline { nan } else { 0.0 })
  }
  if self.polyline {
    return (self.perimetersum.sum(0.0), nan)
  }
  let t = self.geod.inverse_int(self.lat, self.lon, self.lat0, self.lon0, true)
  let perimeter = self.perimetersum.sum(t.s12)
  let area = self.areasum.copy()
  area.add(t.area)
  let area0 = self.area0
  let crossings = self.crossings + transit(self.lon, self.lon0)
  area.remainder(area0)
  if (crossings & 1) != 0 {
    area.add((if area.sum(0.0) < 0.0 { 1.0 } else { -1.0 }) * area0 / 2.0)
  }
  if !reverse {
    area.negate()
  }
  if sign {
    if area.sum(0.0) > area0 / 2.0 {
      area.add(-area0)
    } else if area.sum(0.0) <= -area0 / 2.0 {
      area.add(area0)
    }
  } else if area.sum(0.0) >= area0 {
    area.add(-area0)
  } else if area.sum(0.0) < 0.0 {
    area.add(area0)
  }
  (perimeter, 0.0 + area.sum(0.0))
}

///|
/// The number of vertices added.
pub fn PolygonArea::count(self : PolygonArea) -> Int32 {
  self.num
}
