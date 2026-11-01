// Slope, aspect and hillshade follow GDAL 3.13's gdaldem (apps/gdaldem_lib.cpp,
// Horn's method; MIT License, Copyright (c) 2006, 2009 Matthew Perry and
// 2009-2013 Even Rouault). See NOTICE.

///|
/// An elevation grid of `width` x `height` cells, row by row from the north, each
/// `res_x` x `res_y` meters on the ground; NaN cells have no data.
pub struct Grid {
  elev : FixedArray[Double]
  width : Int32
  height : Int32
  res_x : Double
  res_y : Double
}

///|
pub fn Grid::new(
  elev : FixedArray[Double],
  width : Int32,
  height : Int32,
  res_x : Double,
  res_y : Double,
) -> Grid {
  { elev, width, height, res_x, res_y, }
}

///|
/// Cell (x, y), edges repeated outward and no data as 0 m.
fn Grid::at(self : Grid, x : Int32, y : Int32) -> Double {
  let v = self.elev[@cmp.maximum(0, @cmp.minimum(self.height - 1, y)) *
    self.width +
    @cmp.maximum(0, @cmp.minimum(self.width - 1, x))]
  if v.is_nan() {
    0.0
  } else {
    v
  }
}

///|
/// Horn's sums around cell (x, y): west minus east and north minus south.
fn Grid::horn(self : Grid, x : Int32, y : Int32) -> (Double, Double) {
  let a = self.at(x - 1, y - 1)
  let b = self.at(x, y - 1)
  let c = self.at(x + 1, y - 1)
  let d = self.at(x - 1, y)
  let f = self.at(x + 1, y)
  let g = self.at(x - 1, y + 1)
  let h = self.at(x, y + 1)
  let i = self.at(x + 1, y + 1)
  (a + d + d + g - (c + f + f + i), a + b + b + c - (g + h + h + i))
}

///|
/// Each cell's slope in degrees. Border cells repeat their neighbors (gdaldem
/// leaves them without data).
pub fn Grid::slope(self : Grid, trig : Trig) -> FixedArray[Double] {
  FixedArray::makei(self.width * self.height, k => {
    let (wx, ny) = self.horn(k % self.width, k / self.width)
    let dx = wx / self.res_x
    let dy = ny / self.res_y
    (trig.atan2)((dx * dx + dy * dy).sqrt() / 8.0, 1.0) * 180.0 / @math.PI
  })
}

///|
/// Each cell's aspect in degrees clockwise from north, toward which it faces
/// downhill; NaN where flat.
pub fn Grid::aspect(self : Grid, trig : Trig) -> FixedArray[Double] {
  FixedArray::makei(self.width * self.height, k => {
    let (wx, ny) = self.horn(k % self.width, k / self.width)
    // GDAL's east minus west and south minus north.
    let dx = -wx
    let dy = -ny
    if dx == 0.0 && dy == 0.0 {
      return @double.not_a_number
    }
    let a = (trig.atan2)(dy, -dx) * 180.0 / @math.PI
    let azimuth = if a > 90.0 { 450.0 - a } else { 90.0 - a }
    if azimuth == 360.0 {
      0.0
    } else {
      azimuth
    }
  })
}

///|
/// Each cell's shade from 1 (dark) to 255 under light from `azimuth` degrees
/// clockwise from north at `altitude` degrees, elevations scaled by `z`.
pub fn Grid::hillshade(
  self : Grid,
  trig : Trig,
  azimuth~ : Double = 315.0,
  altitude~ : Double = 45.0,
  z~ : Double = 1.0,
) -> Bytes {
  let rad = @math.PI / 180.0
  let zf = z / 8.0
  let sin_alt = (trig.sin)(altitude * rad)
  let cos_alt = (trig.cos)(altitude * rad) * zf
  let cos_az = (trig.cos)(azimuth * rad) * cos_alt
  let sin_az = (trig.sin)(azimuth * rad) * cos_alt
  let out = FixedArray::make(self.width * self.height, b'\x00')
  for k in 0..<(self.width * self.height) {
    let (wx, ny) = self.horn(k % self.width, k / self.width)
    // GDAL divides north-up rows by a negative resolution: y is north minus south.
    let x = wx / self.res_x
    let y = ny / self.res_y
    let cang = (sin_alt * 254.0 - (y * cos_az * 254.0 - x * sin_az * 254.0)) /
      (1.0 + zf * zf * (x * x + y * y)).sqrt()
    let v = if cang <= 0.0 { 1.0 } else { 1.0 + cang }
    out[k] = @cmp.minimum(255.0, v).round().to_int().to_byte()
  }
  Bytes::from_array(out[:])
}
