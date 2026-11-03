// Coordinates written as text: decimal degrees in either order, degrees with
// minutes and seconds (° ′ ″, ' ", or 度 分 秒), Japan's plane rectangular
// systems ("第IX系 X … Y …") and UTM ("54N 388708 3949480"). Import-free.

export interface LngLatLike {
  lng: number;
  lat: number;
}

/** A position in a projected CRS: `x` easting and `y` northing in meters. */
export interface Projected {
  epsg: number;
  x: number;
  y: number;
  title: string;
}

const ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX"];

const NUMBER = String.raw`[+-]?\d+(?:\.\d+)?`;

/** One angle: decimal degrees, or degrees, minutes and seconds with an optional hemisphere letter or sign. */
function angle(text: string): { value: number; hemisphere: string | null } | null {
  const t = text.trim().replace(/[度]/g, "°").replace(/[分′’']/g, "′").replace(/[秒″”"]/g, "″");
  const m = new RegExp(String.raw`^([NSEW])?\s*([+-])?(\d+(?:\.\d+)?)(?:°\s*(?:(\d+(?:\.\d+)?)′\s*)?(?:(\d+(?:\.\d+)?)″)?)?\s*([NSEW])?$`, "i").exec(t);
  if (!m) return null;
  const [, pre, sign, d, min, sec, post] = m;
  if (pre && post) return null;
  if ((min && Number(min) >= 60) || (sec && Number(sec) >= 60)) return null;
  const value = Number(d) + Number(min ?? 0) / 60 + Number(sec ?? 0) / 3600;
  const hemisphere = (pre ?? post)?.toUpperCase() ?? null;
  const negative = sign === "-" || hemisphere === "S" || hemisphere === "W";
  return { value: negative ? -value : value, hemisphere };
}

/** The ways two angles can be a place: latitude first unless letters or ranges say otherwise. */
export function parseLngLat(text: string): LngLatLike[] {
  // NFKC writes ″ as two primes.
  const t = text.normalize("NFKC").replace(/′′/g, "″").trim();
  // Split on a comma, or on the space after a hemisphere letter or a seconds mark, or on a plain space.
  const parts =
    t.split(/\s*[,、]\s*/).length === 2
      ? t.split(/\s*[,、]\s*/)
      : (/^(.*?[NSEW″])\s+(.+)$/i.exec(t)?.slice(1) ?? t.split(/\s+/));
  if (parts.length !== 2) return [];
  const [a, b] = parts.map(angle);
  if (!a || !b) return [];
  const valid = (p: LngLatLike) => Math.abs(p.lat) <= 90 && Math.abs(p.lng) <= 180;
  if (a.hemisphere || b.hemisphere) {
    const latFirst = a.hemisphere === "N" || a.hemisphere === "S" || b.hemisphere === "E" || b.hemisphere === "W";
    const p = latFirst ? { lat: a.value, lng: b.value } : { lat: b.value, lng: a.value };
    return valid(p) ? [p] : [];
  }
  const out: LngLatLike[] = [];
  for (const p of [{ lat: a.value, lng: b.value }, { lat: b.value, lng: a.value }]) {
    if (valid(p) && !out.some((q) => q.lat === p.lat && q.lng === p.lng)) out.push(p);
  }
  return out;
}

/** "第IX系 X -35367.2 Y -5995.2" (or "9系", X before or after Y) on JGD2011, EPSG 6669-6687. */
export function parsePlaneRectangular(text: string): Projected | null {
  const t = text.normalize("NFKC").trim();
  const m = new RegExp(String.raw`^(?:第\s*)?([IVX]+|\d{1,2})\s*系\s*[,、]?\s*(.+)$`, "i").exec(t);
  if (!m) return null;
  const zone = /^\d+$/.test(m[1]) ? Number(m[1]) : ROMAN.indexOf(m[1].toUpperCase()) + 1;
  if (zone < 1 || zone > 19) return null;
  const x = new RegExp(String.raw`X\s*[=:]?\s*(${NUMBER})`, "i").exec(m[2]);
  const y = new RegExp(String.raw`Y\s*[=:]?\s*(${NUMBER})`, "i").exec(m[2]);
  const plain = new RegExp(String.raw`^(${NUMBER})\s*[, ]\s*(${NUMBER})$`).exec(m[2].trim());
  const [north, east] = x && y ? [x[1], y[1]] : plain ? [plain[1], plain[2]] : [null, null];
  if (north === null || east === null) return null;
  // The systems call northing X and easting Y.
  return { epsg: 6668 + zone, x: Number(east), y: Number(north), title: `第${ROMAN[zone - 1]}系` };
}

/** "54N 388708 3949480" (zone, hemisphere, easting, northing) on WGS 84, EPSG 326zz / 327zz. */
export function parseUtm(text: string): Projected | null {
  const m = new RegExp(String.raw`^(\d{1,2})\s*([NS])\s+(${NUMBER})\s*[, ]\s*(${NUMBER})$`, "i").exec(text.normalize("NFKC").trim());
  if (!m) return null;
  const zone = Number(m[1]);
  if (zone < 1 || zone > 60) return null;
  const north = m[2].toUpperCase() === "N";
  return { epsg: (north ? 32600 : 32700) + zone, x: Number(m[3]), y: Number(m[4]), title: `UTM ${zone}${north ? "N" : "S"}` };
}
