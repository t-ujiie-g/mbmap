// Classification and statistics of numbers for legends and choropleths: ports of simple-statistics
// 8.0.0 (jenks, ckmeans, quantile, equal intervals, sum, variance) and geostats 2.1.0's standard
// deviation classes. Import-free, for `npm test`.

/** How `classBreaks` divides values: simple-statistics' `jenks`, `ckmeansBreaks`, `quantile`, `equalIntervalBreaks`, or geostats' standard deviations. */
export type ClassMethod = "jenks" | "ckmeans" | "quantile" | "equalInterval" | "standardDeviation";

/** The most values `classBreaks` and `statistics` take. */
export const MAX_CLASS_VALUES = 1_000_000;

/** The most classes `classBreaks` makes. */
export const MAX_CLASSES = 256;

/** The most values² × classes `jenks` takes, which bounds its time on the main thread. */
export const MAX_JENKS_WORK = 1e9;

/** The most values × classes `ckmeans` takes: the cells of its two matrices. */
export const MAX_CKMEANS_CELLS = 1e7;

/** Summary of finite values: count, min, max, sum (compensated, as simple-statistics' `sum`), mean, median, population variance and standard deviation. */
export interface Statistics {
  count: number;
  min: number;
  max: number;
  sum: number;
  mean: number;
  median: number;
  variance: number;
  standardDeviation: number;
}

// The finite numbers of `values`, refused past MAX_CLASS_VALUES.
function finite(values: ArrayLike<unknown>): Float64Array {
  if (values.length > MAX_CLASS_VALUES) throw new Error(`mbmap: classify: more than ${MAX_CLASS_VALUES} values`);
  const out = new Float64Array(values.length);
  let n = 0;
  for (let i = 0; i < values.length; i++) {
    const v = values[i];
    if (typeof v === "number" && Number.isFinite(v)) out[n++] = v;
  }
  return out.subarray(0, n);
}

// `x` sorted as by `(a, b) => a - b`: a typed-array sort, which puts -0 before 0, its zeros put back in their order in `x`.
function sorted(x: Float64Array): Float64Array {
  const s = x.slice().sort();
  let lo = 0;
  while (lo < s.length && s[lo] < 0) lo++;
  let hi = lo;
  while (hi < s.length && s[hi] === 0) hi++;
  if (Object.is(s[lo], -0) && !Object.is(s[hi - 1], -0)) {
    for (let i = 0, k = lo; k < hi; i++) if (x[i] === 0) s[k++] = x[i];
  }
  return s;
}

// simple-statistics' `min` and `max`: the first of equal values, so -0 and 0 keep their order.
function minMax(x: Float64Array): [number, number] {
  let min = x[0];
  let max = x[0];
  for (let i = 1; i < x.length; i++) {
    if (x[i] < min) min = x[i];
    if (x[i] > max) max = x[i];
  }
  return [min, max];
}

// simple-statistics' `quickselect` (Floyd-Rivest), whose order of equal zeros its median and quantiles keep.
function quickselect(arr: Float64Array, k: number, left: number, right: number) {
  const swap = (i: number, j: number) => {
    const t = arr[i];
    arr[i] = arr[j];
    arr[j] = t;
  };
  while (right > left) {
    if (right - left > 600) {
      const n = right - left + 1;
      const m = k - left + 1;
      const z = Math.log(n);
      const s = 0.5 * Math.exp((2 * z) / 3);
      let sd = 0.5 * Math.sqrt((z * s * (n - s)) / n);
      if (m - n / 2 < 0) sd *= -1;
      quickselect(arr, k, Math.max(left, Math.floor(k - (m * s) / n + sd)), Math.min(right, Math.floor(k + ((n - m) * s) / n + sd)));
    }
    const t = arr[k];
    let i = left;
    let j = right;
    swap(left, k);
    if (arr[right] > t) swap(left, right);
    while (i < j) {
      swap(i, j);
      i++;
      j--;
      while (arr[i] < t) i++;
      while (arr[j] > t) j--;
    }
    if (arr[left] === t) swap(left, j);
    else swap(++j, right);
    if (j <= k) left = j + 1;
    if (k <= j) right = j - 1;
  }
}

