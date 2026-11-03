///|
test "elevations decode GSI, Mapbox, Terrarium and custom RGB" {
  let px = (r : Int32, g : Int32, b : Int32) => {
    [r.to_byte(), g.to_byte(), b.to_byte(), b'\xff']
  }
  let rgba = Bytes::from_array(
    [..px(0, 0, 100), ..px(0x80, 0, 0), ..px(0xff, 0xff, 0xff), ..px(1, 2, 3)],
  )
  let gsi = @raster.elevations(rgba[:], @raster.Unpack::gsi())
  assert_eq(
    (gsi[0], gsi[2], gsi[3]),
    (1.0, -0.01, 65536.0 * 0.01 + 2.0 * 2.56 + 0.03),
  )
  assert_true(gsi[1].is_nan())
  let mapbox = @raster.elevations(rgba[:], @raster.Unpack::mapbox())
  assert_eq(mapbox[0], 10.0 - 10000.0)
  let zero = Bytes::from_array(px(128, 0, 0))
  assert_eq(@raster.elevations(zero[:], @raster.Unpack::terrarium())[0], 0.0)
  let custom : @raster.Unpack = {
    r: 1.0,
    g: 2.0,
    b: 3.0,
    base: 4.0,
    gsi: false,
  }
  assert_eq(@raster.elevations(rgba[:], custom)[3], 1.0 + 4.0 + 9.0 - 4.0)
}

///|
test "hillshade_slopes keeps flat ground at 128 and leans with the slope" {
  let n = 4
  let flat = FixedArray::make(n * n, 12.0)
  let f = @raster.hillshade_slopes(flat, n, 15)
  assert_true(f.iter().all(b => b == b'\x80'))
  // Rising eastward by 100 m per pixel (a pixel is about 300 m here): x slope
  // up, y slope flat.
  let east = FixedArray::makei(n * n, i => (i % n).to_double() * 100.0)
  let e = @raster.hillshade_slopes(east, n, 15)
  // Pixel (x, y) of the tile is (x + 1, y + 1) past the border.
  let at = (x : Int32, y : Int32) => ((y + 1) * (n + 2) + x + 1) * 2
  assert_eq(e.length(), (n + 2) * (n + 2) * 2)
  assert_true(e[at(1, 1)] > b'\x80')
  assert_eq(e[at(1, 1) + 1], b'\x80')
  // The edge repeats its own pixels, so half the rise shows there, none past it.
  assert_true(e[at(0, 1)] < e[at(1, 1)])
  assert_eq(e[at(-1, 1)], b'\x80')
  // Rising southward, and no data as 0 m.
  let south = FixedArray::makei(n * n, i => {
    if i == 0 {
      @double.not_a_number
    } else {
      (i / n).to_double() * 100.0
    }
  })
  let s = @raster.hillshade_slopes(south, n, 15)
  assert_eq(s[at(2, 2)], b'\x80')
  assert_true(s[at(2, 2) + 1] > b'\x80')
}

///|
test "edge_slopes give a tile's border the slopes of the whole area" {
  // A 2n x 2n surface at z15 is four n x n tiles at z16, with the same scale.
  let n = 6
  let height = (x : Int32, y : Int32) => {
    (x * x).to_double() * 3.0 +
    (y * 7).to_double() +
    (x * y % 5).to_double() * 20.0
  }
  let whole = FixedArray::makei(4 * n * n, i => height(i % (2 * n), i / (2 * n)))
  let big = @raster.hillshade_slopes(whole, 2 * n, 15)
  let tile = (tx : Int32, ty : Int32) => {
    FixedArray::makei(n * n, i => height(tx * n + i % n, ty * n + i / n))
  }
  let edges = (tx : Int32, ty : Int32) => @raster.dem_edges(tile(tx, ty), n)
  let at = (x : Int32, y : Int32) => {
    let i = ((y + 1) * (2 * n + 2) + x + 1) * 2
    (big[i], big[i + 1])
  }
  let right = @raster.edge_slopes(edges(0, 0), edges(1, 0), 3, n, 16)
  let bottom = @raster.edge_slopes(edges(0, 0), edges(0, 1), 1, n, 16)
  let left = @raster.edge_slopes(edges(1, 1), edges(0, 1), 2, n, 16)
  let top = @raster.edge_slopes(edges(1, 1), edges(1, 0), 0, n, 16)
  // Corners need the diagonal tile, so only the pixels between them match.
  for i in 1..<(n - 1) {
    assert_eq((right[i * 2], right[i * 2 + 1]), at(n - 1, i))
    assert_eq((bottom[i * 2], bottom[i * 2 + 1]), at(i, n - 1))
    assert_eq((left[i * 2], left[i * 2 + 1]), at(n, n + i))
    assert_eq((top[i * 2], top[i * 2 + 1]), at(n + i, n))
  }
  // Inside a tile, its own slopes already match.
  let own = @raster.hillshade_slopes(tile(0, 0), n, 16)
  let i = (3 * (n + 2) + 3) * 2
  assert_eq((own[i], own[i + 1]), at(2, 2))
}
