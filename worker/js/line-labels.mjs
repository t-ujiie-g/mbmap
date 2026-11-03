// Where labels go along lines, as MapLibre GL JS 6.16.0 finds them (symbol/clip_line.ts,
// get_anchors.ts, check_max_angle.ts and `anchorIsTooClose` of symbol_layout.ts), in its
// 8192-unit tile. Import-free so tests run it as is.

// MapLibre's tile extent (src/data/extent.ts), twice `@core.TILE_EXTENT`.
export const EXTENT = 8192;

const dist = (a, b) => Math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
const angleTo = (a, b) => Math.atan2(a.y - b.y, a.x - b.x);
const lerp = (a, b, t) => a + t * (b - a);
const round = (x, y) => ({ x: Math.round(x), y: Math.round(y) });

/** `lines` cut to the box (x1, y1)-(x2, y2), new end points rounded (MapLibre's `clipLine`). */
export function clipLine(lines, x1, y1, x2, y2) {
  const out = [];
  for (const line of lines) {
    let clipped;
    for (let i = 0; i < line.length - 1; i++) {
      let p0 = line[i];
      let p1 = line[i + 1];
      if (p0.x < x1 && p1.x < x1) continue;
      else if (p0.x < x1) p0 = round(x1, p0.y + (p1.y - p0.y) * ((x1 - p0.x) / (p1.x - p0.x)));
      else if (p1.x < x1) p1 = round(x1, p0.y + (p1.y - p0.y) * ((x1 - p0.x) / (p1.x - p0.x)));
      if (p0.y < y1 && p1.y < y1) continue;
      else if (p0.y < y1) p0 = round(p0.x + (p1.x - p0.x) * ((y1 - p0.y) / (p1.y - p0.y)), y1);
      else if (p1.y < y1) p1 = round(p0.x + (p1.x - p0.x) * ((y1 - p0.y) / (p1.y - p0.y)), y1);
      if (p0.x >= x2 && p1.x >= x2) continue;
      else if (p0.x >= x2) p0 = round(x2, p0.y + (p1.y - p0.y) * ((x2 - p0.x) / (p1.x - p0.x)));
      else if (p1.x >= x2) p1 = round(x2, p0.y + (p1.y - p0.y) * ((x2 - p0.x) / (p1.x - p0.x)));
      if (p0.y >= y2 && p1.y >= y2) continue;
      else if (p0.y >= y2) p0 = round(p0.x + (p1.x - p0.x) * ((y2 - p0.y) / (p1.y - p0.y)), y2);
      else if (p1.y >= y2) p1 = round(p0.x + (p1.x - p0.x) * ((y2 - p0.y) / (p1.y - p0.y)), y2);
      const last = clipped?.[clipped.length - 1];
      if (!clipped || p0.x !== last.x || p0.y !== last.y) {
        clipped = [p0];
        out.push(clipped);
      }
      clipped.push(p1);
    }
  }
  return out;
}

function lineLength(line) {
  let length = 0;
  for (let k = 0; k < line.length - 1; k++) length += dist(line[k], line[k + 1]);
  return length;
}

/** Whether the corners of `line` within `windowSize` of each other under a label at `anchor` turn by at most `maxAngle`. */
export function checkMaxAngle(line, anchor, labelLength, windowSize, maxAngle) {
  if (anchor.segment === undefined || labelLength === 0) return true;
  let p = anchor;
  let index = anchor.segment + 1;
  let anchorDistance = 0;
  while (anchorDistance > -labelLength / 2) {
    index--;
    if (index < 0) return false;
    anchorDistance -= dist(line[index], p);
    p = line[index];
  }
  anchorDistance += dist(line[index], line[index + 1]);
  index++;
  const corners = [];
  let angleSum = 0;
  while (anchorDistance < labelLength / 2) {
    const prev = line[index - 1];
    const current = line[index];
    const next = line[index + 1];
    if (!next) return false;
    let delta = angleTo(prev, current) - angleTo(current, next);
    delta = Math.abs(((delta + 3 * Math.PI) % (Math.PI * 2)) - Math.PI);
    corners.push({ distance: anchorDistance, delta });
    angleSum += delta;
    while (anchorDistance - corners[0].distance > windowSize) angleSum -= corners.shift().delta;
    if (angleSum > maxAngle) return false;
    index++;
    anchorDistance += dist(current, next);
  }
  return true;
}

