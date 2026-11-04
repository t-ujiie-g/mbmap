///|
/// An HTMLCanvasElement (or OffscreenCanvas).
#external
pub type Canvas

///|
/// A JS ArrayBuffer holding packed vertices or indices from the worker.
#external
pub type JsBuffer

///|
/// GPU buffers and vertex array of one tile layer.
#external
pub type Mesh

///|
#external
type Gl

///|
/// The WebGL2 context with its programs; JS null if WebGL2 is unavailable.
extern "js" fn create_gl(canvas : Canvas) -> Gl =
  #|(canvas) => {
  #|  const gl = canvas.getContext("webgl2", { antialias: false, alpha: false, depth: true, stencil: true, premultipliedAlpha: true });
  #|  if (!gl) return null;
  #|  const compile = (type, src) => {
  #|    const s = gl.createShader(type);
  #|    gl.shaderSource(s, src);
  #|    gl.compileShader(s);
  #|    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
  #|    return s;
  #|  };
  #|  const program = (vs, fs, uniforms) => {
  #|    const p = gl.createProgram();
  #|    gl.attachShader(p, compile(gl.VERTEX_SHADER, "#version 300 es\n" + vs));
  #|    gl.attachShader(p, compile(gl.FRAGMENT_SHADER, "#version 300 es\nprecision highp float;\n" + fs));
  #|    gl.bindAttribLocation(p, 0, "a_pos");
  #|    gl.bindAttribLocation(p, 1, "a_data");
  #|    gl.bindAttribLocation(p, 2, "a_tex");
  #|    gl.bindAttribLocation(p, 2, "a_offset");
  #|    gl.bindAttribLocation(p, 3, "a_size");
  #|    gl.bindAttribLocation(p, 4, "a_ele");
  #|    gl.bindAttribLocation(p, 1, "a_normal");
  #|    gl.bindAttribLocation(p, 3, "a_heights");
  #|    gl.bindAttribLocation(p, 13, "a_dist");
  #|    gl.bindAttribLocation(p, 14, "a_progress");
  #|    gl.bindAttribLocation(p, 15, "a_shift");
  #|    gl.bindAttribLocation(p, 15, "a_dash");
  #|    gl.bindAttribLocation(p, 13, "a_glyph");
  #|    gl.bindAttribLocation(p, 5, "a_fill");
  #|    gl.bindAttribLocation(p, 14, "a_section");
  #|    // The paint slots (@style.SLOT_*), from a layer's per-vertex paint or a constant.
  #|    ["a_color_lo", "a_color_hi", "a_opacity", "a_extent", "a_stroke_lo", "a_stroke_hi", "a_stroke_opacity", "a_stroke_width"]
  #|      .forEach((name, i) => gl.bindAttribLocation(p, 5 + i, name));
  #|    gl.linkProgram(p);
  #|    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
  #|    const u = { program: p };
  #|    for (const name of uniforms) u[name] = gl.getUniformLocation(p, name);
  #|    return u;
  #|  };
  #|  // u_clip is a rectangle in tile units outside which nothing is drawn: a
  #|  // loaded ancestor stands in for a missing tile clipped to its area.
  #|  const clip = "uniform vec4 u_clip; in vec2 v_pos;" +
  #|    "bool outside() { return any(lessThan(v_pos, u_clip.xy)) || any(greaterThanEqual(v_pos, u_clip.zw)); }";
  #|  // Paint values: each slot holds a value and the next along its zoom curve,
  #|  // mixed by u_t (one per slot); colors are straight RGBA, premultiplied here.
  #|  const paint = "uniform float u_t[6]; in vec4 a_color_lo; in vec4 a_color_hi; in vec2 a_opacity; in vec2 a_extent;" +
  #|    "in vec4 a_stroke_lo; in vec4 a_stroke_hi; in vec2 a_stroke_opacity; in vec2 a_stroke_width;" +
  #|    "float at(vec2 v, int s) { return mix(v.x, v.y, u_t[s]); }" +
  #|    "vec4 premul(vec4 c, float o) { float a = c.a * o; return vec4(c.rgb * a, a); }" +
  #|    "vec4 color() { return premul(mix(a_color_lo, a_color_hi, u_t[0]), at(a_opacity, 1)); }";
  #|  const fill = program(
  #|    paint + "in vec2 a_pos; uniform mat4 u_matrix; out vec2 v_pos; out vec4 v_color;" +
  #|    "void main() { v_pos = a_pos; v_color = color(); gl_Position = u_matrix * vec4(a_pos, 0.0, 1.0); }",
  #|    clip + "in vec4 v_color; out vec4 o; void main() { if (outside()) discard; o = v_color; }",
  #|    ["u_matrix", "u_clip", "u_t"]);
  #|  // Extrusion is in tile units (u_units device pixels at the center's depth
  #|  // u_depth), so lines thin with distance; the last pixel of the half width
  #|  // v_half, taken at the vertex's own depth, fades out (MapLibre's gamma scale).
  #|  // MapLibre's fill outline: 1 px lines along ring edges, faded by the pixel's
  #|  // distance to the line's position (u_world: the drawing buffer's size).
  #|  const fillOutline = program(
  #|    paint + "in vec2 a_pos; uniform mat4 u_matrix; uniform vec2 u_world; out vec2 v_pos; out vec2 v_line; out vec4 v_color;" +
  #|    "void main() { v_pos = a_pos; v_color = premul(mix(a_stroke_lo, a_stroke_hi, u_t[3]), at(a_opacity, 1));" +
  #|    "  gl_Position = u_matrix * vec4(a_pos, 0.0, 1.0); v_line = (gl_Position.xy / gl_Position.w + 1.0) / 2.0 * u_world; }",
  #|    clip + "in vec2 v_line; in vec4 v_color; out vec4 o;" +
  #|    "void main() { if (outside()) discard; o = v_color * (1.0 - smoothstep(0.0, 1.0, length(v_line - gl_FragCoord.xy))); }",
  #|    ["u_matrix", "u_clip", "u_t", "u_world"]);
  #|  // MapLibre's line: outset and inset (device px) from the width and the gap width
  #|  // (slot 4), moved along a_offset by the offset (slot 5); edges fade over the blur
  #|  // u_blur and a pixel, scaled to the vertex's depth (v_scale).
  #|  // Dashes are MapLibre's line_sdf: a_dist (tile units along the line) over the
  #|  // pattern's length u_dash.x, the atlas row u_dash.y spanning u_dash.z
  #|  // across the line, edges smoothed by u_dash.w; all in floor widths
  #|  // (u_floor.x, or the width slot mixed by u_floor.y when it is negative).
  #|  // Dashes by feature (dash 2) take the row, height and width from a_dash (row
  #|  // times 64 plus height, width, edge lengths zooming in and out; a negative
  #|  // width draws solid), u_dash holding px per unit, 1 / atlas height, 1 / dpr
  #|  // and whether to take the zooming-in edge.
  #|  // Gradients are MapLibre's line_gradient: the color at a_progress (share
  #|  // of the line, row of u_rows) in the ramp u_image, premultiplied.
  #|  // Line patterns are MapLibre's line_pattern: the image as tall as the floor
  #|  // width across the line, repeating along a_dist (u_size: its CSS size,
  #|  // u_along: CSS px per tile unit at the integer zoom).
  #|  const lineProgram = (dash, grad, pat) => program(
  #|    paint + "in vec2 a_pos; in vec4 a_data; in vec2 a_offset; uniform mat4 u_matrix; uniform float u_units; uniform float u_dpr;" +
  #|    "uniform float u_depth; out vec2 v_edge; out vec2 v_pos; out vec2 v_width; out float v_scale; out vec4 v_color;" +
  #|    (dash ? "in float a_dist; uniform vec4 u_dash; uniform vec2 u_floor; out vec2 v_tex; out float v_gamma;" : "") +
  #|    (dash === 2 ? "in vec4 a_dash; flat out float v_mode;" : "") +
  #|    (grad ? "in vec2 a_progress; uniform float u_rows; out vec2 v_uv; out float v_opacity;" : "") +
  #|    (pat ? "in float a_dist; uniform vec2 u_floor; out float v_dist; out float v_fw; out float v_opacity;" : "") +
  #|    "void main() { float aa = 0.5; float gap = at(a_stroke_opacity, 4) * u_dpr / 2.0;" +
  #|    "  float half_ = at(a_extent, 2) * u_dpr / 2.0;" +
  #|    "  float inset = gap + (gap > 0.0 ? aa : 0.0);" +
  #|    "  float outset = gap + half_ * (gap > 0.0 ? 2.0 : 1.0) + (half_ == 0.0 ? 0.0 : aa);" +
  #|    "  vec2 off = at(a_stroke_width, 5) * u_dpr * a_offset / 63.0;" +
  #|    "  v_pos = a_pos + (off + a_data.xy / 63.0 * outset) * u_units; v_color = color();" +
  #|    "  gl_Position = u_matrix * vec4(v_pos, 0.0, 1.0); v_edge = a_data.zw;" +
  #|    (dash ? "  float fw = u_floor.x >= 0.0 ? u_floor.x : mix(a_extent.x, a_extent.y, u_floor.y);" : "") +
  #|    (dash === 2 ? "  float row = floor(a_dash.x / 64.0); float h = a_dash.x - row * 64.0;" +
  #|      "  float g = u_dash.w > 0.5 ? a_dash.z : a_dash.w; v_mode = a_dash.y < 0.0 ? 1.0 : a_dash.y == 0.0 || g <= 0.0 ? 2.0 : 0.0;" +
  #|      "  v_tex = vec2(a_dist * u_dash.x / a_dash.y / fw, (a_data.z * -h / 2.0 + row + 0.5) * u_dash.y); v_gamma = u_dash.z / g / fw;" :
  #|      dash ? "  v_tex = vec2(a_dist * u_dash.x / fw, a_data.z * u_dash.z + u_dash.y); v_gamma = u_dash.w / fw;" : "") +
  #|    (grad ? "  v_uv = vec2(a_progress.x, (a_progress.y + 0.5) / u_rows); v_opacity = at(a_opacity, 1);" : "") +
  #|    (pat ? "  v_dist = a_dist; v_opacity = at(a_opacity, 1);" +
  #|      "  v_fw = u_floor.x >= 0.0 ? u_floor.x : mix(a_extent.x, a_extent.y, u_floor.y);" : "") +
  #|    "  v_width = vec2(outset, inset); v_scale = gl_Position.w / u_depth; }",
  #|    // v_edge is (side, along): its length reaches 1 at the outline and
  #|    // around round caps.
  #|    clip + "in vec4 v_color; in vec2 v_edge; in vec2 v_width; in float v_scale; uniform float u_blur; out vec4 o;" +
  #|    (dash ? "uniform sampler2D u_image; in vec2 v_tex; in float v_gamma;" : "") +
  #|    (dash === 2 ? "flat in float v_mode;" : "") +
  #|    (grad ? "uniform sampler2D u_image; in vec2 v_uv; in float v_opacity;" : "") +
  #|    (pat ? "uniform sampler2D u_image; uniform vec4 u_pattern; uniform vec2 u_texsize; uniform vec2 u_size;" +
  #|      "uniform float u_along; in float v_dist; in float v_fw; in float v_opacity;" : "") +
  #|    "void main() { if (outside()) discard;" +
  #|    (grad ? "  vec4 c = texture(u_image, v_uv) * v_opacity;" : pat ?
  #|      "  float x = mod(v_dist * u_along / u_size.x * u_size.y / v_fw, 1.0); vec2 ts = 1.0 / u_texsize;" +
  #|      "  vec4 c = texture(u_image, mix(u_pattern.xy * ts - ts, u_pattern.zw * ts + ts, vec2(x, 0.5 - 0.5 * v_edge.x))) * v_opacity;" :
  #|      "  vec4 c = v_color;") +
  #|    "  float d = length(v_edge) * v_width.x; float b = (u_blur + 1.0) * v_scale;" +
  #|    "  o = c * clamp(min(d - (v_width.y - b), v_width.x - d) / b, 0.0, 1.0);" +
  #|    (dash === 2 ? "  if (v_mode > 1.5) discard; if (v_mode < 0.5)" : "") +
  #|    (dash ? "  o *= smoothstep(0.5 - v_gamma, 0.5 + v_gamma, texture(u_image, v_tex).r);" : "") + " }",
  #|    ["u_matrix", "u_units", "u_dpr", "u_depth", "u_clip", "u_t", "u_blur", ...(dash ? ["u_dash", "u_floor", "u_image"] : []),
  #|      ...(grad ? ["u_rows", "u_image"] : []), ...(pat ? ["u_floor", "u_image", "u_pattern", "u_texsize", "u_size", "u_along"] : [])]);
  #|  const line = lineProgram(false, false, false), lineDash = lineProgram(true, false, false), lineDashFeature = lineProgram(2, false, false);
  #|  const lineGradient = lineProgram(false, true, false), linePattern = lineProgram(false, false, true);
  #|  // MapLibre's patterns (fill_pattern, fill_outline_pattern, background_pattern):
  #|  // tile units in CSS pixels at the integer zoom (u_units), offset by the tile's
  #|  // pixel position (u_pixel: upper and lower 16 bits) modulo the pattern's size
  #|  // u_size, so patterns line up across tiles; u_pattern is its atlas rectangle.
  #|  const patternPos = "uniform vec2 u_size; uniform vec4 u_pixel; uniform float u_units;" +
  #|    "vec2 patternPos(vec2 pos) { vec2 off = mod(mod(mod(u_pixel.xy, u_size) * 256.0, u_size) * 256.0 + u_pixel.zw, u_size);" +
  #|    "  return (u_units * pos + off) / u_size; }";
  #|  // An SDF pattern is the paint color where its alpha passes the edge.
  #|  const patternColor = "uniform vec4 u_pattern; uniform vec2 u_texsize; uniform sampler2D u_image; uniform bool u_sdf;" +
  #|    "vec4 patternColor(vec2 v, vec4 color, float opacity) {" +
  #|    "  vec4 t = texture(u_image, mix(u_pattern.xy / u_texsize, u_pattern.zw / u_texsize, mod(v, 1.0)));" +
  #|    "  if (!u_sdf) return t * opacity;" +
  #|    "  float g = max(fwidth(t.a) * 0.5, 1.0 / 255.0 / 16.0); float e = (256.0 - 64.0) / 256.0;" +
  #|    "  return color * smoothstep(e - g, e + g, t.a); }";
  #|  const patternUniforms = ["u_size", "u_pixel", "u_units", "u_pattern", "u_texsize", "u_image", "u_sdf"];
  #|  const fillPattern = program(
  #|    paint + patternPos + "in vec2 a_pos; uniform mat4 u_matrix; out vec2 v_pos; out vec2 v_pat; out vec4 v_color; out float v_opacity;" +
  #|    "void main() { v_pos = a_pos; v_pat = patternPos(a_pos); v_color = color(); v_opacity = at(a_opacity, 1);" +
  #|    "  gl_Position = u_matrix * vec4(a_pos, 0.0, 1.0); }",
  #|    clip + patternColor + "in vec2 v_pat; in vec4 v_color; in float v_opacity; out vec4 o;" +
  #|    "void main() { if (outside()) discard; o = patternColor(v_pat, v_color, v_opacity); }",
  #|    ["u_matrix", "u_clip", "u_t", ...patternUniforms]);
  #|  const fillOutlinePattern = program(
  #|    paint + patternPos + "in vec2 a_pos; uniform mat4 u_matrix; uniform vec2 u_world; out vec2 v_pos; out vec2 v_line;" +
  #|    "out vec2 v_pat; out vec4 v_color; out float v_opacity;" +
  #|    "void main() { v_pos = a_pos; v_pat = patternPos(a_pos); v_color = color(); v_opacity = at(a_opacity, 1);" +
  #|    "  gl_Position = u_matrix * vec4(a_pos, 0.0, 1.0); v_line = (gl_Position.xy / gl_Position.w + 1.0) / 2.0 * u_world; }",
  #|    clip + patternColor + "in vec2 v_line; in vec2 v_pat; in vec4 v_color; in float v_opacity; out vec4 o;" +
  #|    "void main() { if (outside()) discard;" +
  #|    "  o = patternColor(v_pat, v_color, v_opacity) * (1.0 - smoothstep(0.0, 1.0, length(v_line - gl_FragCoord.xy))); }",
  #|    ["u_matrix", "u_clip", "u_t", "u_world", ...patternUniforms]);
  #|  const backgroundPattern = program(
  #|    patternPos + "in vec2 a_pos; uniform mat4 u_matrix; out vec2 v_pat;" +
  #|    "void main() { v_pat = patternPos(a_pos); gl_Position = u_matrix * vec4(a_pos, 0.0, 1.0); }",
  #|    patternColor + "uniform float u_opacity; uniform vec4 u_color; in vec2 v_pat; out vec4 o;" +
  #|    "void main() { o = patternColor(v_pat, u_color, u_opacity); }",
  #|    ["u_matrix", "u_opacity", "u_color", ...patternUniforms]);
  #|  gl.enable(gl.BLEND);
  #|  gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
  #|  // MapLibre's circles: facing the viewer (u_pitch false) and grown as the map
  #|  // (u_scale: u_size device pixels at the center's depth), or lying on the map
  #|  // (u_units tile units per device pixel), or kept on screen with u_scale false.
  #|  // u_inner is the fill radius over u_size, the stroke lies outside it.
  #|  // The radius and stroke width (CSS px times u_dpr) from a_extent and a_stroke_width;
  #|  // a circle of size 0 is moved out of clip space. Edges fade over a pixel or the
  #|  // blur u_blur (a share of the size). Without a stroke the edge fades to the fill color.
  #|  const circle = program(
  #|    paint + "in vec2 a_pos; in vec4 a_data; uniform mat4 u_matrix; uniform vec2 u_px; uniform float u_dpr;" +
  #|    "uniform float u_depth; uniform float u_units; uniform bool u_scale; uniform bool u_pitch;" +
  #|    "out vec2 v_extrude; out vec2 v_pos; out vec4 v_color; out vec4 v_stroke;" +
  #|    "out float v_size; out float v_inner;" +
  #|    "void main() { float r = at(a_extent, 2) * u_dpr; float w = at(a_stroke_width, 5) * u_dpr;" +
  #|    "  v_size = r + w; v_inner = v_size > 0.0 ? r / v_size : 0.0; v_color = color();" +
  #|    "  v_stroke = w > 0.0 ? premul(mix(a_stroke_lo, a_stroke_hi, u_t[3]), at(a_stroke_opacity, 4)) : v_color;" +
  #|    "  v_pos = a_pos; v_extrude = a_data.xy / 63.0; vec4 c = u_matrix * vec4(a_pos, 0.0, 1.0);" +
  #|    "  if (u_pitch) { float k = u_scale ? 1.0 : c.w / u_depth;" +
  #|    "    c = u_matrix * vec4(a_pos + v_extrude * v_size * u_units * k, 0.0, 1.0); }" +
  #|    "  else c += vec4(v_extrude * v_size * u_px * (u_scale ? u_depth : c.w), 0.0, 0.0);" +
  #|    "  gl_Position = v_size > 0.0 ? c : vec4(2.0, 2.0, 2.0, 1.0); }",
  #|    clip + "in vec4 v_color; in vec4 v_stroke; in float v_size; in float v_inner;" +
  #|    "uniform float u_blur; in vec2 v_extrude; out vec4 o;" +
  #|    "void main() { if (outside()) discard; float d = length(v_extrude); float aa = max(1.0 / v_size, u_blur);" +
  #|    "  float t = smoothstep(v_inner - aa, v_inner, d);" +
  #|    "  o = mix(v_color, v_stroke, t) * (1.0 - smoothstep(1.0 - aa, 1.0, d)); }",
  #|    ["u_matrix", "u_px", "u_dpr", "u_depth", "u_clip", "u_t", "u_units", "u_scale", "u_pitch", "u_blur"]);
  #|  // MapLibre's heatmap shaders: a Gaussian kernel per point on the map, its quad
  #|  // grown until the kernel falls to 1/255/16, radius in CSS px times u_extrude (tile
  #|  // units); weight and radius in the opacity and size slots.
  #|  const heatmap = program(
  #|    paint + "in vec2 a_pos; in vec4 a_data; uniform mat4 u_matrix; uniform float u_extrude; uniform float u_intensity;" +
  #|    "out vec2 v_extrude; out float v_weight;" +
  #|    "void main() { float w = at(a_opacity, 1); v_weight = w;" +
  #|    "  float s = sqrt(-2.0 * log(1.0 / 255.0 / 16.0 / w / u_intensity / 0.3989422804014327)) / 3.0;" +
  #|    "  v_extrude = s * a_data.xy / 63.0;" +
  #|    "  gl_Position = u_matrix * vec4(a_pos + v_extrude * at(a_extent, 2) * u_extrude, 0.0, 1.0); }",
  #|    "uniform float u_intensity; in vec2 v_extrude; in float v_weight; out vec4 o;" +
  #|    "void main() { float d = -0.5 * 3.0 * 3.0 * dot(v_extrude, v_extrude);" +
  #|    "  o = vec4(v_weight * u_intensity * 0.3989422804014327 * exp(d), 1.0, 1.0, 1.0); }",
  #|    ["u_matrix", "u_t", "u_extrude", "u_intensity"]);
  #|  // The density u_image over the viewport (a quad from gl_VertexID), colored by u_ramp.
  #|  const heatmapTexture = program(
  #|    "out vec2 v_pos; void main() { v_pos = vec2(gl_VertexID & 1, gl_VertexID >> 1);" +
  #|    "  gl_Position = vec4(v_pos * 2.0 - 1.0, 0.0, 1.0); }",
  #|    "uniform sampler2D u_image; uniform sampler2D u_ramp; uniform float u_opacity; in vec2 v_pos; out vec4 o;" +
  #|    "void main() { o = texture(u_ramp, vec2(texture(u_image, v_pos).r, 0.5)) * u_opacity; }",
  #|    ["u_image", "u_ramp", "u_opacity"]);
  #|  // a_data: corner offset in 16ths of a CSS px (y down), a_shift: the label's in CSS px;
  #|  // a_size: text size in 1/16 px, all times MapLibre's perspective ratio; a_ele: anchor
  #|  // height (m); a_fill a format section's color where a_section is 1.
  #|  // The anchor in clip space and its visibility behind terrain (v_alpha).
  #|  const symbolBase = "in vec2 a_pos; in vec2 a_data; in vec2 a_tex; in float a_size; in float a_ele; in vec2 a_shift; in vec3 a_glyph;" +
  #|    "uniform mat4 u_matrix; uniform float u_along;" +
  #|    "uniform vec2 u_px; uniform float u_dpr; uniform vec2 u_atlas; uniform float u_center; uniform float u_scale;" +
  #|    "uniform highp sampler2D u_depth; uniform bool u_occlude; out vec2 v_tex; out float v_scale; out float v_alpha; out float v_gamma;" +
  #|    "float visible(vec3 f) { float d = texture(u_depth, f.xy * 0.5 + 0.5).r * 2.0 - 1.0 + 0.0001 - f.z;" +
  #|    "  return 1.0 - clamp(-d * 500.0, 0.0, 1.0); }" +
  #|    "vec4 anchor() { vec4 c = u_matrix * vec4(a_pos, a_ele * u_scale, 1.0); v_alpha = 1.0;" +
  #|    "  if (u_occlude) { vec3 f = c.xyz / c.w; v_alpha = visible(f);" +
  #|    "    if (v_alpha <= 0.95) v_alpha = (v_alpha + visible(f + vec3(0.0, 0.01, 0.0))) / 2.0; }" +
  #|    "  v_tex = a_tex / u_atlas; return c; }";
  #|  const symbolUniforms = ["u_matrix", "u_px", "u_dpr", "u_atlas", "u_center", "u_scale", "u_depth", "u_occlude", "u_along", "u_glyphs", "u_color",
  #|    "u_halo_color", "u_halo", "u_opacity", "u_gamma_scale"];
  #|  // MapLibre's symbol_sdf fragment: the SDF's edge at 0.75 (d its `channel`), 1/8 per glyph px at
  #|  // v_scale (its fontScale), smoothed by v_gamma over u_gamma_scale; u_halo: width, blur, plain.
  #|  const sdf = (channel, color, head) => head +
  #|    "uniform sampler2D u_glyphs; uniform vec4 u_halo_color; uniform vec3 u_halo;" +
  #|    "uniform float u_dpr; uniform float u_opacity; uniform float u_gamma_scale; in vec2 v_tex; in float v_scale; in float v_alpha;" +
  #|    "in float v_gamma; out vec4 o;" +
  #|    "void main() { vec4 t = texture(u_glyphs, v_tex); float a = u_opacity * v_alpha; if (!u_sdf) { o = t * a; return; }" +
  #|    "  float e = 0.105 / u_dpr, g = e / (v_scale * u_gamma_scale) * v_gamma, d = t." + channel + ";" +
  #|    "  vec4 f = a * smoothstep(0.75 - g, 0.75 + g, d) * " + color + "; o = f;" +
  #|    "  if (u_halo.x > 0.0) { float gh = (u_halo.y * 1.19 / 8.0 + e) / (v_scale * u_gamma_scale) * v_gamma;" +
  #|    "    float he = (6.0 - u_halo.x / v_scale) / 8.0;" +
  #|    "    float ah = min(smoothstep(he - gh, he + gh, d), 1.0 - smoothstep(0.75, 0.75 + 2.0 * gh, d));" +
  #|    "    vec4 h = a * ah * u_halo_color; o = u_halo.z > 0.0 ? f + (1.0 - f.a) * h : h; } }";
  #|  const symbol = program(
  #|    symbolBase + "in vec4 a_fill; in float a_section; uniform vec4 u_color; uniform float u_fill_opacity; out vec4 v_color;" +
  #|    "void main() { vec4 c = anchor(); v_color = a_section > 0.5 ? vec4(a_fill.rgb * a_fill.a, a_fill.a) * u_fill_opacity : u_color; v_gamma = 1.0;" +
  #|    "  if (v_alpha < 0.1 || (u_along > 0.0 && a_glyph.x < -1e8)) { gl_Position = vec4(-2.0, -2.0, -2.0, 1.0); return; }" +
  #|    // Along a line: the glyph at a_glyph (tile units, angle), lying on the map, sized
  #|    // by MapLibre's ratio for text pitched with the map; u_along is tile units per px.
  #|    "  if (u_along > 0.0) { float q = clamp(0.5 + 0.5 * c.w / u_center, 0.0, 4.0);" +
  #|    "    float s = sin(a_glyph.z), k = cos(a_glyph.z);" +
  #|    "    vec4 p = u_matrix * vec4(a_glyph.xy + mat2(k, s, -s, k) * a_data * 0.0625 * q * u_along, a_ele * u_scale, 1.0);" +
  #|    "    gl_Position = p; v_scale = a_size / 384.0 * q; v_gamma = p.w; return; }" +
  #|    "  float r = clamp(0.5 + 0.5 * u_center / c.w, 0.0, 4.0);" +
  #|    "  vec2 off = (a_data * 0.0625 + a_shift) * r * u_dpr * u_px * vec2(1.0, -1.0);" +
  #|    "  gl_Position = vec4(c.xy + off * c.w, c.z, c.w); v_scale = a_size / 384.0 * r; }",
  #|    sdf("r", "v_color", "in vec4 v_color; const bool u_sdf = true;"),
  #|    [...symbolUniforms, "u_fill_opacity"]);
  #|  // MapLibre's symbol_icon and, for SDF icons, symbol_sdf: a_data a corner at size 1 in 32nds of a
  #|  // px, a_size the size times 128 unless u_size is set; u_angle turns icons pitched with the map
  #|  // (u_units tile units per px), u_rotate turns the others with it. u_halo: width, blur, plain.
  #|  const icon = program(
  #|    symbolBase + "uniform float u_size; uniform bool u_persp; uniform bool u_pitch; uniform bool u_rotate; uniform float u_angle;" +
  #|    "uniform float u_units;" +
  #|    "void main() { vec4 c = anchor(); bool along = u_along > 0.0;" +
  #|    "  if (v_alpha < 0.1 || (along && a_glyph.x < -1e8)) { gl_Position = vec4(-2.0, -2.0, -2.0, 1.0); return; }" +
  #|    "  float size = u_size >= 0.0 ? u_size : a_size / 128.0; vec2 off = a_data / 32.0;" +
  #|    "  if (u_pitch) { if (u_persp) size *= clamp(0.5 + 0.5 * c.w / u_center, 0.0, 4.0);" +
  #|    "    float t = u_angle + (along ? a_glyph.z : 0.0), s = sin(t), k = cos(t);" +
  #|    "    gl_Position = u_matrix * vec4((along ? a_glyph.xy : a_pos) + mat2(k, s, -s, k) * (off * size + a_shift) * u_units," +
  #|    "      a_ele * u_scale, 1.0);" +
  #|    "    v_scale = size; v_gamma = gl_Position.w; return; }" +
  #|    "  float r = clamp(0.5 + 0.5 * u_center / c.w, 0.0, 4.0); if (u_persp) size *= r; off *= size;" +
  #|    "  if (u_rotate) { vec4 e = u_matrix * vec4(a_pos + vec2(1.0, 0.0), a_ele * u_scale, 1.0);" +
  #|    "    vec2 d = e.xy / e.w - c.xy / c.w; float t = atan(d.y * u_px.x / u_px.y, d.x), s = sin(t), k = cos(t);" +
  #|    "    off = mat2(k, -s, s, k) * off; }" +
  #|    "  gl_Position = vec4(c.xy + (off + a_shift * r) * u_dpr * u_px * vec2(1.0, -1.0) * c.w, c.z, c.w);" +
  #|    "  v_scale = size; v_gamma = 1.0; }",
  #|    sdf("a", "u_color", "uniform vec4 u_color; uniform bool u_sdf;"),
  #|    [...symbolUniforms, "u_sdf", "u_size", "u_persp", "u_pitch", "u_rotate", "u_angle", "u_units"]);
  #|  // MapLibre's fill_extrusion shaders; vertices as in docs/FORMATS.md, a_ele the
  #|  // ground (m) under the centroid times u_ground (0 without terrain, which also
  #|  // skips the 10 m basement), u_scale world pixels per meter.
  #|  const extrusion = program(
  #|    "in vec2 a_pos; in ivec3 a_normal; in vec4 a_heights; in float a_ele; uniform mat4 u_matrix;" +
  #|    "uniform float u_t; uniform float u_scale; uniform float u_ground; uniform vec3 u_lightpos;" +
  #|    "uniform float u_lightintensity; uniform vec3 u_lightcolor; uniform float u_vertical_gradient;" +
  #|    "uniform float u_opacity; uniform vec3 u_color; out vec4 v_color; out vec2 v_pos;" +
  #|    "void main() { float base = mix(a_heights.x, a_heights.y, u_t) * 0.1;" +
  #|    "  float height = mix(a_heights.z, a_heights.w, u_t) * 0.1; vec3 normal = vec3(a_normal);" +
  #|    "  float gradient_base = max(0.0, base), gradient_height = max(0.0, height);" +
  #|    "  float top = a_ele * u_ground, bottom = u_ground > 0.0 ? top - (base > 0.0 ? 0.0 : 10.0) : 0.0;" +
  #|    "  base = max(0.0, base) + bottom; height = max(0.0, height) + top;" +
  #|    "  float t = float(a_normal.x & 1); v_pos = a_pos;" +
  #|    "  gl_Position = u_matrix * vec4(a_pos, (t > 0.0 ? height : base) * u_scale, 1.0);" +
  #|    "  vec3 color = u_color; float colorvalue = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722;" +
  #|    "  v_color = vec4(0.0, 0.0, 0.0, 1.0); color += vec3(0.03);" +
  #|    "  float directional = clamp(dot(normal / 16384.0, u_lightpos), 0.0, 1.0);" +
  #|    "  directional = mix(1.0 - u_lightintensity, max(1.0 - colorvalue + u_lightintensity, 1.0), directional);" +
  #|    "  if (normal.z == 0.0) directional *= (1.0 - u_vertical_gradient) + u_vertical_gradient *" +
  #|    "    clamp((t + gradient_base) * pow(gradient_height / 150.0, 0.5), mix(0.7, 0.98, 1.0 - u_lightintensity), 1.0);" +
  #|    "  v_color.rgb += clamp(color * directional * u_lightcolor, mix(vec3(0.0), vec3(0.3), 1.0 - u_lightcolor), vec3(1.0));" +
  #|    "  v_color *= u_opacity; }",
  #|    clip + "in vec4 v_color; out vec4 o; void main() { if (outside()) discard; o = v_color; }",
  #|    ["u_matrix", "u_clip", "u_t", "u_scale", "u_ground", "u_lightpos", "u_lightintensity", "u_lightcolor",
  #|     "u_vertical_gradient", "u_opacity", "u_color"]);
  #|  // MapLibre's fill_extrusion_pattern: roofs take the pattern in tile units,
  #|  // walls along their distance (a_normal.w, in 8192 units) and height (u_height_factor); its
  #|  // light differs from the plain one's.
  #|  const extrusionPattern = program(
  #|    patternPos + "in vec2 a_pos; in ivec4 a_normal; in vec4 a_heights; in float a_ele; uniform mat4 u_matrix;" +
  #|    "uniform float u_t; uniform float u_scale; uniform float u_ground; uniform vec3 u_lightpos;" +
  #|    "uniform float u_lightintensity; uniform vec3 u_lightcolor; uniform float u_vertical_gradient;" +
  #|    "uniform float u_opacity; uniform float u_height_factor; out vec4 v_light; out vec2 v_pos; out vec2 v_pat;" +
  #|    "void main() { float base = mix(a_heights.x, a_heights.y, u_t) * 0.1;" +
  #|    "  float height = mix(a_heights.z, a_heights.w, u_t) * 0.1; vec3 normal = vec3(a_normal.xyz);" +
  #|    "  float gradient_base = max(0.0, base), gradient_height = max(0.0, height);" +
  #|    "  float top = a_ele * u_ground, bottom = u_ground > 0.0 ? top - (base > 0.0 ? 0.0 : 10.0) : 0.0;" +
  #|    "  base = max(0.0, base) + bottom; height = max(0.0, height) + top;" +
  #|    "  float t = float(a_normal.x & 1); float elevation = t > 0.0 ? height : base; v_pos = a_pos;" +
  #|    "  gl_Position = u_matrix * vec4(a_pos, elevation * u_scale, 1.0);" +
  #|    "  bool roof = a_normal.x == 1 && a_normal.y == 0 && a_normal.z == 16384;" +
  #|    "  v_pat = patternPos(roof ? a_pos : vec2(float(a_normal.w) * 0.5, elevation * u_height_factor));" +
  #|    "  float directional = clamp(dot(normal / 16383.0, u_lightpos), 0.0, 1.0);" +
  #|    "  directional = mix(1.0 - u_lightintensity, max(0.5 + u_lightintensity, 1.0), directional);" +
  #|    "  if (normal.z == 0.0) directional *= (1.0 - u_vertical_gradient) + u_vertical_gradient *" +
  #|    "    clamp((t + gradient_base) * pow(gradient_height / 150.0, 0.5), mix(0.7, 0.98, 1.0 - u_lightintensity), 1.0);" +
  #|    "  v_light = vec4(clamp(directional * u_lightcolor, mix(vec3(0.0), vec3(0.3), 1.0 - u_lightcolor), vec3(1.0)), 1.0) * u_opacity; }",
  #|    clip + patternColor + "in vec4 v_light; in vec2 v_pat; out vec4 o;" +
  #|    "void main() { if (outside()) discard; o = patternColor(v_pat, vec4(0.0), 1.0) * v_light; }",
  #|    ["u_matrix", "u_clip", "u_t", "u_scale", "u_ground", "u_lightpos", "u_lightintensity", "u_lightcolor",
  #|     "u_vertical_gradient", "u_opacity", "u_height_factor", ...patternUniforms]);
  #|  // MapLibre's hillshade.fragment.glsl over the tile's quad: v_tex runs 0-1 across the
  #|  // slopes inside their border, u_lat is the tile's north and south latitude; u_method numbers
  #|  // standard 0, combined 1, igor 2, multidirectional 3, basic 4; u_count lights.
  #|  const hillshade = program(
  #|    "in vec2 a_pos; uniform mat4 u_matrix; out vec2 v_pos; out vec2 v_tex;" +
  #|    "void main() { v_pos = a_pos; v_tex = a_pos / 4096.0; gl_Position = u_matrix * vec4(a_pos, 0.0, 1.0); }",
  #|    clip + `uniform sampler2D u_image; uniform vec2 u_lat; uniform float u_exaggeration; uniform vec4 u_accent;
  #|    uniform int u_method; uniform int u_count; uniform float u_altitudes[8]; uniform float u_azimuths[8];
  #|    uniform vec4 u_shadows[8]; uniform vec4 u_highlights[8]; in vec2 v_tex; out vec4 o;
  #|    const float PI = 3.141592653589793;
  #|    float get_aspect(vec2 deriv) { return deriv.x != 0.0 ? atan(deriv.y, -deriv.x) : PI / 2.0 * (deriv.y > 0.0 ? 1.0 : -1.0); }
  #|    void igor(vec2 deriv) {
  #|      deriv = deriv * u_exaggeration * 2.0; float aspect = get_aspect(deriv); float azimuth = u_azimuths[0] + PI;
  #|      float slope_stength = atan(length(deriv)) * 2.0/PI;
  #|      float aspect_strength = 1.0 - abs(mod((aspect + azimuth) / PI + 0.5, 2.0) - 1.0);
  #|      o = u_shadows[0] * (slope_stength * aspect_strength) + u_highlights[0] * (slope_stength * (1.0-aspect_strength)); }
  #|    void standard(vec2 deriv) {
  #|      float azimuth = u_azimuths[0] + PI; float slope = atan(0.625 * length(deriv)); float aspect = get_aspect(deriv);
  #|      float intensity = u_exaggeration; float base = 1.875 - intensity * 1.75; float maxValue = 0.5 * PI;
  #|      float scaledSlope = intensity != 0.5 ? ((pow(base, slope) - 1.0) / (pow(base, maxValue) - 1.0)) * maxValue : slope;
  #|      float accent = cos(scaledSlope); vec4 accent_color = (1.0 - accent) * u_accent * clamp(intensity * 2.0, 0.0, 1.0);
  #|      float shade = abs(mod((aspect + azimuth) / PI + 0.5, 2.0) - 1.0);
  #|      vec4 shade_color = mix(u_shadows[0], u_highlights[0], shade) * sin(scaledSlope) * clamp(intensity * 2.0, 0.0, 1.0);
  #|      o = accent_color * (1.0 - shade_color.a) + shade_color; }
  #|    void basic(vec2 deriv) {
  #|      deriv = deriv * u_exaggeration * 2.0; float azimuth = u_azimuths[0] + PI;
  #|      float cos_az = cos(azimuth); float sin_az = sin(azimuth); float cos_alt = cos(u_altitudes[0]); float sin_alt = sin(u_altitudes[0]);
  #|      float cang = (sin_alt - (deriv.y*cos_az*cos_alt - deriv.x*sin_az*cos_alt)) / sqrt(1.0 + dot(deriv, deriv));
  #|      float shade = clamp(cang, 0.0, 1.0);
  #|      o = shade > 0.5 ? u_highlights[0]*(2.0*shade - 1.0) : u_shadows[0]*(1.0 - 2.0*shade); }
  #|    void multidirectional(vec2 deriv) {
  #|      deriv = deriv * u_exaggeration * 2.0; o = vec4(0,0,0,0);
  #|      for (int i = 0; i < 8; i++) {
  #|        if (i >= u_count) break;
  #|        float cos_alt = cos(u_altitudes[i]); float sin_alt = sin(u_altitudes[i]);
  #|        float cos_az = -cos(u_azimuths[i]); float sin_az = -sin(u_azimuths[i]);
  #|        float cang = (sin_alt - (deriv.y*cos_az*cos_alt - deriv.x*sin_az*cos_alt)) / sqrt(1.0 + dot(deriv, deriv));
  #|        float shade = clamp(cang, 0.0, 1.0);
  #|        if (shade > 0.5) o += u_highlights[i]*(2.0*shade - 1.0)/float(u_count);
  #|        else o += u_shadows[i]*(1.0 - 2.0*shade)/float(u_count); } }
  #|    void combined(vec2 deriv) {
  #|      deriv = deriv * u_exaggeration * 2.0; float azimuth = u_azimuths[0] + PI;
  #|      float cos_az = cos(azimuth); float sin_az = sin(azimuth); float cos_alt = cos(u_altitudes[0]); float sin_alt = sin(u_altitudes[0]);
  #|      float cang = acos((sin_alt - (deriv.y*cos_az*cos_alt - deriv.x*sin_az*cos_alt)) / sqrt(1.0 + dot(deriv, deriv)));
  #|      cang = clamp(cang, 0.0, PI/2.0);
  #|      float shade = cang* atan(length(deriv)) * 4.0/PI/PI; float highlight = (PI/2.0-cang)* atan(length(deriv)) * 4.0/PI/PI;
  #|      o = u_shadows[0]*shade + u_highlights[0]*highlight; }
  #|    void main() { if (outside()) discard;
  #|      highp vec2 size = vec2(textureSize(u_image, 0)); highp vec2 texturePos = (v_tex * (size - 2.0) + 1.0) / size;
  #|      float scaleFactor = cos(radians((u_lat.x - u_lat.y) * (1.0 - v_tex.y) + u_lat.y));
  #|      vec2 deriv = (texture(u_image, texturePos).rg - 128.0 / 255.0) * 8.0 / scaleFactor;
  #|      if (u_method == 4) basic(deriv); else if (u_method == 1) combined(deriv); else if (u_method == 2) igor(deriv);
  #|      else if (u_method == 3) multidirectional(deriv); else standard(deriv); }`,
  #|    ["u_matrix", "u_clip", "u_image", "u_lat", "u_exaggeration", "u_accent", "u_method", "u_count", "u_altitudes",
  #|     "u_azimuths", "u_shadows", "u_highlights"]);
  #|  // MapLibre's color_relief shaders: elevations packed in the DEM tile's RGB (u_unpack; the
  #|  // texture u_dimension wide with a border) colored between u_color_ramp_size stops.
  #|  const colorRelief = program(
  #|    "in vec2 a_pos; uniform mat4 u_matrix; uniform vec2 u_dimension; out vec2 v_pos; out vec2 v_tex;" +
  #|    "void main() { v_pos = a_pos; gl_Position = u_matrix * vec4(a_pos, 0.0, 1.0);" +
  #|    "  highp vec2 epsilon = 2.0 / u_dimension; float scale = (u_dimension.x - 4.0) / u_dimension.x;" +
  #|    "  v_tex = (a_pos / 4096.0) * scale + epsilon; }",
  #|    clip + `uniform sampler2D u_image; uniform vec4 u_unpack; uniform sampler2D u_elevation_stops;
  #|    uniform sampler2D u_color_stops; uniform int u_color_ramp_size; uniform float u_opacity; in vec2 v_tex; out vec4 o;
  #|    float getElevation(vec2 coord) { vec4 data = texture(u_image, coord) * 255.0; data.a = -1.0; return dot(data, u_unpack); }
  #|    float getElevationStop(int stop) {
  #|      vec4 data = texelFetch(u_elevation_stops, ivec2(stop, 0), 0) * 255.0; data.a = -1.0; return dot(data, u_unpack); }
  #|    void main() { if (outside()) discard;
  #|      float el = getElevation(v_tex); int r = (u_color_ramp_size - 1); int l = 0;
  #|      float el_l = getElevationStop(l); float el_r = getElevationStop(r);
  #|      while (r - l > 1) {
  #|        int m = (r + l) / 2; float el_m = getElevationStop(m);
  #|        if (el < el_m) { r = m; el_r = el_m; } else { l = m; el_l = el_m; } }
  #|      float x = (float(l) + (el - el_l) / (el_r - el_l) + 0.5)/float(u_color_ramp_size);
  #|      o = u_opacity*texture(u_color_stops, vec2(x, 0)); }`,
  #|    ["u_matrix", "u_clip", "u_dimension", "u_image", "u_unpack", "u_elevation_stops", "u_color_stops",
  #|     "u_color_ramp_size", "u_opacity"]);
  #|  // MapLibre's raster shaders without the parent cross-fade: the quad's corners
  #|  // (u_top: top left, right; u_bottom: bottom left, right) warped by u_warp, the
  #|  // premultiplied image unpremultiplied, hue spun, saturated, contrasted and
  #|  // mapped between the brightness bounds (u_bright).
  #|  const raster = program(
  #|    "in vec2 a_pos; uniform mat4 u_matrix; uniform vec4 u_top; uniform vec4 u_bottom; uniform vec3 u_warp;" +
  #|    "out vec2 v_pos; out vec3 v_tex;" +
  #|    "void main() { vec2 f = a_pos / 4096.0;" +
  #|    "  vec2 bilinear = mix(mix(u_top.xy, u_top.zw, f.x), mix(u_bottom.xy, u_bottom.zw, f.x), f.y);" +
  #|    "  float d = dot(u_warp.xy, f) + 1.0;" +
  #|    "  vec2 across = u_top.zw - u_top.xy + u_warp.x * u_top.zw, down = u_bottom.xy - u_top.xy + u_warp.y * u_bottom.xy;" +
  #|    "  v_pos = mix((across * f.x + down * f.y + u_top.xy) / d, bilinear, u_warp.z);" +
  #|    "  float r = mix(1.0 / d, 1.0, u_warp.z); v_tex = vec3(f * r, r);" +
  #|    "  gl_Position = u_matrix * vec4(v_pos, 0.0, 1.0); }",
  #|    clip + "uniform sampler2D u_image; uniform float u_opacity; uniform vec2 u_bright; uniform float u_saturation;" +
  #|    "uniform float u_contrast; uniform vec3 u_spin; in vec3 v_tex; out vec4 o;" +
  #|    "void main() { if (outside()) discard; vec4 color = texture(u_image, v_tex.xy / v_tex.z);" +
  #|    "  if (color.a > 0.0) color.rgb /= color.a; color.a *= u_opacity; vec3 rgb = color.rgb;" +
  #|    "  rgb = vec3(dot(rgb, u_spin.xyz), dot(rgb, u_spin.zxy), dot(rgb, u_spin.yzx));" +
  #|    "  float average = (color.r + color.g + color.b) / 3.0; rgb += (average - rgb) * u_saturation;" +
  #|    "  rgb = (rgb - 0.5) * u_contrast + 0.5;" +
  #|    "  o = vec4(mix(vec3(u_bright.x), vec3(u_bright.y), rgb) * color.a, color.a); }",
  #|    ["u_matrix", "u_clip", "u_image", "u_opacity", "u_bright", "u_saturation", "u_contrast", "u_spin",
  #|     "u_top", "u_bottom", "u_warp"]);
  #|  // One quad over a tile, for raster layers.
  #|  const quad = gl.createVertexArray();
  #|  gl.bindVertexArray(quad);
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  #|  gl.bufferData(gl.ARRAY_BUFFER, new Int16Array([0, 0, 4096, 0, 0, 4096, 4096, 4096]), gl.STATIC_DRAW);
  #|  gl.enableVertexAttribArray(0);
  #|  gl.vertexAttribPointer(0, 2, gl.SHORT, false, 4, 0);
  #|  gl.bindVertexArray(null);
  #|  // 16 x 16 quads over a tile, for warped pictures (MapLibre's subdivided quad).
  #|  const imageGrid = gl.createVertexArray(), gv = [], gi = [];
  #|  for (let y = 0; y <= 16; y++) for (let x = 0; x <= 16; x++) gv.push(x * 256, y * 256);
  #|  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
  #|    const a = y * 17 + x;
  #|    gi.push(a, a + 17, a + 1, a + 1, a + 17, a + 18);
  #|  }
  #|  gl.bindVertexArray(imageGrid);
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  #|  gl.bufferData(gl.ARRAY_BUFFER, new Int16Array(gv), gl.STATIC_DRAW);
  #|  gl.enableVertexAttribArray(0);
  #|  gl.vertexAttribPointer(0, 2, gl.SHORT, false, 4, 0);
  #|  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl.createBuffer());
  #|  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint16Array(gi), gl.STATIC_DRAW);
  #|  gl.bindVertexArray(null);
  #|  // Terrain: a grid raised by R32F elevations, bilinear by hand (float textures
  #|  // do not filter) over the u_dem part (offset, scale); a_data.x = 1 on skirts
  #|  // below the edges; u_image is the map drawn for the tile (rows bottom up).
  #|  const terrain = program(
  #|    "in vec2 a_pos; in vec4 a_data; uniform mat4 u_matrix; uniform sampler2D u_elev; uniform float u_scale;" +
  #|    "uniform float u_skirt; uniform vec3 u_dem; uniform vec2 u_fog; out vec2 v_uv; out float v_fog;" +
  #|    "float h(ivec2 p) { ivec2 n = textureSize(u_elev, 0) - 1; return texelFetch(u_elev, clamp(p, ivec2(0), n), 0).r; }" +
  #|    "void main() { v_uv = a_pos / 4096.0;" +
  #|    "  vec2 t = (u_dem.xy + v_uv * u_dem.z) * vec2(textureSize(u_elev, 0)) - 0.5;" +
  #|    "  ivec2 i = ivec2(floor(t)); vec2 f = t - floor(t);" +
  #|    "  float e = mix(mix(h(i), h(i + ivec2(1, 0)), f.x), mix(h(i + ivec2(0, 1)), h(i + ivec2(1, 1)), f.x), f.y);" +
  #|    "  gl_Position = u_matrix * vec4(a_pos, e * u_scale - a_data.x * u_skirt, 1.0);" +
  #|    "  float near = u_fog.x, far = u_fog.y;" +
  #|    "  v_fog = ((far + near) / (far - near) - 2.0 * far * near / ((far - near) * gl_Position.w)) * 0.5 + 0.5; }",
  #|    "uniform sampler2D u_image; uniform vec4 u_fog_color; uniform vec4 u_horizon_color;" +
  #|    "uniform vec3 u_fog_blend; in vec2 v_uv; in float v_fog; out vec4 o;" +
  #|    "vec4 lin(vec4 c) { return pow(c, vec4(2.2)); }" +
  #|    "void main() { vec4 c = texture(u_image, vec2(v_uv.x, 1.0 - v_uv.y));" +
  #|    "  if (u_fog_blend.y > 0.0 && v_fog > u_fog_blend.x) {" +
  #|    "    float h = smoothstep(0.0, 1.0, max((v_fog - u_fog_blend.z) / (1.0 - u_fog_blend.z), 0.0));" +
  #|    "    vec4 fog = mix(lin(u_fog_color), lin(u_horizon_color), h);" +
  #|    "    float k = max(v_fog - u_fog_blend.x, 0.0) / (1.0 - u_fog_blend.x);" +
  #|    "    c = pow(mix(lin(c), fog, k * k * u_fog_blend.y), vec4(1.0 / 2.2)); }" +
  #|    "  o = c; }",
  #|    ["u_matrix", "u_elev", "u_scale", "u_skirt", "u_dem", "u_image", "u_fog", "u_fog_color",
  #|     "u_horizon_color", "u_fog_blend"]);
  #|  // The sky: a screen quad (from gl_VertexID, no buffers) colored above the
  #|  // horizon line u_horizon (device pixels from the bottom), blending from
  #|  // the horizon's color over u_blend pixels (MapLibre's sky shader).
  #|  const sky = program(
  #|    "void main() { gl_Position = vec4(float(gl_VertexID & 1) * 2.0 - 1.0, float(gl_VertexID >> 1) * 2.0 - 1.0, 1.0, 1.0); }",
  #|    "uniform vec4 u_sky; uniform vec4 u_horizon_color; uniform float u_horizon; uniform float u_blend; out vec4 o;" +
  #|    "void main() { float b = gl_FragCoord.y - u_horizon; if (b <= 0.0) discard;" +
  #|    "  o = b < u_blend ? mix(u_sky, u_horizon_color, pow(1.0 - b / u_blend, 2.0)) : u_sky; }",
  #|    ["u_sky", "u_horizon_color", "u_horizon", "u_blend"]);
  #|  const empty = gl.createVertexArray();
  #|  // The grid: 65 x 65 vertices, then a skirt vertex under each edge vertex.
  #|  const N = 64, verts = [], data = [], idx = [];
  #|  for (let y = 0; y <= N; y++) for (let x = 0; x <= N; x++) { verts.push(x * 4096 / N, y * 4096 / N); data.push(0, 0, 0, 0); }
  #|  const edge = [];
  #|  for (let i = 0; i <= N; i++) edge.push(i, N * (N + 1) + i, i * (N + 1), i * (N + 1) + N);
  #|  const skirtOf = new Map();
  #|  for (const v of edge) if (!skirtOf.has(v)) { skirtOf.set(v, verts.length / 2); verts.push(verts[v * 2], verts[v * 2 + 1]); data.push(1, 0, 0, 0); }
  #|  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
  #|    const a = y * (N + 1) + x, b = a + 1, c = a + N + 1, d = c + 1;
  #|    idx.push(a, c, b, b, c, d);
  #|  }
  #|  const wall = (p, q) => { const sp = skirtOf.get(p), sq = skirtOf.get(q); idx.push(p, sp, q, q, sp, sq); };
  #|  for (let i = 0; i < N; i++) {
  #|    wall(i, i + 1); wall(N * (N + 1) + i, N * (N + 1) + i + 1);
  #|    wall(i * (N + 1), (i + 1) * (N + 1)); wall(i * (N + 1) + N, (i + 1) * (N + 1) + N);
  #|  }
  #|  const grid = gl.createVertexArray();
  #|  gl.bindVertexArray(grid);
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  #|  gl.bufferData(gl.ARRAY_BUFFER, new Int16Array(verts), gl.STATIC_DRAW);
  #|  gl.enableVertexAttribArray(0);
  #|  gl.vertexAttribPointer(0, 2, gl.SHORT, false, 4, 0);
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  #|  gl.bufferData(gl.ARRAY_BUFFER, new Int8Array(data), gl.STATIC_DRAW);
  #|  gl.enableVertexAttribArray(1);
  #|  gl.vertexAttribPointer(1, 4, gl.BYTE, false, 4, 0);
  #|  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl.createBuffer());
  #|  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint16Array(idx), gl.STATIC_DRAW);
  #|  gl.bindVertexArray(null);
  #|  // MapLibre's packDEMData of elevation v by unpack vector u into out at i (alpha 255); a
  #|  // channel whose factor is a whole multiple of the smallest is cut out by integer division.
  #|  const packDem = (v, u, out, i) => {
  #|    const f = [u[0], u[1], u[2]].filter((x) => x !== 0), min = Math.min(...f), s = Math.round((v + u[3]) / min);
  #|    for (let k = 0; k < 3; k++) {
  #|      const r = u[k] / min, n = Math.round(r);
  #|      out[i + k] = u[k] === 0 ? 0 : (Math.abs(r - n) < 1e-9 ? Math.floor(s / n) : Math.floor(s * min / u[k])) % 256;
  #|    }
  #|    out[i + 3] = 255;
  #|  };
  #|  // Reused for every draw, so WebGL does not convert an array each time.
  #|  return { gl, fill, fillOutline, fillPattern, fillOutlinePattern, backgroundPattern, line, lineDash, lineDashFeature, lineGradient, linePattern, circle, heatmap, heatmapTexture, symbol, icon, hillshade, colorRelief, raster, terrain, sky, empty, extrusion, extrusionPattern, quad, imageGrid, packDem, grid: { vao: grid, count: idx.length },
  #|    atlas: null, mat: new Float32Array(16), px: [0, 0], size: [1, 1] };
  #|}

