// Expected values worked out by hand with GDAL 3.13.3's formulas: heights
// relative to the observer, each cell's horizon from its neighbors toward the
// observer (`CalcHeightLine`, `CalcHeightEdge`, `CalcHeightDiagonal`).

///|
/// A north-up geotransform with square cells of `size` and `rows` rows, its
/// origin at (0, rows * size).
fn north_up(rows : Int32, size : Double) -> FixedArray[Double] {
  [0.0, size, 0.0, rows.to_double() * size, 0.0, -size]
}

///|
fn grid(rows : Array[Array[Double]]) -> FixedArray[Double] {
  let out = []
  for row in rows {
    for v in row {
      out.push(v)
    }
  }
  FixedArray::from_array(out)
}

///|
fn run(
  values : FixedArray[Double],
  width : Int32,
  height : Int32,
  gt : FixedArray[Double],
  options : @viewshed.ViewshedOptions,
  nodata? : Double,
) -> @viewshed.ViewshedResult {
  @viewshed.viewshed(values, width, height, gt, nodata, options).unwrap()
}

///|
test "a flat plane is visible everywhere" {
  let values = FixedArray::make(25, 0.0)
  let r = run(
    values,
    5,
    5,
    north_up(5, 1.0),
    @viewshed.ViewshedOptions::new(2.5, 2.5),
  )
  assert_eq(r.width, 5)
  assert_eq(r.height, 5)
  assert_eq(r.values, FixedArray::make(25, 255.0))
  assert_eq(r.geotransform, north_up(5, 1.0))
  assert_eq(r.nodata, None)
  assert_eq(r.found_nodata, false)
}

///|
test "a wall shadows the cells behind it, with and without a target height" {
  let values : FixedArray[Double] = [0.0, 0.0, 10.0, 0.0, 0.0, 0.0, 0.0]
  let gt = north_up(1, 1.0)
  let r = run(values, 7, 1, gt, @viewshed.ViewshedOptions::new(0.5, 0.5))
  assert_eq(r.values, [255.0, 255.0, 255.0, 0.0, 0.0, 0.0, 0.0])
  let tall = run(
    values,
    7,
    1,
    gt,
    @viewshed.ViewshedOptions::new(0.5, 0.5, target_height=15.0),
  )
  assert_eq(tall.values, [255.0, 255.0, 255.0, 255.0, 0.0, 0.0, 0.0])
}

///|
test "DEM and ground modes give the height a target needs" {
  let values : FixedArray[Double] = [0.0, 0.0, 10.0, 0.0, 0.0, 0.0, 0.0]
  let gt = north_up(1, 1.0)
  let dem = run(
    values,
    7,
    1,
    gt,
    @viewshed.ViewshedOptions::new(0.5, 0.5, mode=Dem),
  )
  assert_eq(dem.values, [0.0, 0.0, 10.0, 14.0, 18.0, 22.0, 26.0])
  let ground = run(
    values,
    7,
    1,
    gt,
    @viewshed.ViewshedOptions::new(0.5, 0.5, mode=Ground),
  )
  assert_eq(ground.values, [0.0, 0.0, 0.0, 14.0, 18.0, 22.0, 26.0])
}

///|
let pillar : FixedArray[Double] = grid([
  [0.0, 0.0, 0.0, 0.0],
  [0.0, 10.0, 0.0, 0.0],
  [0.0, 0.0, 0.0, 0.0],
  [0.0, 0.0, 0.0, 0.0],
])

///|
test "a pillar casts a shadow away from an observer in the corner" {
  let r = run(
    pillar,
    4,
    4,
    north_up(4, 1.0),
    @viewshed.ViewshedOptions::new(0.5, 3.5),
  )
  assert_eq(
    r.values,
    grid([
      [255.0, 255.0, 255.0, 255.0],
      [255.0, 255.0, 0.0, 0.0],
      [255.0, 0.0, 0.0, 0.0],
      [255.0, 0.0, 0.0, 0.0],
    ]),
  )
  let ground = run(
    pillar,
    4,
    4,
    north_up(4, 1.0),
    @viewshed.ViewshedOptions::new(0.5, 3.5, mode=Ground),
  )
  assert_eq(
    ground.values,
    grid([
      [0.0, 0.0, 0.0, 0.0],
      [0.0, 0.0, 8.0, 7.0],
      [0.0, 8.0, 18.0, 16.0],
      [0.0, 7.0, 16.0, 26.0],
    ]),
  )
  let dem = run(
    pillar,
    4,
    4,
    north_up(4, 1.0),
    @viewshed.ViewshedOptions::new(0.5, 3.5, mode=Dem),
  )
  assert_eq(dem.values[5], 10.0)
  assert_eq(dem.values[6], 8.0)
}

