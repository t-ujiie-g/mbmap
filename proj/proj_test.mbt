///|
fn near(a : (Double, Double), b : (Double, Double), tol : Double) -> Bool {
  (a.0 - b.0).abs() < tol && (a.1 - b.1).abs() < tol
}

///|
fn epsg(code : Int32) -> @proj.Crs {
  @proj.Crs::from_epsg(code).unwrap()
}

///|
const D2R : Double = 0.017453292519943295

///|
let tokyo_station : (Double, Double) = (139.7671, 35.6812)

///|
test "Tokyo Station in plane rectangular IX, UTM 54, Web Mercator and the Tokyo datum, as proj4js gives" {
  let wgs = epsg(4326)
  // proj4js 2.22.0's results (bench/proj/golden.mjs checks every CRS).
  let cases = [
    (6677, (-5995.185165978678, -35367.230132542936)),
    (2451, (-5995.185165978678, -35367.230132542936)),
    (6691, (388433.37462039513, 3949290.0134295365)),
    (3857, (15558802.401652545, 4256843.186542427)),
    (30169, (-5701.993464301608, -35723.00993903457)),
    (4301, (139.77033413284113, 35.677960647310144)),
  ]
  for c in cases {
    let (code, expected) = c
    let (x, y) = tokyo_station
    let xy = @proj.transform(wgs, epsg(code), x, y).unwrap()
    assert_true(near(xy, expected, 1.0e-6))
    assert_true(
      near(
        @proj.transform(epsg(code), wgs, xy.0, xy.1).unwrap(),
        tokyo_station,
        // A datum shift drops the height it makes, as proj4js does: about
        // 5 mm back on the Tokyo datum.
        if code == 30169 || code == 4301 {
          1.0e-7
        } else {
          1.0e-9
        },
      ),
    )
    assert_eq(epsg(code).is_geographic(), code == 4301)
  }
  // Southern UTM zones count northing from 10,000 km at the equator.
  assert_true(
    near(
      @proj.transform(wgs, epsg(32754), 141.0, -35.0).unwrap(),
      (500000.0, 6126956.93546574),
      1.0e-6,
    ),
  )
  // Plane IX straight to UTM 54.
  assert_true(
    near(
      @proj.transform(
        epsg(6677),
        epsg(6691),
        -5995.185165978678,
        -35367.230132542936,
      ).unwrap(),
      (388433.37462039513, 3949290.0134295365),
      1.0e-6,
    ),
  )
}

///|
test "definitions from PROJ strings: Lambert 93 and the British National Grid's 7-parameter shift" {
  let wgs = epsg(4326)
  let l93 = @proj.Definition::new(Lcc, 6378137.0, 6356752.314140356)
  l93.lat0 = 46.5 * D2R
  l93.long0 = 3.0 * D2R
  l93.lat1 = 49.0 * D2R
  l93.lat2 = 44.0 * D2R
  l93.x0 = 700000.0
  l93.y0 = 6600000.0
  l93.towgs84 = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
  let l93 = @proj.Crs::new(l93).unwrap()
  assert_true(
    near(
      @proj.transform(wgs, l93, 2.3522, 48.8566).unwrap(),
      (652469.022709136, 6862035.259420076),
      1.0e-6,
    ),
  )
  let osgb = @proj.Definition::new(Tmerc, 6377563.396, 6356256.91)
  osgb.lat0 = 49.0 * D2R
  osgb.long0 = -2.0 * D2R
  osgb.k0 = 0.9996012717
  osgb.x0 = 400000.0
  osgb.y0 = -100000.0
  osgb.towgs84 = [446.448, -125.157, 542.06, 0.15, 0.247, 0.842, -20.489]
  let osgb = @proj.Crs::new(osgb).unwrap()
  let xy = @proj.transform(wgs, osgb, -0.1276, 51.5072).unwrap()
  assert_true(near(xy, (530043.1949909067, 180358.2078843171), 1.0e-6))
  assert_true(
    near(
      @proj.transform(osgb, wgs, xy.0, xy.1).unwrap(),
      (-0.1276, 51.5072),
      1.0e-7,
    ),
  )
}

///|
test "geographic CRSs pass coordinates through and unknown codes are refused" {
  let wgs = epsg(4326)
  assert_true(wgs.is_geographic())
  assert_eq(@proj.transform(wgs, wgs, 1.0, 2.0), Some((1.0, 2.0)))
  assert_true(
    near(
      @proj.transform(wgs, epsg(6668), 1.0, 2.0).unwrap(),
      (1.0, 2.0),
      1.0e-12,
    ),
  )
  for code in [0, 6667, 2442, 30160, 32661, 6693, 3091, 99999] {
    assert_true(@proj.Crs::from_epsg(code) is None)
  }
}