///|
extern "js" fn is_null(gl : Gl) -> Bool =
  #|(x) => x == null

///|
extern "js" fn gl_viewport(gl : Gl, width : Int32, height : Int32) -> Unit =
  #|(c, w, h) => { c.gl.viewport(0, 0, w, h); c.px = [2 / w, 2 / h]; c.size = [w, h]; }

///|
extern "js" fn gl_clear(gl : Gl, r : Double, g : Double, b : Double) -> Unit =
  #|(c, r, g, b) => { c.gl.clearColor(r, g, b, 1); c.gl.clear(c.gl.COLOR_BUFFER_BIT | c.gl.DEPTH_BUFFER_BIT); }

///|
extern "js" fn gl_upload(
  gl : Gl,
  line : Bool,
  vertices : JsBuffer,
  indices : JsBuffer,
  count : Int32,
  index_bytes : Int32,
) -> Mesh =
  #|(c, line, vertices, indices, count, indexBytes) => {
  #|  const gl = c.gl;
  #|  const vao = gl.createVertexArray();
  #|  gl.bindVertexArray(vao);
  #|  const vbo = gl.createBuffer();
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
  #|  gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);
  #|  gl.enableVertexAttribArray(0);
  #|  gl.vertexAttribPointer(0, 2, gl.SHORT, false, line ? 8 : 4, 0);
  #|  if (line) {
  #|    gl.enableVertexAttribArray(1);
  #|    gl.vertexAttribPointer(1, 4, gl.BYTE, false, 8, 4);
  #|  }
  #|  const ibo = gl.createBuffer();
  #|  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo);
  #|  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);
  #|  gl.bindVertexArray(null);
  #|  const type = indexBytes === 2 ? gl.UNSIGNED_SHORT : gl.UNSIGNED_INT;
  #|  return { vao, vbo, ibo, count, type, bytes: vertices.byteLength + indices.byteLength };
  #|}

