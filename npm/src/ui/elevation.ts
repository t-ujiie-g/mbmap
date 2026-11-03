// The numbers of an elevation profile: its range, total ascent and descent,
// and the sample nearest a distance. Import-free, so that `npm test` can load it.

/** `min` and `max` elevation, `gain` (total ascent) and `loss` (total descent) in meters, samples without data skipped. */
export function profileStats(elevations: ArrayLike<number>): { min: number; max: number; gain: number; loss: number } {
  let min = Infinity;
  let max = -Infinity;
  let gain = 0;
  let loss = 0;
  let last = NaN;
  for (let i = 0; i < elevations.length; i++) {
    const e = elevations[i];
    if (Number.isNaN(e)) continue;
    min = Math.min(min, e);
    max = Math.max(max, e);
    if (!Number.isNaN(last)) {
      if (e > last) gain += e - last;
      else loss += last - e;
    }
    last = e;
  }
  return min <= max ? { min, max, gain, loss } : { min: NaN, max: NaN, gain: 0, loss: 0 };
}

/** The index of the distance in `distances` (ascending) nearest `d`, or -1 when there is none. */
export function nearestIndex(distances: ArrayLike<number>, d: number): number {
  const n = distances.length;
  if (n === 0 || Number.isNaN(d)) return -1;
  let lo = 0;
  let hi = n - 1;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (distances[mid] < d) lo = mid + 1;
    else hi = mid;
  }
  return lo > 0 && d - distances[lo - 1] <= distances[lo] - d ? lo - 1 : lo;
}
