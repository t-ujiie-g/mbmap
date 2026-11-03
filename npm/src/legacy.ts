// Legacy filters and functions as expressions, ported from MapLibre's style-spec 26.5.0 (src/feature_filter/convert.ts,
// src/function/convert.ts), BSD-3-Clause, Copyright (c) 2020 MapLibre contributors; see NOTICE.
// Loaded by the map only for a style that has them. Import-free for `npm test`.

type Json = unknown;
type Expression = unknown[];
type Spec = { type: string; default: Json; interpolated: boolean; tokens: boolean; value?: string; length?: number | null; values?: string[] };
type Types = Record<string, string>;

/** Each layout and paint property: `[type, default, interpolated, ...]`, then `1` if it takes `{tokens}`, an array's item type and length, or an enum's values (from the style-spec reference). */
const PROPERTIES: Record<string, Json[]> = {
  "fill-sort-key": ["number", null, 0],
  "circle-sort-key": ["number", null, 0],
  "fill-extrusion-rounded-corner-distance": ["number", 0, 0],
  "line-cap": ["enum", "butt", 0, ["butt", "round", "square"]],
  "line-join": ["enum", "miter", 0, ["bevel", "round", "miter"]],
  "line-miter-limit": ["number", 2, 1],
  "line-round-limit": ["number", 1.05, 1],
  "line-sort-key": ["number", null, 0],
  "symbol-placement": ["enum", "point", 0, ["point", "line", "line-center"]],
  "symbol-spacing": ["number", 250, 1],
  "symbol-avoid-edges": ["boolean", false, 0],
  "symbol-sort-key": ["number", null, 0],
  "symbol-z-order": ["enum", "auto", 0, ["auto", "viewport-y", "source"]],
  "icon-allow-overlap": ["boolean", false, 0],
  "icon-overlap": ["enum", null, 0, ["never", "always", "cooperative"]],
  "icon-ignore-placement": ["boolean", false, 0],
  "icon-optional": ["boolean", false, 0],
  "icon-rotation-alignment": ["enum", "auto", 0, ["map", "viewport", "auto"]],
  "icon-size": ["number", 1, 1],
  "icon-text-fit": ["enum", "none", 0, ["none", "width", "height", "both"]],
  "icon-text-fit-padding": ["array", [0, 0, 0, 0], 1, "number", 4],
  "icon-image": ["resolvedImage", null, 0, 1],
  "icon-rotate": ["number", 0, 1],
  "icon-padding": ["padding", [2], 1],
  "icon-keep-upright": ["boolean", false, 0],
  "icon-offset": ["array", [0, 0], 1, "number", 2],
  "icon-anchor": ["enum", "center", 0, ["center", "left", "right", "top", "bottom", "top-left", "top-right", "bottom-left", "bottom-right"]],
  "icon-pitch-alignment": ["enum", "auto", 0, ["map", "viewport", "auto"]],
  "text-pitch-alignment": ["enum", "auto", 0, ["map", "viewport", "auto"]],
  "text-rotation-alignment": ["enum", "auto", 0, ["map", "viewport", "viewport-glyph", "auto"]],
  "text-field": ["formatted", "", 0, 1],
  "text-font": ["array", ["Open Sans Regular", "Arial Unicode MS Regular"], 0, "string", null],
  "text-size": ["number", 16, 1],
  "text-max-width": ["number", 10, 1],
  "text-line-height": ["number", 1.2, 1],
  "text-letter-spacing": ["number", 0, 1],
  "text-justify": ["enum", "center", 0, ["auto", "left", "center", "right"]],
  "text-radial-offset": ["number", 0, 1],
  "text-variable-anchor": ["array", null, 0, "enum", null],
  "text-variable-anchor-offset": ["variableAnchorOffsetCollection", null, 1],
  "text-anchor": ["enum", "center", 0, ["center", "left", "right", "top", "bottom", "top-left", "top-right", "bottom-left", "bottom-right"]],
  "text-max-angle": ["number", 45, 1],
  "text-writing-mode": ["array", null, 0, "enum", null],
  "text-rotate": ["number", 0, 1],
  "text-padding": ["number", 2, 1],
  "text-keep-upright": ["boolean", true, 0],
  "text-transform": ["enum", "none", 0, ["none", "uppercase", "lowercase"]],
  "text-offset": ["array", [0, 0], 1, "number", 2],
  "text-allow-overlap": ["boolean", false, 0],
  "text-overlap": ["enum", null, 0, ["never", "always", "cooperative"]],
  "text-ignore-placement": ["boolean", false, 0],
  "text-optional": ["boolean", false, 0],
  "symbol-height-offset": ["number", 0, 1],
  "symbol-height-anchor": ["enum", "ground", 0, ["ground", "absolute"]],
  "fill-antialias": ["boolean", true, 0],
  "fill-opacity": ["number", 1, 1],
  "fill-layer-opacity": ["number", 1, 1],
  "fill-layer-blend": ["enum", "normal", 0, ["normal", "multiply", "color", "luminosity", "plus-lighter", "screen", "overlay"]],
  "fill-color": ["color", "#000000", 1],
  "fill-outline-color": ["color", null, 1],
  "fill-translate": ["array", [0, 0], 1, "number", 2],
  "fill-translate-anchor": ["enum", "map", 0, ["map", "viewport"]],
  "fill-pattern": ["resolvedImage", null, 0],
  "fill-extrusion-opacity": ["number", 1, 1],
  "fill-extrusion-color": ["color", "#000000", 1],
  "fill-extrusion-translate": ["array", [0, 0], 1, "number", 2],
  "fill-extrusion-translate-anchor": ["enum", "map", 0, ["map", "viewport"]],
  "fill-extrusion-pattern": ["resolvedImage", null, 0],
  "fill-extrusion-height": ["number", 0, 1],
  "fill-extrusion-base": ["number", 0, 1],
  "fill-extrusion-vertical-gradient": ["boolean", true, 0],
  "line-opacity": ["number", 1, 1],
  "line-layer-opacity": ["number", 1, 1],
  "line-layer-blend": ["enum", "normal", 0, ["normal", "multiply", "color", "luminosity", "plus-lighter", "screen", "overlay"]],
  "line-color": ["color", "#000000", 1],
  "line-translate": ["array", [0, 0], 1, "number", 2],
  "line-translate-anchor": ["enum", "map", 0, ["map", "viewport"]],
  "line-width": ["number", 1, 1],
  "line-gap-width": ["number", 0, 1],
  "line-offset": ["number", 0, 1],
  "line-blur": ["number", 0, 1],
  "line-dasharray": ["array", null, 0, "number", null],
  "line-pattern": ["resolvedImage", null, 0],
  "line-gradient": ["color", null, 1],
  "circle-radius": ["number", 5, 1],
  "circle-color": ["color", "#000000", 1],
  "circle-blur": ["number", 0, 1],
  "circle-opacity": ["number", 1, 1],
  "circle-translate": ["array", [0, 0], 1, "number", 2],
  "circle-translate-anchor": ["enum", "map", 0, ["map", "viewport"]],
  "circle-pitch-scale": ["enum", "map", 0, ["map", "viewport"]],
  "circle-pitch-alignment": ["enum", "viewport", 0, ["map", "viewport"]],
  "circle-stroke-width": ["number", 0, 1],
  "circle-stroke-color": ["color", "#000000", 1],
  "circle-stroke-opacity": ["number", 1, 1],
  "heatmap-radius": ["number", 30, 1],
  "heatmap-weight": ["number", 1, 1],
  "heatmap-intensity": ["number", 1, 1],
  "heatmap-color": ["color", ["interpolate", ["linear"], ["heatmap-density"], 0, "rgba(0, 0, 255, 0)", 0.1, "royalblue", 0.3, "cyan", 0.5, "lime", 0.7, "yellow", 1, "red"], 1],
  "heatmap-opacity": ["number", 1, 1],
  "icon-opacity": ["number", 1, 1],
  "icon-color": ["color", "#000000", 1],
  "icon-halo-color": ["color", "rgba(0, 0, 0, 0)", 1],
  "icon-halo-width": ["number", 0, 1],
  "icon-halo-blur": ["number", 0, 1],
  "icon-translate": ["array", [0, 0], 1, "number", 2],
  "icon-translate-anchor": ["enum", "map", 0, ["map", "viewport"]],
  "text-opacity": ["number", 1, 1],
  "text-color": ["color", "#000000", 1],
  "text-halo-color": ["color", "rgba(0, 0, 0, 0)", 1],
  "text-halo-width": ["number", 0, 1],
  "text-halo-blur": ["number", 0, 1],
  "text-translate": ["array", [0, 0], 1, "number", 2],
  "text-translate-anchor": ["enum", "map", 0, ["map", "viewport"]],
  "raster-opacity": ["number", 1, 1],
  "raster-hue-rotate": ["number", 0, 1],
  "raster-brightness-min": ["number", 0, 1],
  "raster-brightness-max": ["number", 1, 1],
  "raster-saturation": ["number", 0, 1],
  "raster-contrast": ["number", 0, 1],
  "resampling": ["enum", "linear", 0, ["linear", "nearest"]],
  "raster-resampling": ["enum", "linear", 0, ["linear", "nearest"]],
  "raster-fade-duration": ["number", 300, 1],
  "hillshade-illumination-direction": ["numberArray", 335, 1],
  "hillshade-illumination-altitude": ["numberArray", 45, 1],
  "hillshade-illumination-anchor": ["enum", "viewport", 0, ["map", "viewport"]],
  "hillshade-exaggeration": ["number", 0.5, 1],
  "hillshade-shadow-color": ["colorArray", "#000000", 1],
  "hillshade-highlight-color": ["colorArray", "#FFFFFF", 1],
  "hillshade-accent-color": ["color", "#000000", 1],
  "hillshade-method": ["enum", "standard", 0, ["standard", "basic", "combined", "igor", "multidirectional"]],
  "color-relief-opacity": ["number", 1, 1],
  "color-relief-color": ["color", null, 1],
  "background-color": ["color", "#000000", 1],
  "background-pattern": ["resolvedImage", null, 0],
  "background-opacity": ["number", 1, 1],
};