///|
extern "js" fn gl_release(gl : Gl, mesh : Mesh) -> Unit =
  #|(c, m) => {
  #|  if (m.elev) c.gl.deleteTexture(m.elev);
  #|  if (m.relief) c.gl.deleteTexture(m.relief);
  #|  if (m.texture) { c.gl.deleteTexture(m.texture); return; }
  #|  c.gl.deleteVertexArray(m.vao); c.gl.deleteBuffer(m.vbo); c.gl.deleteBuffer(m.ibo);
  #|  if (m.outline) c.gl.deleteBuffer(m.outline);
  #|  if (m.dist) c.gl.deleteBuffer(m.dist);
  #|  if (m.offsets) c.gl.deleteBuffer(m.offsets);
  #|  if (m.progress) c.gl.deleteBuffer(m.progress);
  #|  if (m.ele) c.gl.deleteBuffer(m.ele);
  #|  if (m.shift) c.gl.deleteBuffer(m.shift);
  #|  if (m.glyph) c.gl.deleteBuffer(m.glyph);
  #|  if (m.colored) c.gl.deleteBuffer(m.colored);
  #|}

///|
/// One draw's paint by slot (`@style.SLOT_*`): per slot, a constant (straight
/// RGBA or a number) or a layer's per-vertex values from where its zoom
/// position starts.
#external
pub type PaintSlots