// simple-statistics' `quantile` over a copy of `x` (`multiQuantileSelect`, which makes the same
// `quickselect` calls as its `quantileSelect` for one quantile).
function quantiles(x: Float64Array, ps: number[]): number[] {
  const copy = x.slice();
  const last = copy.length - 1;
  const index = (p: number) => (p === 1 ? last : p === 0 ? 0 : last * p);
  const at = [...new Set(ps.flatMap((p) => [Math.floor(index(p)), Math.ceil(index(p))]))].sort((a, b) => a - b);
  const select = (lo: number, hi: number, left: number, right: number) => {
    if (lo > hi) return;
    const mid = (lo + hi) >> 1;
    quickselect(copy, at[mid], left, right);
    select(lo, mid - 1, left, at[mid] - 1);
    select(mid + 1, hi, at[mid] + 1, right);
  };
  select(0, at.length - 1, 0, last);
  return ps.map((p) => quantileSorted(copy, p));
}

// simple-statistics' `sum`: Neumaier's compensated sum.
function sum(x: Float64Array): number {
  if (x.length === 0) return 0;
  let s = x[0];
  let correction = 0;
  for (let i = 1; i < x.length; i++) {
    const t = s + x[i];
    correction += Math.abs(s) >= Math.abs(x[i]) ? s - t + x[i] : x[i] - t + s;
    s = t;
  }
  return s + correction;
}

// simple-statistics' `quantileSorted`.
function quantileSorted(x: Float64Array, p: number): number {
  const idx = (x.length - 1) * p;
  if (p === 1) return x[x.length - 1];
  if (p === 0) return x[0];
  if (idx % 1 !== 0) {
    const lower = Math.floor(idx);
    return x[lower] + (idx - lower) * (x[Math.ceil(idx)] - x[lower]);
  }
  return x[idx];
}

function variance(x: Float64Array, mean: number): number {
  let s = 0;
  for (let i = 0; i < x.length; i++) s += (x[i] - mean) * (x[i] - mean);
  return s / x.length;
}

// The statistics of `x` (not empty) but its median.
function moments(x: Float64Array): Statistics {
  const [min, max] = minMax(x);
  const total = sum(x);
  const mean = total / x.length;
  const v = variance(x, mean);
  return { count: x.length, min, max, sum: total, mean, median: Number.NaN, variance: v, standardDeviation: x.length === 1 ? 0 : Math.sqrt(v) };
}

/** Statistics of the finite numbers in `values`; null when there are none. */
export function statistics(values: ArrayLike<unknown>): Statistics | null {
  const x = finite(values);
  return x.length === 0 ? null : { ...moments(x), median: quantiles(x, [0.5])[0] };
}

// simple-statistics' `jenks` (Fisher-Jenks by its two tables) over sorted values; null for more classes than values.
function jenks(data: Float64Array, n: number): number[] | null {
  if (n > data.length) return null;
  const rows = data.length + 1;
  const lower = Array.from({ length: rows }, () => new Array<number>(n + 1).fill(0));
  const combos = Array.from({ length: rows }, () => new Array<number>(n + 1).fill(0));
  for (let i = 1; i < n + 1; i++) {
    lower[1][i] = 1;
    combos[1][i] = 0;
    for (let j = 2; j < rows; j++) combos[j][i] = Number.POSITIVE_INFINITY;
  }
  const shift = data[Math.floor(data.length / 2)];
  let v = 0;
  for (let l = 2; l < rows; l++) {
    let s = 0;
    let squares = 0;
    let w = 0;
    for (let m = 1; m < l + 1; m++) {
      const lowerLimit = l - m + 1;
      const val = data[lowerLimit - 1] - shift;
      w++;
      s += val;
      squares += val * val;
      v = squares - (s * s) / w;
      const i4 = lowerLimit - 1;
      if (i4 !== 0) {
        for (let j = 2; j < n + 1; j++) {
          if (combos[l][j] >= v + combos[i4][j - 1]) {
            lower[l][j] = lowerLimit;
            combos[l][j] = v + combos[i4][j - 1];
          }
        }
      }
    }
    lower[l][1] = 1;
    combos[l][1] = v;
  }
  const breaks: number[] = [];
  let k = data.length;
  breaks[n] = data[data.length - 1];
  for (let c = n; c > 0; c--) {
    // simple-statistics throws where its table leads before the first row (many equal values).
    if (k < 0) return null;
    breaks[c - 1] = data[lower[k][c] - 1];
    k = lower[k][c] - 1;
  }
  return breaks;
}

