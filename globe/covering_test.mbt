// Expected tiles come from MapLibre GL JS 6.16.0's coveringTiles (`npm run globe:golden` compares more views).

///|
fn tile_triples(tiles : Array[@core.TileId]) -> Array[(Int32, Int32, Int32)] {
  tiles.map(t => (t.z, t.x, t.y))
}

///|
fn pitched_globe() -> @globe.Globe {
  @globe.Globe::new(
    {
      center: { lng: 139.7671, lat: 35.6812, },
      zoom: 6.0,
      bearing: -120.0,
      pitch: 60.0,
    },
    800.0,
    600.0,
  )
}

///|
test "covering tiles of a pitched globe vary in zoom, nearest first" {
  assert_eq(tile_triples(pitched_globe().covering_tiles()), [
    (6, 56, 25),
    (6, 57, 25),
    (6, 56, 24),
    (6, 58, 25),
    (5, 28, 13),
    (4, 13, 7),
    (4, 13, 6),
    (7, 114, 48),
    (7, 114, 49),
    (7, 115, 49),
  ])
}

///|
test "covering tiles keep to the zoom range" {
  assert_eq(
    tile_triples(pitched_globe().covering_tiles(min_zoom=2, max_zoom=6)),
    [
      (6, 56, 25),
      (6, 57, 25),
      (6, 56, 24),
      (6, 57, 24),
      (6, 58, 25),
      (5, 28, 13),
      (4, 13, 7),
      (4, 13, 6),
    ],
  )
  assert_eq(pitched_globe().covering_tiles(min_zoom=8, max_zoom=6).length(), 0)
}
