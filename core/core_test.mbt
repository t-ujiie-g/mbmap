///|
fn near(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-9
}

///|
test "mercator round-trips and matches known values" {
  let origin = ({ lng: -180.0, lat: 0.0, } : @core.LngLat).to_mercator()
  assert_eq(origin.x, 0.0)
  assert_true(near(origin.y, 0.5))
  let tokyo : @core.LngLat = { lng: 139.7671, lat: 35.6812, }
  let back = tokyo.to_mercator().to_lnglat()
  assert_true(near(back.lng, tokyo.lng) && near(back.lat, tokyo.lat))
}

///|
test "tile_containing finds the Tokyo Station tile used by the bench fixtures" {
  let m = ({ lng: 139.7671, lat: 35.6812, } : @core.LngLat).to_mercator()
  let t = @core.tile_containing(m, 14).unwrap()
  assert_eq((t.z, t.x, t.y), (14, 14552, 6451))
  assert_true(t.mercator_bounds().contains(m.x, m.y))
  let b = t.lnglat_bounds()
  assert_true(b.min_x <= 139.7671 && 139.7671 < b.max_x)
  assert_true(b.min_y <= 35.6812 && 35.6812 < b.max_y)
}

///|
test "tile_containing clamps outside the world and rejects bad zooms" {
  let far : @core.MercatorCoord = { x: -3.0, y: 7.5, }
  let t = @core.tile_containing(far, 2).unwrap()
  assert_eq((t.x, t.y), (0, 3))
  let nan : @core.MercatorCoord = { x: @double.not_a_number, y: 1.0, }
  assert_eq(@core.tile_containing(nan, 3).unwrap().x, 0)
  assert_true(@core.tile_containing(far, -1) is None)
  assert_true(@core.tile_containing(far, @core.MAX_TILE_ZOOM + 1) is None)
}

///|
test "TileId::new validates the address" {
  assert_true(@core.TileId::new(0, 0, 0) is Some(_))
  assert_true(@core.TileId::new(1, 2, 0) is None)
  assert_true(@core.TileId::new(3, 0, -1) is None)
  assert_true(@core.TileId::new(-1, 0, 0) is None)
  assert_true(@core.TileId::new(@core.MAX_TILE_ZOOM + 1, 0, 0) is None)
  let max = 1 << @core.MAX_TILE_ZOOM
  assert_true(
    @core.TileId::new(@core.MAX_TILE_ZOOM, max - 1, max - 1) is Some(_),
  )
}

///|
test "parent and children are inverse" {
  let t = @core.TileId::new(14, 14552, 6451).unwrap()
  let kids = t.children().unwrap()
  assert_eq(kids.length(), 4)
  for k in kids {
    assert_eq(k.parent(), Some(t))
  }
  assert_eq((kids[3].x, kids[3].y), (29105, 12903))
  assert_true(@core.TileId::new(0, 0, 0).unwrap().parent() is None)
  let deepest = @core.TileId::new(@core.MAX_TILE_ZOOM, 0, 0).unwrap()
  assert_true(deepest.children() is None)
}

///|
test "tile keys are unique across zooms" {
  let seen : Map[Int64, Unit] = Map([])
  for z in 0..<=4 {
    let n = 1 << z
    for x in 0..<n {
      for y in 0..<n {
        let k = @core.TileId::new(z, x, y).unwrap().key()
        assert_false(seen.contains(k))
        seen[k] = ()
      }
    }
  }
  let max = 1 << @core.MAX_TILE_ZOOM
  let k = @core.TileId::new(@core.MAX_TILE_ZOOM, max - 1, max - 1)
    .unwrap()
    .key()
  assert_true(k > 0L)
}

///|
test "BBox empty and contains" {
  let e = @core.BBox::empty()
  assert_true(e.is_empty())
  assert_false(e.contains(0.0, 0.0))
  let b : @core.BBox = { min_x: 1.0, min_y: -1.0, max_x: 3.0, max_y: 2.0, }
  assert_false(b.is_empty())
  assert_true(b.contains(1.0, -1.0))
  assert_false(b.contains(3.0, 0.0))
}
