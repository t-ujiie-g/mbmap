// Follows proj4js 2.22.0's pseudocylindrical projections (lib/projections/
// sinu.js, eck6.js, moll.js, robin.js, eqearth.js), MIT License, Copyright (c) 2014, Mike Adair,
// Richard Greenwood, Didier Richard, Stephen Irons, Olivier Terral, Calvin
// Metcalf. See NOTICE.
// Equal Earth follows eqearth.js, Copyright 2018 Bernie Jenny, Monash
// University, Apache License 2.0. See NOTICE.

///|
/// Sinusoidal, and Eckert VI on a sphere (`m`, `n`, `c_x`, `c_y` of the
/// generalized form; Eckert VI is always spherical).
priv struct Sinu {
  p : Base
  sphere : Bool
  en : FixedArray[Double]
  m : Double
  n : Double
  c_x : Double
  c_y : Double
}

///|
fn Sinu::new(p : Base, eck6 : Bool) -> Sinu {
  let (m, n) = if eck6 {
    (1.0, 2.570796326794896619231321691)
  } else {
    (0.0, 1.0)
  }
  let sphere = eck6 || p.sphere
  let c_y = ((m + 1.0) / n).sqrt()
  {
    p: { ..p, es: if sphere { 0.0 } else { p.es }, },
    sphere,
    en: if sphere {
      []
    } else {
      pj_enfn(p.es)
    },
    m,
    n,
    c_x: c_y / (m + 1.0),
    c_y,
  }
}

///|
fn Sinu::forward(self : Sinu, lon : Double, lat : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let lon = adjust_lon(lon - p.long0)
  let (x, y) = if self.sphere {
    let mut lat = lat
    if self.m == 0.0 {
      if self.n != 1.0 {
        lat = m.asin(self.n * m.sin(lat))
      }
    } else {
      let k = self.n * m.sin(lat)
      for _ in 0..<20 {
        let v = (self.m * lat + m.sin(lat) - k) / (self.m + m.cos(lat))
        lat -= v
        if v.abs() < EPSLN {
          break
        }
      }
    }
    (p.a * self.c_x * lon * (self.m + m.cos(lat)), p.a * self.c_y * lat)
  } else {
    let s = m.sin(lat)
    let c = m.cos(lat)
    (
      p.a * lon * c / (1.0 - p.es * s * s).sqrt(),
      p.a * pj_mlfn(lat, s, c, self.en),
    )
  }
  // proj4js leaves out the false easting and northing here, which breaks
  // their round trip; PROJ adds them.
  (x + p.x0, y + p.y0)
}

///|
fn Sinu::inverse(self : Sinu, x : Double, y : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let x = x - p.x0
  let y = y - p.y0
  if self.sphere {
    let lat = y / p.a / self.c_y
    let lon = x / p.a / (self.c_x * (self.m + m.cos(lat)))
    let lat = if self.m != 0.0 {
      asinz(m, (self.m * lat + m.sin(lat)) / self.n)
    } else if self.n != 1.0 {
      asinz(m, m.sin(lat) / self.n)
    } else {
      lat
    }
    (adjust_lon(lon + p.long0), adjust_lat(lat))
  } else {
    let lat = pj_inv_mlfn(m, y / p.a, p.es, self.en)
    let s = lat.abs()
    if s < HALF_PI {
      let s = m.sin(lat)
      (
        adjust_lon(
          p.long0 + x * (1.0 - p.es * s * s).sqrt() / (p.a * m.cos(lat)),
        ),
        lat,
      )
    } else if s - EPSLN < HALF_PI {
      (p.long0, lat)
    } else {
      nan2
    }
  }
}

///|
/// Mollweide.
fn moll_forward(
  m : Trig,
  p : Base,
  lon : Double,
  lat : Double,
) -> (Double, Double) {
  let mut delta_lon = adjust_lon(lon - p.long0)
  let mut theta = lat
  let con = PI * m.sin(lat)
  // proj4js iterates without a bound; 50 steps reach EPSLN everywhere.
  for _ in 0..<50 {
    let delta_theta = -(theta + m.sin(theta) - con) / (1.0 + m.cos(theta))
    theta += delta_theta
    if delta_theta.abs() < EPSLN {
      break
    }
  }
  theta /= 2.0
  if PI / 2.0 - lat.abs() < EPSLN {
    delta_lon = 0.0
  }
  (
    0.900316316158 * p.a * delta_lon * m.cos(theta) + p.x0,
    1.4142135623731 * p.a * m.sin(theta) + p.y0,
  )
}