function resample(line, offset, spacing, windowSize, maxAngle, labelLength, continued, atMiddle, extent, limit) {
  const half = labelLength / 2;
  const total = lineLength(line);
  let distance = 0;
  let marked = offset - spacing;
  let anchors = [];
  for (let i = 0; i < line.length - 1; i++) {
    const a = line[i];
    const b = line[i + 1];
    const segment = dist(a, b);
    const angle = angleTo(b, a);
    while (marked + spacing < distance + segment) {
      marked += spacing;
      const t = (marked - distance) / segment;
      const x = lerp(a.x, b.x, t);
      const y = lerp(a.y, b.y, t);
      if (x >= 0 && x < extent && y >= 0 && y < extent && marked - half >= 0 && marked + half <= total) {
        const anchor = { ...round(x, y), angle, segment: i };
        if (!windowSize || checkMaxAngle(line, anchor, labelLength, windowSize, maxAngle)) anchors.push(anchor);
        if (anchors.length >= limit) return anchors;
      }
    }
    distance += segment;
  }
  if (!atMiddle && !anchors.length && !continued) {
    anchors = resample(line, distance / 2, spacing, windowSize, maxAngle, labelLength, continued, true, extent, limit);
  }
  return anchors;
}

/**
 * Anchors every `spacing` along `line` (MapLibre's `getAnchors`), at most `limit`: `length` is the
 * label's in glyph units (24 a em), `boxScale` tile units per glyph unit, `maxAngle` in radians.
 */
export function getAnchors(line, spacing, maxAngle, length, boxScale, overscaling, extent = EXTENT, limit = Infinity, text = true) {
  if (!(spacing > 0) || limit <= 0) return [];
  const windowSize = text && length > 0 ? (3 / 5) * 24 * boxScale : 0;
  const labelLength = length * boxScale;
  const first = line[0];
  const continued = first.x === 0 || first.x === extent || first.y === 0 || first.y === extent;
  if (spacing - labelLength < spacing / 4) spacing = labelLength + spacing / 4;
  const offset = !continued ? ((length / 2 + 24 * 2) * boxScale * overscaling) % spacing : ((spacing / 2) * overscaling) % spacing;
  return resample(line, offset, spacing, windowSize, maxAngle, labelLength, continued, false, extent, limit);
}

/** The anchor at the middle of `line` if the label fits there (MapLibre's `getCenterAnchor`). */
export function getCenterAnchor(line, maxAngle, length, boxScale, text = true) {
  const windowSize = text && length > 0 ? (3 / 5) * 24 * boxScale : 0;
  const labelLength = length * boxScale;
  let prev = 0;
  const center = lineLength(line) / 2;
  for (let i = 0; i < line.length - 1; i++) {
    const a = line[i];
    const b = line[i + 1];
    const segment = dist(a, b);
    if (prev + segment > center) {
      const t = (center - prev) / segment;
      const anchor = { ...round(lerp(a.x, b.x, t), lerp(a.y, b.y, t)), angle: angleTo(b, a), segment: i };
      return !windowSize || checkMaxAngle(line, anchor, labelLength, windowSize, maxAngle) ? anchor : null;
    }
    prev += segment;
  }
  return null;
}

/**
 * MapLibre's `mergeLines`: the first lines of `features` (`{text, lines}`, in order) that meet end
 * to start with the same text joined into one, the feature merged into another dropped.
 */
