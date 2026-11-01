// Follows proj4js 2.22.0's lib/common/vincenty.js, MIT License, Copyright (c) 2014, Mike Adair,
// Richard Greenwood, Didier Richard, Stephen Irons, Olivier Terral, Calvin
// Metcalf. See NOTICE.

///|
/// The initial azimuth and distance from (`lat1`, `lon1`) to (`lat2`,
/// `lon2`) on the ellipsoid of semi-major axis `a` and flattening `f`.
fn vincenty_inverse(
  m : Trig,
  lat1 : Double,
  lon1 : Double,
  lat2 : Double,
  lon2 : Double,
  a : Double,
  f : Double,
) -> (Double, Double) {
  let l = lon2 - lon1
  let u1 = m.atan((1.0 - f) * m.tan(lat1))
  let u2 = m.atan((1.0 - f) * m.tan(lat2))
  let sin_u1 = m.sin(u1)
  let cos_u1 = m.cos(u1)
  let sin_u2 = m.sin(u2)
  let cos_u2 = m.cos(u2)
  let mut lambda = l
  let mut sin_lambda = 0.0
  let mut cos_lambda = 0.0
  let mut sin_sigma = 0.0
  let mut cos_sigma = 0.0
  let mut sigma = 0.0
  let mut cos2_alpha = 0.0
  let mut cos2_sigma_m = 0.0
  let mut converged = false
  for _ in 0..<100 {
    sin_lambda = m.sin(lambda)
    cos_lambda = m.cos(lambda)
    let t = cos_u1 * sin_u2 - sin_u1 * cos_u2 * cos_lambda
    sin_sigma = (cos_u2 * sin_lambda * (cos_u2 * sin_lambda) + t * t).sqrt()
    if sin_sigma == 0.0 {
      return (0.0, 0.0)
    }
    cos_sigma = sin_u1 * sin_u2 + cos_u1 * cos_u2 * cos_lambda
    sigma = m.atan2(sin_sigma, cos_sigma)
    let sin_alpha = cos_u1 * cos_u2 * sin_lambda / sin_sigma
    cos2_alpha = 1.0 - sin_alpha * sin_alpha
    cos2_sigma_m = if cos2_alpha != 0.0 {
      cos_sigma - 2.0 * sin_u1 * sin_u2 / cos2_alpha
    } else {
      0.0
    }
    let c = f / 16.0 * cos2_alpha * (4.0 + f * (4.0 - 3.0 * cos2_alpha))
    let previous = lambda
    lambda = l +
      (1.0 - c) *
      f *
      sin_alpha *
      (
        sigma +
        c *
        sin_sigma *
        (
          cos2_sigma_m +
          c * cos_sigma * (-1.0 + 2.0 * cos2_sigma_m * cos2_sigma_m)
        )
      )
    if (lambda - previous).abs() <= 1.0e-12 {
      converged = true
      break
    }
  }
  if !converged {
    return nan2
  }
  let b = a * (1.0 - f)
  let u_sq = cos2_alpha * (a * a - b * b) / (b * b)
  let big_a = 1.0 +
    u_sq / 16384.0 * (4096.0 + u_sq * (-768.0 + u_sq * (320.0 - 175.0 * u_sq)))
  let big_b = u_sq /
    1024.0 *
    (256.0 + u_sq * (-128.0 + u_sq * (74.0 - 47.0 * u_sq)))
  let delta_sigma = big_b *
    sin_sigma *
    (
      cos2_sigma_m +
      big_b /
      4.0 *
      (
        cos_sigma * (-1.0 + 2.0 * cos2_sigma_m * cos2_sigma_m) -
        big_b /
        6.0 *
        cos2_sigma_m *
        (-3.0 + 4.0 * sin_sigma * sin_sigma) *
        (-3.0 + 4.0 * cos2_sigma_m * cos2_sigma_m)
      )
    )
  (
    m.atan2(cos_u2 * sin_lambda, cos_u1 * sin_u2 - sin_u1 * cos_u2 * cos_lambda),
    b * big_a * (sigma - delta_sigma),
  )
}

///|
/// The point (latitude, longitude) at distance `s12` and azimuth `azi1` from
/// (`lat1`, `lon1`).
fn vincenty_direct(
  m : Trig,
  lat1 : Double,
  lon1 : Double,
  azi1 : Double,
  s12 : Double,
  a : Double,
  f : Double,
) -> (Double, Double) {
  let u1 = m.atan((1.0 - f) * m.tan(lat1))
  let sin_u1 = m.sin(u1)
  let cos_u1 = m.cos(u1)
  let sin_alpha1 = m.sin(azi1)
  let cos_alpha1 = m.cos(azi1)
  let sigma1 = m.atan2(sin_u1, cos_u1 * cos_alpha1)
  let sin_alpha = cos_u1 * sin_alpha1
  let cos2_alpha = 1.0 - sin_alpha * sin_alpha
  let b = a * (1.0 - f)
  let u_sq = cos2_alpha * (a * a - b * b) / (b * b)
  let big_a = 1.0 +
    u_sq / 16384.0 * (4096.0 + u_sq * (-768.0 + u_sq * (320.0 - 175.0 * u_sq)))
  let big_b = u_sq /
    1024.0 *
    (256.0 + u_sq * (-128.0 + u_sq * (74.0 - 47.0 * u_sq)))
  let mut sigma = s12 / (b * big_a)
  let mut sin_sigma = 0.0
  let mut cos_sigma = 0.0
  let mut cos2_sigma_m = 0.0
  let mut converged = false
  for _ in 0..<100 {
    cos2_sigma_m = m.cos(2.0 * sigma1 + sigma)
    sin_sigma = m.sin(sigma)
    cos_sigma = m.cos(sigma)
    let delta_sigma = big_b *
      sin_sigma *
      (
        cos2_sigma_m +
        big_b /
        4.0 *
        (
          cos_sigma * (-1.0 + 2.0 * cos2_sigma_m * cos2_sigma_m) -
          big_b /
          6.0 *
          cos2_sigma_m *
          (-3.0 + 4.0 * sin_sigma * sin_sigma) *
          (-3.0 + 4.0 * cos2_sigma_m * cos2_sigma_m)
        )
      )
    let previous = sigma
    sigma = s12 / (b * big_a) + delta_sigma
    if (sigma - previous).abs() <= 1.0e-12 {
      converged = true
      break
    }
  }
  if !converged {
    return nan2
  }
  let tmp = sin_u1 * sin_sigma - cos_u1 * cos_sigma * cos_alpha1
  let lat2 = m.atan2(
    sin_u1 * cos_sigma + cos_u1 * sin_sigma * cos_alpha1,
    (1.0 - f) * (sin_alpha * sin_alpha + tmp * tmp).sqrt(),
  )
  let lambda = m.atan2(
    sin_sigma * sin_alpha1,
    cos_u1 * cos_sigma - sin_u1 * sin_sigma * cos_alpha1,
  )
  let c = f / 16.0 * cos2_alpha * (4.0 + f * (4.0 - 3.0 * cos2_alpha))
  let l = lambda -
    (1.0 - c) *
    f *
    sin_alpha *
    (
      sigma +
      c *
      sin_sigma *
      (
        cos2_sigma_m +
        c * cos_sigma * (-1.0 + 2.0 * cos2_sigma_m * cos2_sigma_m)
      )
    )
  (lat2, lon1 + l)
}
