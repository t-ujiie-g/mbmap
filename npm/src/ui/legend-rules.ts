// How a legend splits a layer's color into entries: the feature property a
// `match`, `step`, `interpolate` or `case` of `==` tests reads, and for each
// entry the properties of a feature drawn that way. Import-free.

/**
 * One legend entry: `values` it matches (`match`, `case`), its `range` [from, to) (`step`; null
 * ends are open), its `value` (an `interpolate` stop), or `other` (the fallback); `properties` make a
 * feature drawn as the entry is.
 */
export interface LegendCategory {
  values?: unknown[];
  range?: [number | null, number | null];
  value?: number;
  other?: boolean;
  properties: Record<string, unknown>;
}

/** `property` is null when the color does not depend on a feature property (one entry). */
export interface Breakdown {
  kind: "single" | "match" | "step" | "interpolate";
  property: string | null;
  categories: LegendCategory[];
}

/** The color paint property of each layer type, which the legend breaks down. */
export const COLOR_PROPERTY: Record<string, string> = {
  background: "background-color",
  fill: "fill-color",
  line: "line-color",
  circle: "circle-color",
  symbol: "text-color",
  "fill-extrusion": "fill-extrusion-color",
};

const CASTS = new Set(["to-string", "to-number", "string", "number", "to-boolean", "boolean"]);

/** The property `["get", key]` reads, through type casts; null for anything else. */
function propertyOf(input: unknown): string | null {
  if (!Array.isArray(input)) return null;
  if (input[0] === "get" && input.length === 2 && typeof input[1] === "string") return input[1];
  if (CASTS.has(input[0]) && input.length >= 2) return propertyOf(input[1]);
  return null;
}

const single: Breakdown = { kind: "single", property: null, categories: [{ properties: {} }] };

/** The entries of a color expression; anything not keyed on one property is a single entry. */
export function breakdown(expr: unknown): Breakdown {
  if (!Array.isArray(expr)) return single;
  const [op] = expr;
  if (op === "match") {
    const key = propertyOf(expr[1]);
    if (!key) return single;
    const categories: LegendCategory[] = [];
    for (let i = 2; i + 1 < expr.length; i += 2) {
      const values = Array.isArray(expr[i]) ? (expr[i] as unknown[]) : [expr[i]];
      categories.push({ values, properties: { [key]: values[0] } });
    }
    // Without the property, no label matches and the fallback is drawn.
    categories.push({ other: true, properties: {} });
    return { kind: "match", property: key, categories };
  }
  if (op === "case") {
    const conditions: [string, unknown][] = [];
    for (let i = 1; i + 1 < expr.length; i += 2) {
      const c = expr[i];
      const key = Array.isArray(c) && c[0] === "==" ? propertyOf(c[1]) : null;
      if (!key || Array.isArray(c[2])) return single;
      conditions.push([key, c[2]]);
    }
    const key = conditions[0]?.[0];
    if (!key || conditions.some(([k]) => k !== key)) return single;
    const categories: LegendCategory[] = conditions.map(([, v]) => ({ values: [v], properties: { [key]: v } }));
    categories.push({ other: true, properties: {} });
    return { kind: "match", property: key, categories };
  }
  if (op === "step") {
    const key = propertyOf(expr[1]);
    const stops = expr.filter((_, i) => i >= 3 && i % 2 === 1).map(Number);
    if (!key || stops.length === 0 || stops.some((s) => !Number.isFinite(s))) return single;
    const bounds = [null, ...stops, null];
    const categories = bounds.slice(0, -1).map((from, i) => {
      const to = bounds[i + 1];
      // A value inside the range: its start, or below the first stop.
      return { range: [from, to] as [number | null, number | null], properties: { [key]: from ?? stops[0] - 1 } };
    });
    return { kind: "step", property: key, categories };
  }
  if (op === "interpolate" || op === "interpolate-hcl" || op === "interpolate-lab") {
    const key = propertyOf(expr[2]);
    if (!key) return single;
    const categories = expr
      .filter((_, i) => i >= 3 && i % 2 === 1)
      .map((v) => ({ value: Number(v), properties: { [key]: Number(v) } }));
    return { kind: "interpolate", property: key, categories };
  }
  return single;
}

/** A plain label for a category; legends pass their own for anything better. */
export function defaultLabel(c: LegendCategory): string {
  if (c.other) return "other";
  if (c.values) return c.values.map(String).join(", ");
  if (c.range) {
    const [from, to] = c.range;
    return from === null ? `< ${to}` : to === null ? `≥ ${from}` : `${from} – ${to}`;
  }
  return c.value !== undefined ? String(c.value) : "";
}