export function mergeLines(features) {
  const left = new Map();
  const right = new Map();
  const merged = [];
  const key = (text, line, onRight) => {
    const points = onRight ? line.last.points : line.first.points;
    const p = onRight ? points[points.length - 1] : points[0];
    return `${text}:${p.x}:${p.y}`;
  };
  const fromRight = (leftKey, rightKey, line) => {
    const i = right.get(leftKey);
    right.delete(leftKey);
    right.set(rightKey, i);
    merged[i].last.next = line.first;
    merged[i].last = line.last;
    return i;
  };
  const fromLeft = (leftKey, rightKey, line) => {
    const i = left.get(rightKey);
    left.delete(rightKey);
    left.set(leftKey, i);
    line.last.next = merged[i].first;
    merged[i].first = line.first;
    return i;
  };
  for (const feature of features) {
    const chunk = { points: feature.lines[0], next: null };
    const line = { feature, first: chunk, last: chunk };
    if (!feature.text || !chunk.points?.length) {
      merged.push(line);
      continue;
    }
    const leftKey = key(feature.text, line);
    const rightKey = key(feature.text, line, true);
    if (right.has(leftKey) && left.has(rightKey) && right.get(leftKey) !== left.get(rightKey)) {
      const j = fromLeft(leftKey, rightKey, line);
      const i = fromRight(leftKey, rightKey, merged[j]);
      left.delete(leftKey);
      right.delete(rightKey);
      right.set(key(feature.text, merged[i], true), i);
      merged[j].feature.dropped = true;
    } else if (right.has(leftKey)) {
      fromRight(leftKey, rightKey, line);
    } else if (left.has(rightKey)) {
      fromLeft(leftKey, rightKey, line);
    } else {
      const i = merged.push(line) - 1;
      left.set(leftKey, i);
      right.set(rightKey, i);
    }
  }
  const out = [];
  for (const line of merged) {
    if (line.feature.dropped) continue;
    if (line.first.next) {
      const points = [...line.first.points];
      for (let c = line.first.next; c; c = c.next) points.push(...c.points.slice(1));
      line.feature.lines = [points, ...line.feature.lines.slice(1)];
    }
    out.push(line.feature);
  }
  return out;
}

/** Whether `anchor` lies within `distance` of an earlier anchor of the same text, remembering it if not. */
export function tooClose(seen, text, distance, anchor) {
  const others = seen.get(text);
  if (!others) {
    seen.set(text, [anchor]);
    return false;
  }
  for (let k = others.length - 1; k >= 0; k--) if (dist(anchor, others[k]) < distance) return true;
  others.push(anchor);
  return false;
}

/**
 * The label instances of one feature's `lines` at `overscaling` (MapLibre lays labels out again in
 * tiles deeper than the source's): `{anchor, line}` per anchor, `line` the clipped line it lies on.
 * `layout`: `{placement: "line" | "line-center", spacing (px), maxAngle (degrees), size (px)}`; at most `limit` of them.
 */
export function lineAnchors(lines, text, length, layout, overscaling, seen, limit = Infinity) {
  const tilePixelRatio = EXTENT / (512 * overscaling);
  const spacing = tilePixelRatio * layout.spacing;
  const boxScale = (tilePixelRatio * layout.size) / 24;
  const maxAngle = (layout.maxAngle / 180) * Math.PI;
  const out = [];
  if (!(limit > 0)) return out;
  const inside = (a) => a.x >= 0 && a.x < EXTENT && a.y >= 0 && a.y < EXTENT;
  if (layout.placement === "line") {
    for (const line of clipLine(lines, 0, 0, EXTENT, EXTENT)) {
      // Anchors are made only as far as the room left, so a long line cannot outrun the cap.
      for (const anchor of getAnchors(line, spacing, maxAngle, length, boxScale, overscaling, EXTENT, limit - out.length, !!text)) {
        // Only labels with text keep apart from their like (MapLibre's `anchorIsTooClose`).
        if ((!text || !tooClose(seen, text, spacing / 2, anchor)) && inside(anchor)) out.push({ anchor, line });
        if (out.length >= limit) return out;
      }
    }
  } else {
    for (const line of lines) {
      if (out.length >= limit) return out;
      if (line.length < 2) continue;
      const anchor = getCenterAnchor(line, maxAngle, length, boxScale, !!text);
      if (anchor && inside(anchor)) out.push({ anchor, line });
    }
  }
  return out;
}