///|
/// A layer's per-vertex paint on the GPU (docs/FORMATS.md, "Vertex paint").
#external
pub type PaintBuffer

///|
extern "js" fn paint_slots_new() -> PaintSlots = "() => []"

///|
extern "js" fn paint_slots_constant(
  slots : PaintSlots,
  slot : Int32,
  a : Double,
  b : Double,
  c : Double,
  d : Double,
) -> Unit = "(s, slot, a, b, c, d) => { s[slot] = { value: [a, b, c, d] }; }"

///|
extern "js" fn paint_slots_buffer(
  slots : PaintSlots,
  slot : Int32,
  buffer : PaintBuffer,
  offset : Int32,
  stride : Int32,
  t : Double,
  single : Bool,
) -> Unit =
  #|(s, slot, buffer, offset, stride, t, single) => { s[slot] = { buffer, offset, stride, t, single }; }

///|
extern "js" fn gl_upload_paint(gl : Gl, data : JsBuffer) -> PaintBuffer =
  #|(c, data) => {
  #|  const gl = c.gl, b = gl.createBuffer();
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, b);
  #|  gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
  #|  return b;
  #|}

///|
extern "js" fn gl_release_paint(gl : Gl, buffer : PaintBuffer) -> Unit =
  #|(c, b) => c.gl.deleteBuffer(b)

