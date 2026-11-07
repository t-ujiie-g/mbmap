// GDAL's viewshed of an analysis worker grid through viewshed_worker: a DEM grid in ground meters per cell at
// its middle latitude (its slopes' scale), a GeoTIFF grid in its own projected CRS. Import-free; the worker
// passes what it needs (docs/FORMATS.md "Analysis worker messages").

// GRS 80 and WGS 84 (and Web Mercator's sphere): GDAL's GetSemiMajor for the CRSs grids come in.
const SEMI_MAJOR = 6378137;

export async function viewshed({ values, size, dem, raster, observer, options, check, checked, writeInput, outputOf, module, crsId, transform, worldWidth }) {
  const { observerHeight, targetHeight, maxDistance, curvatureCoeff, mode, visible, invisible, outOfRange } = options ?? {};
  check([observerHeight, targetHeight, maxDistance, curvatureCoeff, mode, visible, invisible, outOfRange].every(Number.isFinite));
  const { width, height } = size;
  let geo;
  let observerXY;
  let toLngLat;
  if (dem) {
    const [z, x0, y0, tile] = dem;
    const n = 2 ** z;
    const y1 = y0 + height / tile - 1;
    const lat = Math.atan(Math.sinh(Math.PI * (1 - ((y0 + y1 + 1) / 2) * (2 / n))));
    const res = (worldWidth / n / tile) * Math.cos(lat);
    const [lng, la] = observer;
    const s = Math.sin((Math.max(-85.0511, Math.min(85.0511, la)) * Math.PI) / 180);
    const px = (((lng + 180) / 360) * n - x0) * tile;
    const py = ((0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)) * n - y0) * tile;
    geo = [0, res, 0, 0, 0, -res];
    observerXY = [px * res, -py * res];
    // Cell corners back to longitude and latitude through the tiles' Web Mercator pixels.
    toLngLat = async (xy) => {
      const out = new Float64Array(xy.length);
      for (let i = 0; i < xy.length; i += 2) {
        out[i] = ((xy[i] / res / tile + x0) / n) * 360 - 180;
        out[i + 1] = (Math.atan(Math.sinh(Math.PI * (1 - (2 * (-xy[i + 1] / res / tile + y0)) / n))) * 180) / Math.PI;
      }
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
  const n = checked(exports, exports.viewshed(width, height, ...geo, ...observerXY, observerHeight, targetHeight, maxDistance, curvatureCoeff, SEMI_MAJOR, mode, visible, invisible, outOfRange));
  const out = new Float64Array(outputOf(exports, n * 8).buffer);
  const [w, h, g0, g1, , g3, , g5] = out;
  const corners = await toLngLat(new Float64Array([g0, g3, g0 + w * g1, g3 + h * g5]));
  return {
    width: w,
    height: h,
    bounds: [Math.min(corners[0], corners[2]), Math.min(corners[1], corners[3]), Math.max(corners[0], corners[2]), Math.max(corners[1], corners[3])],
    values: out.slice(8),
  };
}