function specOf(name: string): Spec | undefined {
  const row = PROPERTIES[name];
  if (!row) return undefined;
  const [type, def, interpolated, a, b] = row as [string, Json, number, Json, Json];
  return {
    type,
    default: def === null ? undefined : def,
    interpolated: interpolated === 1,
    tokens: type !== "array" && type !== "enum" && a === 1,
    ...(type === "array" ? { value: a as string, length: b as number | null } : {}),
    ...(type === "enum" ? { values: a as string[] } : {}),
  };
}

/** MapLibre's `classifyFilter` result is `legacy`: neither an expression nor a plain boolean. */
export function isLegacyFilter(filter: Json): boolean {
  return classify(filter) === 1;
}

/** 0 expression, 1 legacy, 2 neutral (MapLibre's `classifyFilter`). */
function classify(f: Json): number {
  if (typeof f === "boolean") return 2;
  if (!Array.isArray(f) || f.length === 0) return 1;
  switch (f[0]) {
    case "has":
      if (f.length < 2 || f[1] === "$id" || f[1] === "$type") return 1;
      return f.length === 2 ? 2 : 0;
    case "in":
      return f.length >= 3 && (typeof f[1] !== "string" || Array.isArray(f[2])) ? 0 : 1;
    case "!in":
    case "!has":
    case "none":
      return 1;
    case "==":
    case "!=":
    case ">":
    case ">=":
    case "<":
    case "<=":
      return f.length !== 3 || Array.isArray(f[1]) || Array.isArray(f[2]) ? 0 : 1;
    case "any":
    case "all": {
      let legacy = false;
      for (const c of f.slice(1)) {
        const k = classify(c);
        if (k === 0) return 0;
        if (k === 1) legacy = true;
      }
      return legacy ? 1 : 2;
    }
    default:
      return 0;
  }
}

