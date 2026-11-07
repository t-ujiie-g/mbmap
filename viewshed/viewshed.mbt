// A port of GDAL 3.13.3's viewshed (alg/viewshed/viewshed.cpp,
// viewshed_executor.cpp; MIT License, (c) 2024 info@hobu.co) with the
// defaults of apps/gdal_viewshed.cpp. See NOTICE.

///|
/// The most input cells `viewshed` takes.
pub const MAX_VIEWSHED_CELLS : Int32 = 16_777_216

///|
/// Observer pixel coordinates beyond this many cells from the raster's origin
/// are refused (GDAL's int arithmetic would overflow on them).
const MAX_OBSERVER_PIXEL : Int32 = 1_073_741_824

///|
/// gdal_viewshed's `-om`: `Normal` writes the visibility values (Byte), `Dem`
/// and `Ground` the height above the datum or the ground a target needs to be
/// seen (Float64).
pub(all) enum ViewshedMode {
  Normal
  Dem
  Ground
}

///|
/// How a cell's horizon height is taken from its neighbors toward the observer
/// (GDAL's `GVM_*`; gdal_viewshed always uses `Edge`).
pub(all) enum CellMode {
  Diagonal
  Edge
  Max
  Min
}

///|
/// gdal_viewshed's options (`gdal raster viewshed`'s for the min distance, angles
/// and pitches). `curvature_coeff` None acts as no `-cc`; `semi_major` is GDAL's
/// `GetSemiMajor` of the CRS in meters, None for none (no curvature correction).
pub(all) struct ViewshedOptions {
  observer_x : Double
  observer_y : Double
  observer_height : Double
  target_height : Double
  max_distance : Double
  min_distance : Double
  start_angle : Double
  end_angle : Double
  low_pitch : Double
  high_pitch : Double
  curvature_coeff : Double?
  semi_major : Double?
  visible_value : Double
  invisible_value : Double
  out_of_range_value : Double
  nodata : Double
  mode : ViewshedMode
  cell_mode : CellMode
}

///|
/// Options with gdal_viewshed's defaults.
pub fn ViewshedOptions::new(
  observer_x : Double,
  observer_y : Double,
  observer_height~ : Double = 2.0,
  target_height~ : Double = 0.0,
  max_distance~ : Double = 0.0,
  min_distance~ : Double = 0.0,
  start_angle~ : Double = 0.0,
  end_angle~ : Double = 0.0,
  low_pitch~ : Double = -90.0,
  high_pitch~ : Double = 90.0,
  curvature_coeff? : Double,
  semi_major? : Double,
  visible_value~ : Double = 255.0,
  invisible_value~ : Double = 0.0,
  out_of_range_value~ : Double = 0.0,
  nodata~ : Double = -1.0,
  mode~ : ViewshedMode = Normal,
  cell_mode~ : CellMode = Edge,
) -> ViewshedOptions {
  {
    observer_x,
    observer_y,
    observer_height,
    target_height,
    max_distance,
    min_distance,
    start_angle,
    end_angle,
    low_pitch,
    high_pitch,
    curvature_coeff,
    semi_major,
    visible_value,
    invisible_value,
    out_of_range_value,
    nodata,
    mode,
    cell_mode,
  }
}

///|
/// The raster gdal_viewshed writes, row by row; `found_nodata` is GDAL's warning
/// that an input cell was nodata or NaN (such cells are used as heights).
pub struct ViewshedResult {
  values : FixedArray[Double]
  width : Int32
  height : Int32
  geotransform : FixedArray[Double]
  nodata : Double?
  found_nodata : Bool
}

///|
/// GDAL's default `-cc`, standard atmospheric refraction.
pub const DEFAULT_CURVATURE_COEFF : Double = 0.85714

///|
const WGS84_SEMI_MAJOR : Double = 6378137.0