///|
test "diagonal cell mode takes the plane through the two nearer cells" {
  let r = run(
    pillar,
    4,
    4,
    north_up(4, 1.0),
    @viewshed.ViewshedOptions::new(0.5, 3.5, mode=Ground, cell_mode=Diagonal),
  )
  let z2 = (8.0 * 2.0 + -2.0 * 1.0) / 2.0
  let z3 = (z2 * 3.0 + -2.0 * 1.0) / 3.0
  assert_eq(r.values[6], z2 - -2.0)
  assert_eq(r.values[7], z3 - -2.0)
  let min = run(
    pillar,
    4,
    4,
    north_up(4, 1.0),
    @viewshed.ViewshedOptions::new(0.5, 3.5, mode=Ground, cell_mode=Min),
  )
  assert_eq(min.values[6], 8.0)
  let max = run(
    pillar,
    4,
    4,
    north_up(4, 1.0),
    @viewshed.ViewshedOptions::new(0.5, 3.5, mode=Ground, cell_mode=Max),
  )
  assert_eq(max.values[6], 9.0)
}

///|
test "an observer on a peak sees down a concave hill but not past a convex one" {
  let gt = north_up(1, 1.0)
  let concave : FixedArray[Double] = [0.0, 5.0, 10.0, 5.0, 0.0]
  assert_eq(
    run(concave, 5, 1, gt, @viewshed.ViewshedOptions::new(2.5, 0.5)).values,
    FixedArray::make(5, 255.0),
  )
  let convex : FixedArray[Double] = [0.0, 8.0, 10.0, 8.0, 0.0]
  assert_eq(
    run(convex, 5, 1, gt, @viewshed.ViewshedOptions::new(2.5, 0.5)).values,
    [0.0, 255.0, 255.0, 255.0, 0.0],
  )
}

///|
test "max distance crops the output and marks cells beyond it" {
  let r = run(
    FixedArray::make(49, 0.0),
    7,
    7,
    north_up(7, 1.0),
    @viewshed.ViewshedOptions::new(
      3.5,
      3.5,
      max_distance=2.0,
      out_of_range_value=7.0,
    ),
  )
  assert_eq(r.width, 5)
  assert_eq(r.height, 5)
  assert_eq(r.geotransform, [1.0, 1.0, 0.0, 6.0, 0.0, -1.0])
  assert_eq(
    r.values,
    grid([
      [7.0, 7.0, 255.0, 7.0, 7.0],
      [7.0, 255.0, 255.0, 255.0, 7.0],
      [255.0, 255.0, 255.0, 255.0, 255.0],
      [7.0, 255.0, 255.0, 255.0, 7.0],
      [7.0, 7.0, 255.0, 7.0, 7.0],
    ]),
  )
}

///|
test "non-square cells measure distance in the CRS" {
  let gt : FixedArray[Double] = [0.0, 2.0, 0.0, 5.0, 0.0, -1.0]
  let r = run(
    FixedArray::make(25, 0.0),
    5,
    5,
    gt,
    @viewshed.ViewshedOptions::new(
      5.0,
      2.5,
      max_distance=2.0,
      out_of_range_value=7.0,
    ),
  )
  assert_eq(r.width, 3)
  assert_eq(r.height, 5)
  assert_eq(r.geotransform, [2.0, 2.0, 0.0, 5.0, 0.0, -1.0])
  assert_eq(
    r.values,
    grid([
      [7.0, 255.0, 7.0],
      [7.0, 255.0, 7.0],
      [255.0, 255.0, 255.0],
      [7.0, 255.0, 7.0],
      [7.0, 255.0, 7.0],
    ]),
  )
}

