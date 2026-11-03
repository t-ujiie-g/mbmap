///|
/// The RGB unpacking of a `raster-dem` source's encoding.
fn unpack_of(e : @style.DemEncoding) -> @raster.Unpack {
  match e {
    Mapbox => @raster.Unpack::mapbox()
    Terrarium => @raster.Unpack::terrarium()
    Gsi => @raster.Unpack::gsi()
    Custom(r, g, b, base) => { r, g, b, base, gsi: false, }
  }
}

///|
/// What the hillshade layers of DEM source `source` need of RGBA tile `rgba`:
/// slopes, border elevations (f64) and every elevation (f32, no data as 0 m).
/// None (see `error`) for another source or a malformed tile.
pub fn TileProcessor::dem_tile(
  self : TileProcessor,
  source : Int32,
  rgba : BytesView,
  size : Int32,
  z : Int32,
) -> Bytes? {
  guard source >= 0 &&
    source < self.style.sources.length() &&
    self.style.sources[source] is { kind: RasterDem, encoding, .. } else {
    self.error = "no DEM source \{source}"
    return None
  }
  if size <= 0 || size > 1024 || rgba.length() != size * size * 4 {
    self.error = "DEM tile is not \{size} x \{size} RGBA"
    return None
  }
  let elev = @raster.elevations(rgba, unpack_of(encoding))
  let w = @core.ByteWriter::new()
  for b in @raster.hillshade_slopes(elev, size, z, pow=self.trig.pow) {
    w.u8(b.to_int())
  }
  for v in @raster.dem_edges(elev, size) {
    w.f64(v)
  }
  for v in elev {
    w.f32(if v.is_nan() { 0.0 } else { v })
  }
  Some(w.to_bytes())
}