///|
/// gdal_viewshed's output for a DEM (`values` row by row) with GDAL's
/// `geotransform`. None where GDAL fails, for NaN angles or pitches, past
/// `MAX_VIEWSHED_CELLS` or 2^30 cells off; `trig` gives the masks' tan and atan2.
pub fn viewshed(
  values : FixedArray[Double],
  width : Int32,
  height : Int32,
  geotransform : FixedArray[Double],
  nodata : Double?,
  options : ViewshedOptions,
  trig~ : @core.Trig = @core.Trig::moonbit(),
) -> ViewshedResult? {
  if width <= 0 ||
    height <= 0 ||
    width > MAX_VIEWSHED_CELLS / height ||
    values.length() != width * height ||
    geotransform.length() != 6 {
    return None
  }
  let o = options
  if !(o.max_distance >= 0.0 || o.max_distance.is_nan()) ||
    !(o.min_distance >= 0.0 || o.min_distance.is_nan()) ||
    o.start_angle.is_nan() ||
    o.end_angle.is_nan() ||
    o.low_pitch.is_nan() ||
    o.high_pitch.is_nan() {
    return None
  }
  let gt = FixedArray::from_iter(geotransform.iter())
  guard invert_geotransform(gt) is Some(inv) else { return None }
  let dfx = inv[0] + o.observer_x * inv[1] + o.observer_y * inv[2]
  let dfy = inv[3] + o.observer_x * inv[4] + o.observer_y * inv[5]
  if !(dfx >= -2147483648.0 && dfx <= 2147483647.0) ||
    !(dfy >= -2147483648.0 && dfy <= 2147483647.0) {
    return None
  }
  let nx = dfx.to_int()
  let ny = dfy.to_int()
  if nx.abs() > MAX_OBSERVER_PIXEL || ny.abs() > MAX_OBSERVER_PIXEL {
    return None
  }
  if o.start_angle < 0.0 ||
    o.start_angle >= 360.0 ||
    o.end_angle < 0.0 ||
    o.end_angle >= 360.0 ||
    o.high_pitch > 90.0 ||
    o.low_pitch < -90.0 ||
    o.high_pitch <= o.low_pitch {
    return None
  }
  let start_angle = normalize_angle(o.start_angle)
  let end_angle = normalize_angle(o.end_angle)
  guard calc_extents(
      trig, o, width, height, nx, ny, inv, start_angle, end_angle,
    )
    is Some(out) else {
    return None
  }
  let coeff = match o.curvature_coeff {
    Some(c) => c
    None =>
      match o.semi_major {
        Some(a) if (a - WGS84_SEMI_MAJOR).abs() > 0.05 * WGS84_SEMI_MAJOR => 1.0
        _ => DEFAULT_CURVATURE_COEFF
      }
  }
  let height_adj = match o.semi_major {
    Some(a) => coeff / (a * 2.0)
    None => 0.0
  }
  let xsize = out.x_stop - out.x_start
  let ysize = out.y_stop - out.y_start
  let (has_nodata, nodata_value) = match nodata {
    Some(v) => (true, v)
    None => (false, 0.0)
  }
  let min2 = o.min_distance * o.min_distance
  let max2 = o.max_distance * o.max_distance
  let ex : Executor = {
    trig,
    values,
    width,
    x_start: out.x_start,
    y_start: out.y_start,
    y_stop: out.y_stop,
    xsize,
    nx: nx - out.x_start,
    ny,
    gt,
    mode: o.mode,
    cell_mode: o.cell_mode,
    target_height: o.target_height,
    visible: o.visible_value,
    invisible: o.invisible_value,
    out_of_range: o.out_of_range_value,
    observer_height: o.observer_height,
    start_angle,
    end_angle,
    angle_masking: start_angle != end_angle,
    low_pitch_masking: o.low_pitch > -90.0,
    high_pitch_masking: o.high_pitch < 90.0,
    low_tan: if o.low_pitch != -90.0 {
      (trig.tan)(o.low_pitch * (2.0 * PI / 360.0))
    } else {
      @double.not_a_number
    },
    high_tan: if o.high_pitch != 90.0 {
      (trig.tan)(o.high_pitch * (2.0 * PI / 360.0))
    } else {
      @double.not_a_number
    },
    test_angle: FixedArray::make(5, 0.0),
    height_adj,
    min2,
    max2: if max2 == 0.0 {
      @double.max_value
    } else {
      max2
    },
    z_observer: 0.0,
    has_nodata,
    nodata: nodata_value,
    found_nodata: false,
    output: FixedArray::make(xsize * ysize, 0.0),
  }
  ex.run()
  let out_gt : FixedArray[Double] = [
    gt[0] + gt[1] * out.x_start.to_double() + gt[2] * out.y_start.to_double(),
    gt[1],
    gt[2],
    gt[3] + gt[4] * out.x_start.to_double() + gt[5] * out.y_start.to_double(),
    gt[4],
    gt[5],
  ]
  let out_nodata = if o.mode is Normal && o.nodata > 255.0 {
    0.0
  } else {
    o.nodata
  }
  Some({
    values: ex.output,
    width: xsize,
    height: ysize,
    geotransform: out_gt,
    nodata: if out_nodata >= 0.0 {
      Some(out_nodata)
    } else {
      None
    },
    found_nodata: ex.found_nodata,
  })
}

///|
/// `Viewshed::calcExtents`: the output window in input cells, None when empty
/// or when angles mask around an observer outside the raster.
fn calc_extents(
  trig : @core.Trig,
  o : ViewshedOptions,
  width : Int32,
  height : Int32,
  nx : Int32,
  ny : Int32,
  inv : FixedArray[Double],
  start_angle : Double,
  end_angle : Double,
) -> Window? {
  let win = { x_start: 0, x_stop: width, y_start: 0, y_stop: height, }
  let inside = nx >= 0 && nx < width && ny >= 0 && ny < height
  if !inside && start_angle != end_angle {
    return None
  }
  let eps = 1.0e-8
  let md = o.max_distance
  if md > 0.0 {
    let fx = nx.to_double()
    let fy = ny.to_double()
    let x_start = cint((fx - inv[1] * md + eps).floor())
    let x_stop = cint((fx + inv[1] * md - eps).ceil() + 1.0)
    let y_start = cint((fy - inv[5].abs() * md + eps).floor()) -
      (if inv[5] > 0.0 { 1 } else { 0 })
    let y_stop = cint(
      (fy + inv[5].abs() * md - eps).ceil() +
      (if inv[5] < 0.0 { 1.0 } else { 0.0 }),
    )
    if x_start >= win.x_stop ||
      x_stop < 0 ||
      y_start >= win.y_stop ||
      y_stop < 0 {
      return None
    }
    win.x_start = max_int(x_start, 0)
    win.x_stop = min_int(x_stop, win.x_stop)
    win.y_start = max_int(y_start, 0)
    win.y_stop = min_int(y_stop, win.y_stop)
  }
  if win.x_stop - win.x_start <= 0 || win.y_stop - win.y_start <= 0 {
    return None
  }
  shrink_window_for_angles(trig, win, nx, ny, start_angle, end_angle)
  if win.x_stop - win.x_start <= 0 || win.y_stop - win.y_start <= 0 {
    return None
  }
  Some(win)
}