///|
test "earth curvature hides flat ground past the horizon" {
  let values = FixedArray::make(20, 0.0)
  let gt = north_up(1, 1000.0)
  let flat = run(
    values,
    20,
    1,
    gt,
    @viewshed.ViewshedOptions::new(500.0, 500.0, observer_height=10.0),
  )
  assert_eq(flat.values, FixedArray::make(20, 255.0))
  // A 10 m observer sees sqrt(2 * 6378137 m * 10 m / 0.85714), about 12.2 km.
  let earth = run(
    values,
    20,
    1,
    gt,
    @viewshed.ViewshedOptions::new(
      500.0,
      500.0,
      observer_height=10.0,
      semi_major=6378137.0,
    ),
  )
  let expected = FixedArray::make(20, 0.0)
  expected.fill(255.0, start=0, end=13)
  assert_eq(earth.values, expected)
  // A non-Earth ellipsoid takes -cc 1.0: sqrt(2 * 3396190 m * 10 m), 8.2 km.
  let mars = run(
    values,
    20,
    1,
    gt,
    @viewshed.ViewshedOptions::new(
      500.0,
      500.0,
      observer_height=10.0,
      semi_major=3396190.0,
    ),
  )
  let expected = FixedArray::make(20, 0.0)
  expected.fill(255.0, start=0, end=9)
  assert_eq(mars.values, expected)
  let none = run(
    values,
    20,
    1,
    gt,
    @viewshed.ViewshedOptions::new(
      500.0,
      500.0,
      observer_height=10.0,
      semi_major=6378137.0,
      curvature_coeff=0.0,
    ),
  )
  assert_eq(none.values, FixedArray::make(20, 255.0))
}

///|
test "nodata and NaN cells are used as heights and reported" {
  let gt = north_up(1, 1.0)
  let values : FixedArray[Double] = [0.0, @double.not_a_number, 0.0, 100.0]
  let r = run(values, 4, 1, gt, @viewshed.ViewshedOptions::new(0.5, 0.5))
  assert_eq(r.values, [255.0, 255.0, 255.0, 255.0])
  assert_eq(r.found_nodata, true)
  let zeros = run(
    FixedArray::make(4, 0.0),
    4,
    1,
    gt,
    @viewshed.ViewshedOptions::new(0.5, 0.5),
    nodata=0.0,
  )
  assert_eq(zeros.found_nodata, true)
  assert_eq(zeros.values, FixedArray::make(4, 255.0))
}

///|
test "an observer left of the raster stands at its own height" {
  let values : FixedArray[Double] = [5.0, 0.0, 0.0, 10.0]
  let r = run(
    values,
    4,
    1,
    north_up(1, 1.0),
    @viewshed.ViewshedOptions::new(-1.5, 0.5),
  )
  assert_eq(r.values, [255.0, 0.0, 0.0, 0.0])
}

///|
test "an observer above the raster sees its nearest row" {
  let r = run(
    FixedArray::make(9, 0.0),
    3,
    3,
    north_up(3, 1.0),
    @viewshed.ViewshedOptions::new(1.5, 4.5),
  )
  assert_eq(r.values, FixedArray::make(9, 255.0))
}

///|
test "an observer in the last column" {
  let values : FixedArray[Double] = [0.0, 8.0, 10.0, 8.0, 0.0]
  let r = run(
    values,
    5,
    1,
    north_up(1, 1.0),
    @viewshed.ViewshedOptions::new(4.5, 0.5),
  )
  assert_eq(r.values, [0.0, 0.0, 0.0, 255.0, 255.0])
}

///|
test "min distance masks cells near the observer" {
  let r = run(
    FixedArray::make(5, 0.0),
    5,
    1,
    north_up(1, 1.0),
    @viewshed.ViewshedOptions::new(
      0.5,
      0.5,
      min_distance=1.5,
      out_of_range_value=7.0,
    ),
  )
  assert_eq(r.values, [7.0, 7.0, 255.0, 255.0, 255.0])
}

///|
test "normal output is converted to bytes" {
  let r = run(
    FixedArray::make(5, 0.0),
    5,
    1,
    north_up(1, 1.0),
    @viewshed.ViewshedOptions::new(
      0.5,
      0.5,
      min_distance=1.5,
      visible_value=300.4,
      out_of_range_value=2.5,
      nodata=300.0,
    ),
  )
  assert_eq(r.values, [3.0, 3.0, 255.0, 255.0, 255.0])
  assert_eq(r.nodata, Some(0.0))
  let dem = run(
    FixedArray::make(5, 0.0),
    5,
    1,
    north_up(1, 1.0),
    @viewshed.ViewshedOptions::new(
      0.5,
      0.5,
      mode=Dem,
      out_of_range_value=-2.5,
      min_distance=1.5,
      nodata=300.0,
    ),
  )
  assert_eq(dem.values, [-2.5, -2.5, 0.0, 0.0, 0.0])
  assert_eq(dem.nodata, Some(300.0))
}