///|
fn moll_inverse(m : Trig, p : Base, x : Double, y : Double) -> (Double, Double) {
  let mut arg = (y - p.y0) / (1.4142135623731 * p.a)
  if arg.abs() > 0.999999999999 {
    arg = 0.999999999999
  }
  let theta = m.asin(arg)
  let lon = adjust_lon(
    p.long0 + (x - p.x0) / (0.900316316158 * p.a * m.cos(theta)),
  )
  let lon = @cmp.maximum(-PI, @cmp.minimum(PI, lon))
  let arg = (2.0 * theta + m.sin(2.0 * theta)) / PI
  (lon, m.asin(if arg.abs() > 1.0 { 1.0 } else { arg }))
}

///|
/// Robinson's table: x and y polynomials per 5° of latitude.
let robin_x : FixedArray[Double] = [
  1.0000, 2.2199e-17, -7.15515e-05, 3.1103e-06, 0.9986, -0.000482243, -2.4897e-05,
  -1.3309e-06, 0.9954, -0.00083103, -4.48605e-05, -9.86701e-07, 0.9900, -0.00135364,
  -5.9661e-05, 3.6777e-06, 0.9822, -0.00167442, -4.49547e-06, -5.72411e-06, 0.9730,
  -0.00214868, -9.03571e-05, 1.8736e-08, 0.9600, -0.00305085, -9.00761e-05, 1.64917e-06,
  0.9427, -0.00382792, -6.53386e-05, -2.6154e-06, 0.9216, -0.00467746, -0.00010457,
  4.81243e-06, 0.8962, -0.00536223, -3.23831e-05, -5.43432e-06, 0.8679, -0.00609363,
  -0.000113898, 3.32484e-06, 0.8350, -0.00698325, -6.40253e-05, 9.34959e-07, 0.7986,
  -0.00755338, -5.00009e-05, 9.35324e-07, 0.7597, -0.00798324, -3.5971e-05, -2.27626e-06,
  0.7186, -0.00851367, -7.01149e-05, -8.6303e-06, 0.6732, -0.00986209, -0.000199569,
  1.91974e-05, 0.6213, -0.010418, 8.83923e-05, 6.24051e-06, 0.5722, -0.00906601,
  0.000182, 6.24051e-06, 0.5322, -0.00677797, 0.000275608, 6.24051e-06,
]

///|
let robin_y : FixedArray[Double] = [
  -5.20417e-18, 0.0124, 1.21431e-18, -8.45284e-11, 0.0620, 0.0124, -1.26793e-09,
  4.22642e-10, 0.1240, 0.0124, 5.07171e-09, -1.60604e-09, 0.1860, 0.0123999, -1.90189e-08,
  6.00152e-09, 0.2480, 0.0124002, 7.10039e-08, -2.24e-08, 0.3100, 0.0123992, -2.64997e-07,
  8.35986e-08, 0.3720, 0.0124029, 9.88983e-07, -3.11994e-07, 0.4340, 0.0123893, -3.69093e-06,
  -4.35621e-07, 0.4958, 0.0123198, -1.02252e-05, -3.45523e-07, 0.5571, 0.0121916,
  -1.54081e-05, -5.82288e-07, 0.6176, 0.0119938, -2.41424e-05, -5.25327e-07, 0.6769,
  0.011713, -3.20223e-05, -5.16405e-07, 0.7346, 0.0113541, -3.97684e-05, -6.09052e-07,
  0.7903, 0.0109107, -4.89042e-05, -1.04739e-06, 0.8435, 0.0103431, -6.4615e-05,
  -1.40374e-09, 0.8936, 0.00969686, -6.4636e-05, -8.547e-06, 0.9394, 0.00840947,
  -0.000192841, -4.2106e-06, 0.9761, 0.00616527, -0.000256, -4.2106e-06, 1.0000,
  0.00328947, -0.000319159, -4.2106e-06,
]

///|
fn poly3(t : FixedArray[Double], i : Int32, x : Double) -> Double {
  t[i * 4] + x * (t[i * 4 + 1] + x * (t[i * 4 + 2] + x * t[i * 4 + 3]))
}