/** MapLibre's `convertFilter`: a legacy filter as an expression (others unchanged). */
export function convertFilter(filter: Json, types: Types = {}): Json {
  if (classify(filter) !== 1) return filter;
  if (!filter) return true;
  const f = filter as Json[];
  const op = f[0];
  if (f.length <= 1) return op !== "any";
  switch (op) {
    case "==":
    case "!=":
    case "<":
    case ">":
    case "<=":
    case ">=":
      return compare(f[1] as string, f[2], op, types);
    case "any":
      return [
        "any",
        ...f.slice(1).map((c) => {
          const t: Types = {};
          const child = convertFilter(c, t);
          const checks = typeChecks(t);
          return checks === true ? child : ["case", checks, child, false];
        }),
      ];
    case "all": {
      const children = f.slice(1).map((c) => convertFilter(c, types));
      return children.length > 1 ? ["all", ...children] : children[0];
    }
    case "none":
      return ["!", convertFilter(["any", ...f.slice(1)], {})];
    case "in":
      return inOp(f[1] as string, f.slice(2), false);
    case "!in":
      return inOp(f[1] as string, f.slice(2), true);
    case "has":
      return hasOp(f[1] as string);
    case "!has":
      return ["!", hasOp(f[1] as string)];
    default:
      return true;
  }
}