///|
/// Binds the first `count` `slots` to the bound vertex array and `program`: colors take
/// two attributes (start, next), numbers a vec2 (a `single` value: read once, t 0).
/// Every slot is set, as layers share vertex arrays.
extern "js" fn gl_bind_paint(
  gl : Gl,
  program : String,
  slots : PaintSlots,
  count : Int32,
) -> Unit =
  #|(c, name, slots, count) => {
  #|  const gl = c.gl, p = c[name], LOC = [[5, 6], [7], [8], [9, 10], [11], [12]], ts = new Float32Array(6);
  #|  for (let k = 0; k < count; k++) {
  #|    const s = slots[k], locs = LOC[k];
  #|    if (s.buffer) {
  #|      ts[k] = s.t;
  #|      gl.bindBuffer(gl.ARRAY_BUFFER, s.buffer);
  #|      locs.forEach((loc, h) => {
  #|        gl.enableVertexAttribArray(loc);
  #|        if (locs.length === 2) gl.vertexAttribPointer(loc, 4, gl.UNSIGNED_BYTE, true, s.stride, s.offset + (s.single ? 0 : h * 4));
  #|        else gl.vertexAttribPointer(loc, s.single ? 1 : 2, gl.FLOAT, false, s.stride, s.offset);
  #|      });
  #|    } else {
  #|      const v = s.value;
  #|      for (const loc of locs) {
  #|        gl.disableVertexAttribArray(loc);
  #|        if (locs.length === 2) gl.vertexAttrib4f(loc, v[0], v[1], v[2], v[3]);
  #|        else gl.vertexAttrib2f(loc, v[0], v[0]);
  #|      }
  #|    }
  #|  }
  #|  gl.uniform1fv(p.u_t, ts);
  #|}