///|
test "pitch limits mask cells above or below them" {
  let values : FixedArray[Double] = [0.0, 0.0, 10.0, 0.0, 0.0]
  let gt = north_up(1, 1.0)
  let high = run(
    values,
    5,
    1,
    gt,
    @viewshed.ViewshedOptions::new(
      0.5,
      0.5,
      high_pitch=0.0,
      out_of_range_value=7.0,
    ),
  )
  assert_eq(high.values, [255.0, 255.0, 7.0, 0.0, 0.0])
  let low = run(
    values,
    5,
    1,
    gt,
    @viewshed.ViewshedOptions::new(
      0.5,
      0.5,
      low_pitch=0.0,
      out_of_range_value=7.0,
    ),
  )
  assert_eq(low.values, [7.0, 7.0, 255.0, 7.0, 7.0])
  let dem = run(
    values,
    5,
    1,
    gt,
    @viewshed.ViewshedOptions::new(0.5, 0.5, low_pitch=0.0, mode=Dem),
  )
  assert_eq(dem.values, [2.0, 2.0, 10.0, 2.0, 2.0])
}

///|
test "angles shrink the output to their slice and mask the rest" {
  let values = FixedArray::make(25, 0.0)
  let gt = north_up(5, 1.0)
  let quadrant = run(
    values,
    5,
    5,
    gt,
    @viewshed.ViewshedOptions::new(2.5, 2.5, start_angle=0.0, end_angle=90.0),
  )
  assert_eq(quadrant.width, 3)
  assert_eq(quadrant.height, 3)
  assert_eq(quadrant.geotransform, [2.0, 1.0, 0.0, 5.0, 0.0, -1.0])
  assert_eq(quadrant.values, FixedArray::make(9, 255.0))
  let half = run(
    values,
    5,
    5,
    gt,
    @viewshed.ViewshedOptions::new(
      2.5,
      2.5,
      start_angle=0.0,
      end_angle=45.0,
      out_of_range_value=7.0,
    ),
  )
  assert_eq(half.width, 3)
  assert_eq(half.height, 3)
  assert_eq(
    half.values,
    grid([[255.0, 255.0, 255.0], [255.0, 255.0, 7.0], [255.0, 7.0, 7.0]]),
  )
}