///|
fn robin_forward(p : Base, lon : Double, lat : Double) -> (Double, Double) {
  let lon = adjust_lon(lon - p.long0)
  let dphi = lat.abs()
  let i = @cmp.maximum(
    0,
    @cmp.minimum(17, @math.floor(dphi * R2D / 5.0).to_int()),
  )
  let dphi = R2D * (dphi - 5.0 / R2D * i.to_double())
  let y = poly3(robin_y, i, dphi)
  (
    poly3(robin_x, i, dphi) * lon * p.a * 0.8487 + p.x0,
    (if lat < 0.0 { -y } else { y }) * p.a * 1.3523 + p.y0,
  )
}

///|
fn robin_inverse(p : Base, x : Double, y : Double) -> (Double, Double) {
  let lx = (x - p.x0) / (p.a * 0.8487)
  let ly = (y - p.y0).abs() / (p.a * 1.3523)
  if ly >= 1.0 {
    return (
      adjust_lon(lx / robin_x[18 * 4] + p.long0),
      if y < 0.0 {
        -HALF_PI
      } else {
        HALF_PI
      },
    )
  }
  let mut i = @cmp.maximum(0, @cmp.minimum(17, @math.floor(ly * 18.0).to_int()))
  for _ in 0..<40 {
    if robin_y[i * 4] > ly {
      i -= 1
    } else if robin_y[(i + 1) * 4] <= ly {
      i += 1
    } else {
      break
    }
  }
  let y0 = robin_y[i * 4]
  let mut t = 5.0 * (ly - y0) / (robin_y[(i + 1) * 4] - y0)
  for _ in 0..<100 {
    let der = robin_y[i * 4 + 1] +
      t * (2.0 * robin_y[i * 4 + 2] + t * 3.0 * robin_y[i * 4 + 3])
    let upd = (poly3(robin_y, i, t) - ly) / der
    t -= upd
    if upd.abs() < EPSLN {
      break
    }
  }
  let lat = (5.0 * i.to_double() + t) * D2R
  (
    adjust_lon(lx / poly3(robin_x, i, t) + p.long0),
    if y < 0.0 {
      -lat
    } else {
      lat
    },
  )
}

///|
/// Equal Earth.
priv struct Eqearth {
  p : Base
  apa : FixedArray[Double]
  qp : Double
  rqda : Double
}

///|
const EQEARTH_M : Double = 0.8660254037844386

///|
fn Eqearth::new(p : Base) -> Eqearth {
  let m = p.m
  if p.es != 0.0 {
    let qp = qsfnz(m, p.e, 1.0)
    { p, apa: authset(p.es), qp, rqda: (0.5 * qp).sqrt(), }
  } else {
    { p, apa: [], qp: 0.0, rqda: 1.0, }
  }
}

///|
fn eqearth_y(t : Double) -> Double {
  let t2 = t * t
  let t6 = t2 * t2 * t2
  t * (1.340264 + -0.081106 * t2 + t6 * (0.000893 + 0.003796 * t2))
}

///|
fn eqearth_dy(t : Double) -> Double {
  let t2 = t * t
  let t6 = t2 * t2 * t2
  1.340264 + 3.0 * -0.081106 * t2 + t6 * (7.0 * 0.000893 + 9.0 * 0.003796 * t2)
}

///|
fn Eqearth::forward(
  self : Eqearth,
  lon : Double,
  lat : Double,
) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let lam = adjust_lon(lon - p.long0)
  let sinphi = if p.es != 0.0 {
    qsfnz(m, p.e, m.sin(lat)) / self.qp
  } else {
    m.sin(lat)
  }
  let t = m.asin(EQEARTH_M * sinphi)
  let x = lam * m.cos(t) / (EQEARTH_M * eqearth_dy(t)) * self.rqda
  let y = eqearth_y(t) * self.rqda
  (p.a * x + p.x0, p.a * y + p.y0)
}

///|
fn Eqearth::inverse(self : Eqearth, x : Double, y : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let x = (x - p.x0) / p.a / self.rqda
  let y = (y - p.y0) / p.a / self.rqda
  let mut t = y
  for _ in 0..<12 {
    let dlat = (eqearth_y(t) - y) / eqearth_dy(t)
    t -= dlat
    if dlat.abs() < 1.0e-9 {
      break
    }
  }
  let lon = EQEARTH_M * x * eqearth_dy(t) / m.cos(t)
  let lat = m.asin(m.sin(t) / EQEARTH_M)
  (
    adjust_lon(lon + p.long0),
    if p.es != 0.0 {
      authlat(m, lat, self.apa)
    } else {
      lat
    },
  )
}