///|
/// `clip` is (min x, min y, max x, max y) in tile units.
extern "js" fn gl_draw_fill(
  gl : Gl,
  program : String,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
) -> Unit =
  #|(c, name, m, matrix, clip) => {
  #|  const gl = c.gl, p = c[name];
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform4f(p.u_clip, clip[0], clip[1], clip[2], clip[3]);
  #|  gl.drawElements(gl.TRIANGLES, m.rangeCount ?? m.count, m.type, m.rangeOffset ?? 0);
  #|}

///|
extern "js" fn gl_upload_outline(
  gl : Gl,
  mesh : Mesh,
  indices : JsBuffer,
  count : Int32,
) -> Unit =
  #|(c, m, indices, count) => {
  #|  const gl = c.gl;
  #|  m.outline = gl.createBuffer();
  #|  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.outline);
  #|  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);
  #|  m.outlineCount = count;
  #|  m.bytes += indices.byteLength;
  #|}

///|
/// Draws `mesh`'s outline as lines (with the program and vertex array bound),
/// then gives the vertex array back its triangles.
extern "js" fn gl_draw_outline(
  gl : Gl,
  program : String,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
) -> Unit =
  #|(c, name, m, matrix, clip) => {
  #|  const gl = c.gl, p = c[name];
  #|  if (!m.outline) return;
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform4f(p.u_clip, clip[0], clip[1], clip[2], clip[3]);
  #|  gl.uniform2f(p.u_world, 2 / c.px[0], 2 / c.px[1]);
  #|  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.outline);
  #|  gl.drawElements(gl.LINES, m.outlineRange ?? m.outlineCount, m.type, m.outlineOffset ?? 0);
  #|  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.ibo);
  #|}