// simple-statistics' `ckmeans` `ssq`.
function ssq(j: number, i: number, sums: number[], squares: number[]): number {
  let sji: number;
  if (j > 0) {
    const mu = (sums[i] - sums[j - 1]) / (i - j + 1);
    sji = squares[i] - squares[j - 1] - (i - j + 1) * mu * mu;
  } else {
    sji = squares[i] - (sums[i] * sums[i]) / (i + 1);
  }
  return sji < 0 ? 0 : sji;
}

// simple-statistics' `fillMatrixColumn`, its recursion kept on an explicit stack in the same order.
function fillColumn(iMin0: number, iMax0: number, cluster: number, matrix: number[][], back: number[][], sums: number[], squares: number[]) {
  const stack: [number, number][] = [[iMin0, iMax0]];
  while (stack.length) {
    const [iMin, iMax] = stack.pop()!;
    if (iMin > iMax) continue;
    const i = Math.floor((iMin + iMax) / 2);
    matrix[cluster][i] = matrix[cluster - 1][i - 1];
    back[cluster][i] = i;
    let jlow = cluster;
    if (iMin > cluster) jlow = Math.max(jlow, back[cluster][iMin - 1] || 0);
    jlow = Math.max(jlow, back[cluster - 1][i] || 0);
    let jhigh = i - 1;
    if (iMax < matrix[0].length - 1) jhigh = Math.min(jhigh, back[cluster][iMax + 1] || 0);
    for (let j = jhigh; j >= jlow; --j) {
      const sji = ssq(j, i, sums, squares);
      if (sji + matrix[cluster - 1][jlow - 1] >= matrix[cluster][i]) break;
      const low = ssq(jlow, i, sums, squares) + matrix[cluster - 1][jlow - 1];
      if (low < matrix[cluster][i]) {
        matrix[cluster][i] = low;
        back[cluster][i] = jlow;
      }
      jlow++;
      const sj = sji + matrix[cluster - 1][j - 1];
      if (sj < matrix[cluster][i]) {
        matrix[cluster][i] = sj;
        back[cluster][i] = j;
      }
    }
    // The left half first, as the recursion does.
    stack.push([i + 1, iMax], [iMin, i - 1]);
  }
}

// simple-statistics' `ckmeansBreaks` over sorted values (Wang and Song's optimal 1-D k-means).
function ckmeans(data: Float64Array, n: number): number[] {
  let unique = 0;
  for (let i = 0; i < data.length; i++) if (i === 0 || data[i] !== data[i - 1]) unique++;
  if (unique === 1) return [data[0], data[data.length - 1]];
  const rows = data.length;
  const matrix = Array.from({ length: n }, () => new Array<number>(rows).fill(0));
  const back = Array.from({ length: n }, () => new Array<number>(rows).fill(0));
  const shift = data[Math.floor(rows / 2)];
  const sums: number[] = [];
  const squares: number[] = [];
  for (let i = 0; i < rows; i++) {
    const v = data[i] - shift;
    sums.push(i === 0 ? v : sums[i - 1] + v);
    squares.push(i === 0 ? v * v : squares[i - 1] + v * v);
    matrix[0][i] = ssq(0, i, sums, squares);
    back[0][i] = 0;
  }
  for (let cluster = 1; cluster < n; ++cluster) {
    fillColumn(cluster < n - 1 ? cluster : rows - 1, rows - 1, cluster, matrix, back, sums, squares);
  }
  const starts: number[] = [];
  let right = rows - 1;
  for (let cluster = n - 1; cluster >= 0; cluster--) {
    const left = back[cluster][right];
    starts[cluster] = data[left];
    if (cluster > 0) right = left - 1;
  }
  return [...starts, data[rows - 1]];
}

