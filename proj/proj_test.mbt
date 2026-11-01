///|
fn near(a : (Double, Double), b : (Double, Double), tol : Double) -> Bool {
  (a.0 - b.0).abs() < tol && (a.1 - b.1).abs() < tol
}

///|
test "Tokyo Station in plane rectangular IX, UTM 54 and Web Mercator, as proj4js gives" {
  let crs = (code : Int32) => @proj.Crs::from_epsg(code).unwrap()
  let tokyo = (139.7671, 35.6812)
  // proj4js 2.22.0's results (bench/proj/golden.mjs checks every CRS).
  let cases = [
    (6677, (-5995.185165978678, -35367.230132542936)),
    (2451, (-5995.185165978678, -35367.230132542936)),
    (6691, (388433.37462039513, 3949290.0134295365)),
    (3857, (15558802.401652545, 4256843.186542427)),
  ]
  for c in cases {
    let (code, expected) = c
    let xy = crs(code).forward(tokyo.0, tokyo.1).unwrap()
    assert_true(near(xy, expected, 1.0e-6))
    assert_true(near(crs(code).inverse(xy.0, xy.1).unwrap(), tokyo, 1.0e-11))
    assert_true(!crs(code).is_geographic())
  }
  // Southern UTM zones count northing from 10,000 km at the equator.
  assert_true(
    near(
      crs(32754).forward(141.0, -35.0).unwrap(),
      (500000.0, 6126956.93546574),
      1.0e-6,
    ),
  )
  // Plane IX straight to UTM 54.
  assert_true(
    near(
      @proj.transform(
        crs(6677),
        crs(6691),
        -5995.185165978678,
        -35367.230132542936,
      ).unwrap(),
      (388433.37462039513, 3949290.0134295365),
      1.0e-6,
    ),
  )
}

///|
test "geographic CRSs pass coordinates through and unknown codes are refused" {
  let wgs = @proj.Crs::from_epsg(4326).unwrap()
  assert_true(wgs.is_geographic())
  assert_eq(wgs.forward(1.0, 2.0), Some((1.0, 2.0)))
  assert_eq(
    @proj.transform(wgs, @proj.Crs::from_epsg(6668).unwrap(), 1.0, 2.0),
    Some((1.0, 2.0)),
  )
  for code in [0, 6667, 2442, 32661, 6693, 99999] {
    assert_true(@proj.Crs::from_epsg(code) is None)
  }
  // Web Mercator cannot reach the poles; a transverse Mercator a point on the
  // equator 90° from its meridian.
  assert_eq(@proj.Crs::from_epsg(3857).unwrap().forward(0.0, 90.0), None)
  assert_eq(
    @proj.Crs::from_epsg(6677).unwrap().forward(49.83333333333334, 0.0),
    None,
  )
  assert_eq(@proj.Crs::from_epsg(6677).unwrap().inverse(1.0e8, 0.0), None)
  assert_eq(@proj.grs80.a, @proj.wgs84.a)
}