function typeChecks(types: Types): Json {
  const checks = Object.keys(types).map((p) => ["==", ["typeof", p === "$id" ? ["id"] : ["get", p]], types[p]]);
  if (checks.length === 0) return true;
  return checks.length === 1 ? checks[0] : ["all", ...checks];
}

function compare(property: string, value: Json, op: string, types: Types): Json {
  if (property === "$type") return [op, ["geometry-type"], value];
  const get = property === "$id" ? ["id"] : ["get", property];
  if (value !== null) types[property] = typeof value;
  if (property !== "$id" && value === null) {
    if (op === "==") return ["all", ["has", property], ["==", get, null]];
    if (op === "!=") return ["any", ["!", ["has", property]], ["!=", get, null]];
  }
  return [op, get, value];
}

function inOp(property: string, values: Json[], negate: boolean): Json {
  if (values.length === 0) return negate;
  const get = property === "$type" ? ["geometry-type"] : property === "$id" ? ["id"] : ["get", property];
  const type = typeof values[0];
  if (values.every((v) => typeof v === type) && (type === "string" || type === "number")) {
    const unique = values.sort().filter((v, i) => i === 0 || values[i - 1] !== v);
    return ["match", get, unique, !negate, negate];
  }
  return negate ? ["all", ...values.map((v) => ["!=", get, v])] : ["any", ...values.map((v) => ["==", get, v])];
}

function hasOp(property: string): Json {
  if (property === "$type") return true;
  return property === "$id" ? ["!=", ["id"], null] : ["has", property];
}

/** A legacy property function: a plain object, not an expression or a constant. */
export function isFunction(value: Json): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

const literal = (v: Json): Json => (typeof v === "object" ? ["literal", v] : v);

/** MapLibre's `convertFunction` for the property `name`; undefined for a property it does not know. */
export function convertFunction(parameters: Record<string, unknown>, name: string): Json {
  const spec = specOf(name);
  if (!spec) return undefined;
  let stops = parameters.stops as [Json, Json][] | undefined;
  if (!stops) return identity(parameters, spec);
  const both = typeof stops[0][0] === "object";
  const featureDependent = both || parameters.property !== undefined;
  stops = stops.map(([input, output]) => [
    input,
    !featureDependent && spec.tokens && typeof output === "string" ? convertTokenString(output) : literal(output),
  ]);
  if (both) return zoomAndProperty(parameters, spec, stops);
  return featureDependent ? propertyFunction(parameters, spec, stops) : zoomFunction(parameters, spec, stops);
}

function identity(parameters: Record<string, unknown>, spec: Spec): Json {
  const get = ["get", parameters.property];
  if (parameters.default === undefined) return spec.type === "string" ? ["string", get] : get;
  if (spec.type === "enum") return ["match", get, spec.values, get, parameters.default];
  const e: Json[] = [spec.type === "color" ? "to-color" : spec.type, get, literal(parameters.default)];
  if (spec.type === "array") e.splice(1, 0, spec.value, spec.length || null);
  return e;
}

function interpolator(parameters: Record<string, unknown>): string {
  return parameters.colorSpace === "hcl" ? "interpolate-hcl" : parameters.colorSpace === "lab" ? "interpolate-lab" : "interpolate";
}

function functionType(parameters: Record<string, unknown>, spec: Spec): string {
  return (parameters.type as string) || (spec.interpolated ? "exponential" : "interval");
}

function zoomAndProperty(parameters: Record<string, unknown>, spec: Spec, stops: [Json, Json][]): Json {
  const byZoom = new Map<number, [Json, Json][]>();
  for (const [input, output] of stops) {
    const { zoom, value } = input as { zoom: number; value: Json };
    if (!byZoom.has(zoom)) byZoom.set(zoom, []);
    byZoom.get(zoom)!.push([value, output]);
  }
  const step = functionType({}, spec) !== "exponential";
  const e: Expression = step ? ["step", ["zoom"]] : [interpolator(parameters), ["linear"], ["zoom"]];
  for (const [zoom, s] of byZoom) {
    const output = propertyFunction({ zoom, type: parameters.type, property: parameters.property, default: parameters.default }, spec, s);
    appendStop(e, zoom, output, step);
  }
  if (step) fixupStep(e);
  return e;
}