/**
 * The bounds of `classes` classes of the finite numbers in `values` (`classes + 1` numbers, lowest
 * first), as simple-statistics divides them (`jenks`, `ckmeans`, `quantile`, `equalInterval`) or
 * geostats lays out standard deviations around the mean (`matchBounds`: the outer bounds at the
 * minimum and maximum), with the exact mean and deviation. Null where simple-statistics gives none
 * or throws (no values, more classes than values; for jenks also fewer distinct values than classes).
 */
export function classBreaks(
  values: ArrayLike<unknown>,
  classes: number,
  method: ClassMethod = "jenks",
  { matchBounds = false }: { matchBounds?: boolean } = {},
): number[] | null {
  if (!Number.isInteger(classes) || classes < 1 || classes > MAX_CLASSES) throw new Error(`mbmap: classify: classes must be an integer from 1 to ${MAX_CLASSES}`);
  const x = finite(values);
  if (x.length === 0) return null;
  const tooMany = (work: number, cap: number) => {
    if (work > cap) throw new Error(`mbmap: classify: ${x.length} values in ${classes} classes are too many for ${method}`);
  };
  switch (method) {
    case "jenks": {
      tooMany(x.length * x.length * classes, MAX_JENKS_WORK);
      // simple-statistics leaves bounds undefined when there are fewer distinct values than classes.
      const b = jenks(sorted(x), classes);
      return b && b.every((v) => v !== undefined) ? b : null;
    }
    case "ckmeans":
      if (classes > x.length) return null;
      tooMany(x.length * classes, MAX_CKMEANS_CELLS);
      return ckmeans(sorted(x), classes);
    case "quantile":
      return quantiles(x, Array.from({ length: classes + 1 }, (_, i) => i / classes));
    case "equalInterval": {
      if (x.length < 2) return Array.from(x);
      const [min, max] = minMax(x);
      const size = (max - min) / classes;
      return [min, ...Array.from({ length: classes - 1 }, (_, i) => min + size * (i + 1)), max];
    }
    case "standardDeviation": {
      const st = moments(x);
      const [mean, sd] = [st.mean, st.standardDeviation];
      const a: number[] = [];
      if (classes % 2 === 1) {
        const inf = Math.floor(classes / 2);
        a[inf] = mean - sd / 2;
        a[inf + 1] = mean + sd / 2;
        for (let i = inf - 1; i > 0; i--) a[i] = a[i + 1] - sd;
        for (let i = inf + 2; i < classes; i++) a[i] = a[i - 1] + sd;
      } else {
        const mid = classes / 2;
        a[mid] = mean;
        for (let i = mid - 1; i > 0; i--) a[i] = a[i + 1] - sd;
        for (let i = mid + 1; i < classes; i++) a[i] = a[i - 1] + sd;
      }
      a[0] = matchBounds ? st.min : a[1] - sd;
      a[classes] = matchBounds ? st.max : a[classes - 1] + sd;
      return a;
    }
    default:
      throw new Error(`mbmap: classify: unknown method ${String(method)}`);
  }
}

/**
 * A style `step` expression giving `outputs[i]` (colors, widths, …) to values of class `i`:
 * `["step", input, outputs[0], breaks[1], outputs[1], …]`, which `mbmap/ui`'s legend lists as entries. Breaks
 * must ascend; of two equal ones (an empty class, which jenks and quantile may give) the later output stands.
 */
export function classStep(input: unknown, breaks: number[], outputs: unknown[]): unknown[] {
  if (breaks.length < 2 || outputs.length !== breaks.length - 1) throw new Error("mbmap: classify: give one output per class");
  const expr: unknown[] = ["step", input, outputs[0]];
  for (let i = 1; i < outputs.length; i++) {
    if (!(breaks[i] >= breaks[i - 1])) throw new Error("mbmap: classify: breaks must ascend");
    if (i > 1 && breaks[i] === breaks[i - 1]) expr[expr.length - 1] = outputs[i];
    else expr.push(breaks[i], outputs[i]);
  }
  return expr;
}
