///|
/// Latitude limit of Web Mercator (the world is a square).
const MAX_LATITUDE : Double = 85.051128779806604

///|
pub(all) struct LngLat {
  lng : Double
  lat : Double
} derive(Debug, Eq)

///|
/// Position in Web Mercator world space: (0, 0) is the north-west corner and
/// (1, 1) the south-east corner.
pub(all) struct MercatorCoord {
  x : Double
  y : Double
} derive(Debug, Eq)

///|
fn mercator_x_from_lng(lng : Double) -> Double {
  (180.0 + lng) / 360.0
}

///|
/// Latitudes beyond `MAX_LATITUDE` map outside [0, 1].
fn mercator_y_from_lat(lat : Double) -> Double {
  (
    180.0 -
    180.0 /
    @math.PI *
    @math.ln(@math.tan(@math.PI / 4.0 + lat * @math.PI / 360.0))
  ) /
  360.0
}

///|
fn lng_from_mercator_x(x : Double) -> Double {
  x * 360.0 - 180.0
}

///|
fn lat_from_mercator_y(y : Double) -> Double {
  360.0 /
  @math.PI *
  @math.atan(@math.exp((180.0 - y * 360.0) * @math.PI / 180.0)) -
  90.0
}

///|
pub fn LngLat::to_mercator(self : LngLat) -> MercatorCoord {
  { x: mercator_x_from_lng(self.lng), y: mercator_y_from_lat(self.lat), }
}

///|
pub fn MercatorCoord::to_lnglat(self : MercatorCoord) -> LngLat {
  { lng: lng_from_mercator_x(self.x), lat: lat_from_mercator_y(self.y), }
}