function fallback(parameters: Record<string, unknown>, spec: Spec): Json {
  const value = literal(parameters.default !== undefined ? parameters.default : spec.default);
  return value === undefined && spec.type === "resolvedImage" ? "" : value;
}

function propertyFunction(parameters: Record<string, unknown>, spec: Spec, stops: [Json, Json][]): Json {
  const type = functionType(parameters, spec);
  const get = ["get", parameters.property];
  const typed = (e: Json): Json =>
    parameters.default === undefined ? e : ["case", ["==", ["typeof", get], "number"], e, literal(parameters.default)];
  if (type === "categorical" && typeof stops[0][0] === "boolean") {
    return ["case", ...stops.flatMap(([input, output]) => [["==", get, input], output]), fallback(parameters, spec)];
  }
  if (type === "categorical") {
    const e: Expression = ["match", get];
    for (const [input, output] of stops) appendStop(e, input, output, false);
    e.push(fallback(parameters, spec));
    return e;
  }
  if (type === "interval") {
    const e: Expression = ["step", ["number", get]];
    for (const [input, output] of stops) appendStop(e, input, output, true);
    fixupStep(e);
    return typed(e);
  }
  if (type === "exponential") {
    const base = parameters.base !== undefined ? parameters.base : 1;
    const e: Expression = [interpolator(parameters), base === 1 ? ["linear"] : ["exponential", base], ["number", get]];
    for (const [input, output] of stops) appendStop(e, input, output, false);
    return typed(e);
  }
  throw new Error(`mbmap: unknown property function type ${type}`);
}

function zoomFunction(parameters: Record<string, unknown>, spec: Spec, stops: [Json, Json][]): Json {
  const type = functionType(parameters, spec);
  let e: Expression;
  if (type === "interval") e = ["step", ["zoom"]];
  else if (type === "exponential") {
    const base = parameters.base !== undefined ? parameters.base : 1;
    e = [interpolator(parameters), base === 1 ? ["linear"] : ["exponential", base], ["zoom"]];
  } else throw new Error(`mbmap: unknown zoom function type "${type}"`);
  for (const [input, output] of stops) appendStop(e, input, output, type === "interval");
  fixupStep(e);
  return e;
}

/**
 * A one-stop step gets a stop at 0 with the same output. MapLibre's converter pushes 0 as that
 * output (a slip); its own function evaluation keeps the one value, which this follows.
 */
function fixupStep(e: Expression): void {
  if (e[0] === "step" && e.length === 3) e.push(0, e[2]);
}

function appendStop(curve: Expression, input: Json, output: Json, step: boolean): void {
  // Duplicate stops were not validated for functions; MapLibre keeps the first.
  if (curve.length > 3 && input === curve[curve.length - 2]) return;
  if (!(step && curve.length === 2)) curve.push(input);
  curve.push(output);
}

/** `"a {name} b"` as `["concat", "a ", ["get", "name"], " b"]` (MapLibre's `convertTokenString`). */
export function convertTokenString(s: string): Json {
  const result: Json[] = ["concat"];
  const re = /{([^{}]+)}/g;
  let pos = 0;
  for (let m = re.exec(s); m !== null; m = re.exec(s)) {
    const text = s.slice(pos, re.lastIndex - m[0].length);
    pos = re.lastIndex;
    if (text.length > 0) result.push(text);
    result.push(["get", m[1]]);
  }
  if (result.length === 1) return s;
  if (pos < s.length) result.push(s.slice(pos));
  else if (result.length === 2) return ["to-string", result[1]];
  return result;
}

/** `style` with its layers' legacy filters and property functions converted (a new object; the input is kept). */
export function convertStyle<T extends { layers: unknown[] }>(style: T): T {
  const props = (o: unknown) => {
    if (!isFunction(o)) return o;
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(o)) out[k] = isFunction(v) && !k.endsWith("-transition") ? (convertFunction(v, k) ?? v) : v;
    return out;
  };
  const layers = style.layers.map((l) => {
    if (!isFunction(l)) return l;
    const out: Record<string, unknown> = { ...l, paint: props(l.paint), layout: props(l.layout) };
    if (l.paint === undefined) delete out.paint;
    if (l.layout === undefined) delete out.layout;
    if (l.filter !== undefined) out.filter = convertFilter(l.filter);
    return out;
  });
  return { ...style, layers };
}
