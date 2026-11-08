// GDAL's viewshed of an analysis worker grid through viewshed_worker: a DEM grid in ground meters per cell at
// its middle latitude (its slopes' scale), a GeoTIFF grid in its own projected CRS. Import-free; the worker
// passes what it needs (docs/FORMATS.md "Analysis worker messages").

// GRS 80 and WGS 84 (and Web Mercator's sphere): GDAL's GetSemiMajor for the CRSs grids come in.
const SEMI_MAJOR = 6378137;

export async function viewshed({ values, size, dem, raster, observer, options, check, checked, writeInput, f64sOf, module, crsId, transform, tileXY, lngLatOf }) {
  const { observerHeight, targetHeight, maxDistance, curvatureCoeff, mode, visible, invisible, outOfRange } = options ?? {};
  check([observerHeight, targetHeight, maxDistance, curvatureCoeff, mode, visible, invisible, outOfRange].every(Number.isFinite));
  const { width, height } = size;
  let geo;
  let observerXY;
  let toLngLat;
  if (dem) {
    const { tile: [z, x0, y0, tile], res } = dem;
    const n = 2 ** z;
    const [tx, ty] = tileXY(...observer, n);
    geo = [0, res, 0, 0, 0, -res];
    observerXY = [(tx - x0) * tile * res, -(ty - y0) * tile * res];
    // Cell corners back to longitude and latitude through the tiles' Web Mercator pixels.
    toLngLat = async (xy) => {
      const out = new Float64Array(xy.length);
      for (let i = 0; i < xy.length; i += 2) out.set(lngLatOf(xy[i] / res / tile + x0, -xy[i + 1] / res / tile + y0, n), i);
      return out;
    };
  } else {
    const { origin, step, crs } = raster;
    const proj = await module("proj");
    if (checked(proj, proj.crs_kind(await crsId(crs))) === 1) throw new Error("a viewshed needs a grid in a projected CRS");
    geo = [origin[0], step[0], 0, origin[1], 0, step[1]];
    observerXY = Array.from(await transform({ coords: new Float64Array(observer).buffer, from: 4326, to: crs }));
    toLngLat = (xy) => transform({ coords: xy.buffer, from: crs, to: 4326 });
  }
  const exports = await module("viewshed");
  writeInput(exports, [new Uint8Array(values.buffer)]);
  const n = exports.viewshed(width, height, ...geo, ...observerXY, observerHeight, targetHeight, maxDistance, curvatureCoeff, SEMI_MAJOR, mode, visible, invisible, outOfRange);
  const out = f64sOf(exports, n);
  const [w, h, g0, g1, , g3, , g5] = out;
  const corners = await toLngLat(new Float64Array([g0, g3, g0 + w * g1, g3 + h * g5]));
  return {
    width: w,
    height: h,
    bounds: [Math.min(corners[0], corners[2]), Math.min(corners[1], corners[3]), Math.max(corners[0], corners[2]), Math.max(corners[1], corners[3])],
    values: out.slice(8),
  };
}