///|
test "points out of a projection's reach and bad definitions give None" {
  let wgs = epsg(4326)
  // Web Mercator cannot reach the poles; a transverse Mercator a point on the
  // equator 90° from its meridian.
  assert_eq(@proj.transform(wgs, epsg(3857), 0.0, 90.0), None)
  assert_eq(@proj.transform(wgs, epsg(6677), 49.83333333333334, 0.0), None)
  assert_eq(@proj.transform(epsg(6677), wgs, 1.0e8, 0.0), None)
  assert_eq(@proj.transform(wgs, epsg(6677), @double.not_a_number, 0.0), None)
  // A transverse Mercator needs an ellipsoid, an oblique Mercator its line.
  assert_true(
    @proj.Crs::new(@proj.Definition::new(Tmerc, 6371000.0, 6371000.0)) is None,
  )
  assert_true(
    @proj.Crs::new(@proj.Definition::new(Omerc, 6378137.0, 6356752.3)) is None,
  )
  assert_true(@proj.Crs::new(@proj.Definition::new(LongLat, 0.0, 0.0)) is None)
  assert_true(
    @proj.Crs::new(@proj.Definition::new(LongLat, 1.0 / 0.0, 6356752.3)) is None,
  )
  let zone = @proj.Definition::new(Utm, 6378137.0, 6356752.3)
  zone.zone = 61
  assert_true(@proj.Crs::new(zone) is None)
}

///|
test "decode reads the slots docs/FORMATS.md lays out and refuses others" {
  let s = FixedArray::make(@proj.DEFINITION_SLOTS, @double.not_a_number)
  s[0] = 4.0 // Lcc
  s[1] = 6378137.0
  s[2] = 6356752.314140356
  s[3] = 0.0
  s[4] = 7.0
  for i in 5..<12 {
    s[i] = 0.0
  }
  s[12] = 0.0
  s[14] = 0.0
  s[16] = 46.5 * D2R
  s[17] = 49.0 * D2R
  s[18] = 44.0 * D2R
  s[20] = 3.0 * D2R
  s[26] = 700000.0
  s[27] = 6600000.0
  for i in 30..<34 {
    s[i] = 0.0
  }
  let d = @proj.Definition::decode(s[:]).unwrap()
  assert_true(d.proj is Lcc && d.towgs84.length() == 7 && d.zone == 0)
  let l93 = @proj.Crs::new(d).unwrap()
  assert_true(
    near(
      @proj.transform(epsg(4326), l93, 2.3522, 48.8566).unwrap(),
      (652469.022709136, 6862035.259420076),
      1.0e-6,
    ),
  )
  assert_true(@proj.Definition::decode(s[:33]) is None)
  s[4] = 2.0
  assert_true(@proj.Definition::decode(s[:]) is None)
  s[4] = 3.5
  assert_true(@proj.Definition::decode(s[:]) is None)
  s[4] = 0.0
  s[0] = 27.0
  assert_true(@proj.Definition::decode(s[:]) is None)
  s[0] = 1.5
  assert_true(@proj.Definition::decode(s[:]) is None)
  s[0] = 4.0
  s[13] = -1.0
  assert_true(@proj.Crs::new(@proj.Definition::decode(s[:]).unwrap()) is None)
}

///|
test "+R_A projects on the sphere of the ellipsoid's area, as PROJ does" {
  // PROJ 9.9's `proj +proj=mill +R_A +ellps=WGS84` (proj4js keeps a's length).
  let mill = @proj.Definition::new(Mill, 6378137.0, 6356752.314245179)
  mill.r_a = true
  let mill = @proj.Crs::new(mill).unwrap()
  assert_true(
    near(
      @proj.transform(epsg(4326), mill, 10.0, 20.0).unwrap(),
      (1111950.519781, 2253381.689608),
      1.0e-5,
    ),
  )
}

///|
test "Trig::moonbit is what a CRS computes with by default" {
  let (x, y) = tokyo_station
  let wgs = @proj.Crs::from_epsg(4326, trig=@proj.Trig::moonbit()).unwrap()
  let ix = @proj.Crs::from_epsg(6677, trig=@proj.Trig::moonbit()).unwrap()
  assert_eq(
    @proj.transform(wgs, ix, x, y),
    @proj.transform(epsg(4326), epsg(6677), x, y),
  )
}

///|
test "projections refuse what they cannot reach" {
  let wgs = epsg(4326)
  let sphere = (proj : @proj.Method) => {
    let d = @proj.Definition::new(proj, 6371000.0, 6371000.0)
    d.lat0 = 35.0 * D2R
    d.long0 = 135.0 * D2R
    d
  }
  // The far side of the globe is hidden in an orthographic view; its center's
  // antipode has no place in Lambert's azimuthal equal area.
  let ortho = @proj.Crs::new(sphere(Ortho)).unwrap()
  assert_true(@proj.transform(wgs, ortho, 135.0, 35.0) is Some(_))
  assert_eq(@proj.transform(wgs, ortho, -45.0, -35.0), None)
  let laea = @proj.Crs::new(sphere(Laea)).unwrap()
  assert_eq(@proj.transform(wgs, laea, -45.0, -35.0), None)
  assert_eq(@proj.transform(laea, wgs, 1.0e8, 0.0), None)
  // Bonne needs a standard parallel off the equator (lat_1, else lat_0).
  let bonne = sphere(Bonne)
  bonne.lat0 = 0.0
  bonne.lat1 = 0.0
  assert_true(@proj.Crs::new(bonne) is None)
  bonne.lat1 = 45.0 * D2R
  assert_true(@proj.Crs::new(bonne) is Some(_))
}