///|
extern "js" fn gl_draw_circle(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  depth : Double,
  dpr : Double,
  units : Double,
  look : FixedArray[Double],
) -> Unit =
  #|(c, m, matrix, clip, depth, dpr, units, look) => {
  #|  const gl = c.gl, p = c.circle;
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform4f(p.u_clip, clip[0], clip[1], clip[2], clip[3]);
  #|  gl.uniform2f(p.u_px, c.px[0], c.px[1]);
  #|  gl.uniform1f(p.u_depth, depth);
  #|  gl.uniform1f(p.u_dpr, dpr);
  #|  gl.uniform1f(p.u_units, units);
  #|  gl.uniform1i(p.u_scale, look[0]);
  #|  gl.uniform1i(p.u_pitch, look[1]);
  #|  gl.uniform1f(p.u_blur, look[2]);
  #|  gl.drawElements(gl.TRIANGLES, m.rangeCount ?? m.count, m.type, m.rangeOffset ?? 0);
  #|}

///|
/// Uses `program` and binds `mesh`'s vertex array with `slots`.
extern "js" fn gl_use(gl : Gl, program : String, mesh : Mesh) -> Unit =
  #|(c, name, m) => { c.gl.useProgram(c[name].program); c.gl.bindVertexArray(m.vao); }

///|
extern "js" fn mesh_bytes(mesh : Mesh) -> Int32 =
  #|(m) => m.bytes

///|
/// An offscreen draw target: a framebuffer with a color texture.
#external
pub type Target