///|
test "options GDAL refuses give None" {
  let values = FixedArray::make(25, 0.0)
  let gt = north_up(5, 1.0)
  let vs = fn(gt : FixedArray[Double], options) {
    @viewshed.viewshed(values, 5, 5, gt, None, options)
  }
  assert_true(
    vs(gt, @viewshed.ViewshedOptions::new(2.5, 2.5, max_distance=-1.0)) is None,
  )
  assert_true(
    vs(gt, @viewshed.ViewshedOptions::new(2.5, 2.5, min_distance=-1.0)) is None,
  )
  assert_true(
    vs(gt, @viewshed.ViewshedOptions::new(2.5, 2.5, start_angle=360.0)) is None,
  )
  assert_true(
    vs(gt, @viewshed.ViewshedOptions::new(2.5, 2.5, end_angle=-1.0)) is None,
  )
  assert_true(
    vs(
      gt,
      @viewshed.ViewshedOptions::new(2.5, 2.5, start_angle=@double.not_a_number),
    )
    is None,
  )
  assert_true(
    vs(
      gt,
      @viewshed.ViewshedOptions::new(2.5, 2.5, low_pitch=10.0, high_pitch=10.0),
    )
    is None,
  )
  assert_true(
    vs(gt, @viewshed.ViewshedOptions::new(2.5, 2.5, high_pitch=91.0)) is None,
  )
  assert_true(
    vs(gt, @viewshed.ViewshedOptions::new(2.5, 2.5, low_pitch=-91.0)) is None,
  )
  assert_true(
    vs(gt, @viewshed.ViewshedOptions::new(@double.not_a_number, 2.5)) is None,
  )
  assert_true(vs(gt, @viewshed.ViewshedOptions::new(1.0e12, 2.5)) is None)
  assert_true(vs(gt, @viewshed.ViewshedOptions::new(2.0e9, 2.5)) is None)
  assert_true(
    vs(
      gt,
      @viewshed.ViewshedOptions::new(
        -10.0,
        2.5,
        start_angle=10.0,
        end_angle=20.0,
      ),
    )
    is None,
  )
  assert_true(
    vs(gt, @viewshed.ViewshedOptions::new(100.0, 2.5, max_distance=3.0)) is None,
  )
  assert_true(
    vs(
      [0.0, 0.0, 0.0, 5.0, 0.0, -1.0],
      @viewshed.ViewshedOptions::new(2.5, 2.5),
    )
    is None,
  )
  assert_true(
    vs([0.0, 1.0, 1.0, 5.0, 1.0, 1.0], @viewshed.ViewshedOptions::new(2.5, 2.5))
    is None,
  )
  assert_true(
    vs([0.0, 1.0, 0.0, 5.0, 0.0], @viewshed.ViewshedOptions::new(2.5, 2.5))
    is None,
  )
  assert_true(
    @viewshed.viewshed(
      values,
      5,
      4,
      gt,
      None,
      @viewshed.ViewshedOptions::new(2.5, 2.5),
    )
    is None,
  )
  assert_true(
    @viewshed.viewshed(
      values,
      0,
      5,
      gt,
      None,
      @viewshed.ViewshedOptions::new(2.5, 2.5),
    )
    is None,
  )
  assert_true(
    @viewshed.viewshed(
      [],
      70000,
      70000,
      gt,
      None,
      @viewshed.ViewshedOptions::new(2.5, 2.5),
    )
    is None,
  )
}

///|
test "hostile inputs finish" {
  let gt = north_up(5, 1.0)
  let values = FixedArray::make(25, @double.not_a_number)
  let r = @viewshed.viewshed(
    values,
    5,
    5,
    gt,
    None,
    @viewshed.ViewshedOptions::new(2.5, 2.5, max_distance=@double.not_a_number),
  )
  assert_eq(r.map(fn(r) { r.width }), Some(5))
  let far = @viewshed.viewshed(
    FixedArray::make(25, 0.0),
    5,
    5,
    gt,
    None,
    @viewshed.ViewshedOptions::new(
      -1000.0,
      2.5,
      min_distance=998.5,
      max_distance=1.0e300,
    ),
  )
  assert_true(far is None)
  let left = @viewshed.viewshed(
    FixedArray::make(25, 0.0),
    5,
    5,
    gt,
    None,
    @viewshed.ViewshedOptions::new(-3.5, 2.5, min_distance=5.0),
  )
  assert_eq(left.map(fn(r) { r.values.length() }), Some(25))
  let right = @viewshed.viewshed(
    FixedArray::make(25, 0.0),
    5,
    5,
    gt,
    None,
    @viewshed.ViewshedOptions::new(8.5, 2.5, min_distance=5.0),
  )
  assert_eq(right.map(fn(r) { r.values.length() }), Some(25))
  let curved = @viewshed.viewshed(
    FixedArray::make(25, 1.0),
    5,
    5,
    gt,
    None,
    @viewshed.ViewshedOptions::new(
      2.5,
      2.5,
      semi_major=@double.not_a_number,
      observer_height=@double.not_a_number,
    ),
  )
  assert_eq(curved.map(fn(r) { r.values.length() }), Some(25))
}

///|
test "grids past MAX_VIEWSHED_CELLS give None, products that overflow included" {
  let max = @viewshed.MAX_VIEWSHED_CELLS
  assert_true(@viewshed.grid_fits(max, 1))
  assert_true(@viewshed.grid_fits(4096, 4096))
  assert_false(@viewshed.grid_fits(max + 1, 1))
  assert_false(@viewshed.grid_fits(4097, 4096))
  assert_false(@viewshed.grid_fits(0, 5))
  let options = @viewshed.ViewshedOptions::new(0.5, 0.5)
  let gt = north_up(5, 1.0)
  assert_true(@viewshed.viewshed([], 65536, 65536, gt, None, options) is None)
}
