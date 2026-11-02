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
/// The WebGL2 context with its two programs; JS null if WebGL2 is unavailable.
extern "js" fn create_gl(canvas : Canvas) -> Gl =
  #|(canvas) => {
  #|  const gl = canvas.getContext("webgl2", { antialias: false, alpha: false, depth: true, stencil: false, premultipliedAlpha: true });
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
  #|    gl.bindAttribLocation(p, 3, "a_size");
  #|    gl.bindAttribLocation(p, 4, "a_ele");
  #|    gl.bindAttribLocation(p, 1, "a_normal");
  #|    gl.bindAttribLocation(p, 3, "a_heights");
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
  #|  const fill = program(
  #|    "in vec2 a_pos; uniform mat4 u_matrix; out vec2 v_pos;" +
  #|    "void main() { v_pos = a_pos; gl_Position = u_matrix * vec4(a_pos, 0.0, 1.0); }",
  #|    clip + "uniform vec4 u_color; out vec4 o; void main() { if (outside()) discard; o = u_color; }",
  #|    ["u_matrix", "u_clip", "u_color"]);
  #|  // Extrusion is in tile units (u_units device pixels at the center's depth
  #|  // u_depth), so lines thin with distance; the last pixel of the half width
  #|  // v_half, taken at the vertex's own depth, fades out (MapLibre's gamma scale).
  #|  const line = program(
  #|    "in vec2 a_pos; in vec4 a_data; uniform mat4 u_matrix; uniform float u_units; uniform float u_half;" +
  #|    "uniform float u_depth; out vec2 v_edge; out vec2 v_pos; out float v_half;" +
  #|    "void main() { v_pos = a_pos + a_data.xy / 63.0 * u_half * u_units;" +
  #|    "  gl_Position = u_matrix * vec4(v_pos, 0.0, 1.0); v_edge = a_data.zw;" +
  #|    "  v_half = u_half * u_depth / gl_Position.w; }",
  #|    // v_edge is (side, along): its length reaches 1 at the outline and
  #|    // around round caps.
  #|    clip + "uniform vec4 u_color; in vec2 v_edge; in float v_half; out vec4 o;" +
  #|    "void main() { if (outside()) discard; o = u_color * clamp((1.0 - length(v_edge)) * v_half, 0.0, 1.0); }",
  #|    ["u_matrix", "u_units", "u_half", "u_depth", "u_clip", "u_color"]);
  #|  gl.enable(gl.BLEND);
  #|  gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
  #|  // Circles face the viewer and shrink with distance (MapLibre's pitch-alignment
  #|  // "viewport", pitch-scale "map"): u_size device pixels at the center's depth;
  #|  // u_inner is the fill radius over u_size, the stroke lies outside it.
  #|  const circle = program(
  #|    "in vec2 a_pos; in vec4 a_data; uniform mat4 u_matrix; uniform vec2 u_px; uniform float u_size;" +
  #|    "uniform float u_depth; out vec2 v_extrude; out vec2 v_pos;" +
  #|    "void main() { v_pos = a_pos; v_extrude = a_data.xy / 63.0; vec4 c = u_matrix * vec4(a_pos, 0.0, 1.0);" +
  #|    "  gl_Position = c + vec4(v_extrude * u_size * u_px * u_depth, 0.0, 0.0); }",
  #|    clip + "uniform vec4 u_color; uniform vec4 u_stroke; uniform float u_size; uniform float u_inner;" +
  #|    "in vec2 v_extrude; out vec4 o;" +
  #|    "void main() { if (outside()) discard; float d = length(v_extrude); float aa = 1.0 / u_size;" +
  #|    "  float t = smoothstep(u_inner - aa, u_inner, d);" +
  #|    "  o = mix(u_color, u_stroke, t) * (1.0 - smoothstep(1.0 - aa, 1.0, d)); }",
  #|    ["u_matrix", "u_px", "u_size", "u_depth", "u_clip", "u_color", "u_stroke", "u_inner"]);
  #|  // a_data: corner offset in quarter CSS px (y down); a_size: text size in 1/16 px,
  #|  // both times MapLibre's perspective ratio; a_ele: anchor height (m). SDF edge at
  #|  // 0.75, falling 1/16 per glyph px (TinySDF radius 16 at 48 px); see FORMATS.md.
  #|  const symbol = program(
  #|    "in vec2 a_pos; in vec2 a_data; in vec2 a_tex; in float a_size; in float a_ele; uniform mat4 u_matrix;" +
  #|    "uniform vec2 u_px; uniform float u_dpr; uniform vec2 u_atlas; uniform float u_center; uniform float u_scale;" +
  #|    "uniform highp sampler2D u_depth; uniform bool u_occlude; out vec2 v_tex; out float v_scale; out float v_alpha;" +
  #|    "float visible(vec3 f) { float d = texture(u_depth, f.xy * 0.5 + 0.5).r * 2.0 - 1.0 + 0.0001 - f.z;" +
  #|    "  return 1.0 - clamp(-d * 500.0, 0.0, 1.0); }" +
  #|    "void main() { vec4 c = u_matrix * vec4(a_pos, a_ele * u_scale, 1.0); v_alpha = 1.0;" +
  #|    "  if (u_occlude) { vec3 f = c.xyz / c.w; v_alpha = visible(f);" +
  #|    "    if (v_alpha <= 0.95) v_alpha = (v_alpha + visible(f + vec3(0.0, 0.01, 0.0))) / 2.0; }" +
  #|    "  if (v_alpha < 0.1) { gl_Position = vec4(-2.0, -2.0, -2.0, 1.0); return; }" +
  #|    "  float r = clamp(0.5 + 0.5 * u_center / c.w, 0.0, 4.0);" +
  #|    "  vec2 off = a_data * 0.25 * r * u_dpr * u_px * vec2(1.0, -1.0);" +
  #|    "  gl_Position = vec4(c.xy + off * c.w, c.z, c.w); v_tex = a_tex / u_atlas; v_scale = a_size / 16.0 * r * u_dpr / 48.0; }",
  #|    "uniform sampler2D u_glyphs; uniform vec4 u_color; uniform float u_halo; in vec2 v_tex; in float v_scale;" +
  #|    "in float v_alpha; out vec4 o;" +
  #|    "void main() { float d = (0.75 - texture(u_glyphs, v_tex).r) * 16.0 * v_scale;" +
  #|    "  o = u_color * v_alpha * clamp(u_halo + 0.5 - d, 0.0, 1.0); }",
  #|    ["u_matrix", "u_px", "u_dpr", "u_atlas", "u_center", "u_scale", "u_depth", "u_occlude", "u_glyphs", "u_color",
  #|     "u_halo"]);
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
  #|  // MapLibre's hillshade.fragment.glsl, `standard` method, over the tile's
  #|  // quad: v_pos runs 0-1 across the slopes texture, u_lat is the tile's north
  #|  // and south latitude, u_light its azimuth (radians) and exaggeration.
  #|  const hillshade = program(
  #|    "in vec2 a_pos; uniform mat4 u_matrix; out vec2 v_pos; out vec2 v_tex;" +
  #|    "void main() { v_pos = a_pos; v_tex = a_pos / 4096.0; gl_Position = u_matrix * vec4(a_pos, 0.0, 1.0); }",
  #|    clip + "uniform sampler2D u_image; uniform vec2 u_lat; uniform vec2 u_light; uniform vec4 u_shadow;" +
  #|    "uniform vec4 u_highlight; uniform vec4 u_accent; in vec2 v_tex; out vec4 o; const float PI = 3.141592653589793;" +
  #|    "void main() { if (outside()) discard;" +
  #|    "  float scale = cos(radians((u_lat.x - u_lat.y) * (1.0 - v_tex.y) + u_lat.y));" +
  #|    "  vec2 deriv = (texture(u_image, v_tex).rg - 128.0 / 255.0) * 8.0 / scale;" +
  #|    "  float azimuth = u_light.x + PI; float slope = atan(0.625 * length(deriv));" +
  #|    "  float aspect = deriv.x != 0.0 ? atan(deriv.y, -deriv.x) : PI / 2.0 * (deriv.y > 0.0 ? 1.0 : -1.0);" +
  #|    "  float intensity = u_light.y; float base = 1.875 - intensity * 1.75; float maxValue = 0.5 * PI;" +
  #|    "  float scaled = intensity != 0.5 ? ((pow(base, slope) - 1.0) / (pow(base, maxValue) - 1.0)) * maxValue : slope;" +
  #|    "  float k = clamp(intensity * 2.0, 0.0, 1.0); vec4 accent = (1.0 - cos(scaled)) * u_accent * k;" +
  #|    "  float shade = abs(mod((aspect + azimuth) / PI + 0.5, 2.0) - 1.0);" +
  #|    "  vec4 color = mix(u_shadow, u_highlight, shade) * sin(scaled) * k;" +
  #|    "  o = accent * (1.0 - color.a) + color; }",
  #|    ["u_matrix", "u_clip", "u_image", "u_lat", "u_light", "u_shadow", "u_highlight", "u_accent"]);
  #|  // One quad over a tile, for raster layers.
  #|  const quad = gl.createVertexArray();
  #|  gl.bindVertexArray(quad);
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  #|  gl.bufferData(gl.ARRAY_BUFFER, new Int16Array([0, 0, 4096, 0, 0, 4096, 4096, 4096]), gl.STATIC_DRAW);
  #|  gl.enableVertexAttribArray(0);
  #|  gl.vertexAttribPointer(0, 2, gl.SHORT, false, 4, 0);
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
  #|  // Reused for every draw, so WebGL does not convert an array each time.
  #|  return { gl, fill, line, circle, symbol, hillshade, terrain, sky, empty, extrusion, quad, grid: { vao: grid, count: idx.length },
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
  #|  if (m.texture) { c.gl.deleteTexture(m.texture); return; }
  #|  c.gl.deleteVertexArray(m.vao); c.gl.deleteBuffer(m.vbo); c.gl.deleteBuffer(m.ibo);
  #|  if (m.ele) c.gl.deleteBuffer(m.ele);
  #|}

///|
/// `clip` is (min x, min y, max x, max y) in tile units.
extern "js" fn gl_draw_fill(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  r : Double,
  g : Double,
  b : Double,
  a : Double,
) -> Unit =
  #|(c, m, matrix, clip, r, g, b, a) => {
  #|  const gl = c.gl, p = c.fill;
  #|  gl.useProgram(p.program);
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform4f(p.u_clip, clip[0], clip[1], clip[2], clip[3]);
  #|  gl.uniform4f(p.u_color, r * a, g * a, b * a, a);
  #|  gl.bindVertexArray(m.vao);
  #|  gl.drawElements(gl.TRIANGLES, m.rangeCount ?? m.count, m.type, m.rangeOffset ?? 0);
  #|}

///|
extern "js" fn gl_draw_line(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  units : Double,
  depth : Double,
  r : Double,
  g : Double,
  b : Double,
  a : Double,
  half : Double,
) -> Unit =
  #|(c, m, matrix, clip, units, depth, r, g, b, a, half) => {
  #|  const gl = c.gl, p = c.line;
  #|  gl.useProgram(p.program);
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform4f(p.u_clip, clip[0], clip[1], clip[2], clip[3]);
  #|  gl.uniform1f(p.u_units, units);
  #|  gl.uniform1f(p.u_depth, depth);
  #|  gl.uniform1f(p.u_half, half);
  #|  gl.uniform4f(p.u_color, r * a, g * a, b * a, a);
  #|  gl.bindVertexArray(m.vao);
  #|  gl.drawElements(gl.TRIANGLES, m.rangeCount ?? m.count, m.type, m.rangeOffset ?? 0);
  #|}

///|
/// `color` and `stroke` are straight RGBA; sizes are in device pixels.
extern "js" fn gl_draw_circle(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  depth : Double,
  color : FixedArray[Double],
  stroke : FixedArray[Double],
  radius : Double,
  stroke_width : Double,
) -> Unit =
  #|(c, m, matrix, clip, depth, color, stroke, radius, strokeWidth) => {
  #|  const gl = c.gl, p = c.circle;
  #|  const size = radius + strokeWidth;
  #|  if (size <= 0) return;
  #|  // Without a stroke the edge fades to the fill color.
  #|  const s = strokeWidth > 0 ? stroke : color;
  #|  gl.useProgram(p.program);
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform4f(p.u_clip, clip[0], clip[1], clip[2], clip[3]);
  #|  gl.uniform2f(p.u_px, c.px[0], c.px[1]);
  #|  gl.uniform1f(p.u_size, size);
  #|  gl.uniform1f(p.u_depth, depth);
  #|  gl.uniform1f(p.u_inner, radius / size);
  #|  gl.uniform4f(p.u_color, color[0] * color[3], color[1] * color[3], color[2] * color[3], color[3]);
  #|  gl.uniform4f(p.u_stroke, s[0] * s[3], s[1] * s[3], s[2] * s[3], s[3]);
  #|  gl.bindVertexArray(m.vao);
  #|  gl.drawElements(gl.TRIANGLES, m.rangeCount ?? m.count, m.type, m.rangeOffset ?? 0);
  #|}

///|
extern "js" fn mesh_bytes(mesh : Mesh) -> Int32 =
  #|(m) => m.bytes

///|
/// Creates the glyph atlas texture (one byte per pixel) on first use.
extern "js" fn gl_glyph(
  gl : Gl,
  width : Int32,
  height : Int32,
  data : JsBuffer,
  x : Int32,
  y : Int32,
  w : Int32,
  h : Int32,
) -> Unit =
  #|(c, width, height, data, x, y, w, h) => {
  #|  const gl = c.gl;
  #|  if (!c.atlas) {
  #|    c.atlas = gl.createTexture();
  #|    gl.bindTexture(gl.TEXTURE_2D, c.atlas);
  #|    gl.texImage2D(gl.TEXTURE_2D, 0, gl.R8, width, height, 0, gl.RED, gl.UNSIGNED_BYTE, null);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  #|    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  #|    c.atlasSize = [width, height];
  #|  }
  #|  gl.bindTexture(gl.TEXTURE_2D, c.atlas);
  #|  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
  #|  gl.texSubImage2D(gl.TEXTURE_2D, 0, x, y, w, h, gl.RED, gl.UNSIGNED_BYTE, data);
  #|}

///|
/// Uploads glyph quads after turning each vertex's glyph index and corner into
/// atlas pixels from `rects` (x, y, width, height per glyph index). Nothing is
/// drawn until `gl_show`.
extern "js" fn gl_upload_symbols(
  gl : Gl,
  vertices : JsBuffer,
  indices : JsBuffer,
  index_bytes : Int32,
  rects : FixedArray[Int32],
) -> Mesh =
  #|(c, vertices, indices, indexBytes, rects) => {
  #|  const gl = c.gl;
  #|  const v = new DataView(vertices);
  #|  for (let o = 0; o < vertices.byteLength; o += 16) {
  #|    const g = v.getUint16(o + 8, true) * 4, corner = v.getUint16(o + 10, true);
  #|    v.setUint16(o + 8, rects[g] + (corner === 1 || corner === 2 ? rects[g + 2] : 0), true);
  #|    v.setUint16(o + 10, rects[g + 1] + (corner >= 2 ? rects[g + 3] : 0), true);
  #|  }
  #|  const vao = gl.createVertexArray();
  #|  gl.bindVertexArray(vao);
  #|  const vbo = gl.createBuffer();
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
  #|  gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);
  #|  gl.enableVertexAttribArray(0);
  #|  gl.vertexAttribPointer(0, 2, gl.SHORT, false, 16, 0);
  #|  gl.enableVertexAttribArray(1);
  #|  gl.vertexAttribPointer(1, 2, gl.SHORT, false, 16, 4);
  #|  gl.enableVertexAttribArray(2);
  #|  gl.vertexAttribPointer(2, 2, gl.UNSIGNED_SHORT, false, 16, 8);
  #|  gl.enableVertexAttribArray(3);
  #|  gl.vertexAttribPointer(3, 1, gl.UNSIGNED_SHORT, false, 16, 12);
  #|  // Each vertex's anchor elevation in meters, set by gl_set_heights.
  #|  const ele = gl.createBuffer();
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, ele);
  #|  gl.bufferData(gl.ARRAY_BUFFER, vertices.byteLength / 16 * 4, gl.DYNAMIC_DRAW);
  #|  gl.enableVertexAttribArray(4);
  #|  gl.vertexAttribPointer(4, 1, gl.FLOAT, false, 4, 0);
  #|  const ibo = gl.createBuffer();
  #|  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo);
  #|  gl.bindVertexArray(null);
  #|  const all = indexBytes === 2 ? new Uint16Array(indices) : new Uint32Array(indices);
  #|  const type = indexBytes === 2 ? gl.UNSIGNED_SHORT : gl.UNSIGNED_INT;
  #|  return { vao, vbo, ibo, ele, vertices: vertices.byteLength / 16, all, count: 0, type,
  #|    bytes: vertices.byteLength + indices.byteLength };
  #|}

///|
extern "js" fn gl_show(
  gl : Gl,
  mesh : Mesh,
  labels : JsBuffer,
  stride : Int32,
  shown : FixedArray[Bool],
) -> Unit =
  #|(c, m, labels, stride, shown) => {
  #|  const gl = c.gl;
  #|  let n = 0;
  #|  for (let i = 0; i < shown.length; i++) if (shown[i]) n += labels[(i + 1) * stride - 1];
  #|  const out = new m.all.constructor(n);
  #|  let at = 0;
  #|  for (let i = 0; i < shown.length; i++) {
  #|    if (!shown[i]) continue;
  #|    const first = labels[(i + 1) * stride - 2], count = labels[(i + 1) * stride - 1];
  #|    out.set(m.all.subarray(first, first + count), at);
  #|    at += count;
  #|  }
  #|  gl.bindVertexArray(null);
  #|  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.ibo);
  #|  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, out, gl.DYNAMIC_DRAW);
  #|  m.count = n;
  #|}

///|
/// `color` and `halo` are straight RGBA; `halo_width` is in device pixels;
/// `center` is the screen center's clip w; `scale` turns the anchors'
/// elevations (meters) into world pixels.
extern "js" fn gl_draw_symbols(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  dpr : Double,
  color : FixedArray[Double],
  halo : FixedArray[Double],
  halo_width : Double,
  center : Double,
  scale : Double,
) -> Unit =
  #|(c, m, matrix, dpr, color, halo, haloWidth, center, scale) => {
  #|  if (m.count === 0 || !c.atlas) return;
  #|  const gl = c.gl, p = c.symbol;
  #|  gl.useProgram(p.program);
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform2f(p.u_px, c.px[0], c.px[1]);
  #|  gl.uniform1f(p.u_dpr, dpr);
  #|  gl.uniform1f(p.u_center, center);
  #|  gl.uniform1f(p.u_scale, scale);
  #|  const occlude = !!c.depth?.ready;
  #|  gl.uniform1i(p.u_occlude, occlude ? 1 : 0);
  #|  gl.activeTexture(gl.TEXTURE2);
  #|  gl.bindTexture(gl.TEXTURE_2D, occlude ? c.depth.texture : null);
  #|  gl.uniform1i(p.u_depth, 2);
  #|  gl.uniform2f(p.u_atlas, c.atlasSize[0], c.atlasSize[1]);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, c.atlas);
  #|  gl.uniform1i(p.u_glyphs, 0);
  #|  gl.bindVertexArray(m.vao);
  #|  // The halo goes under the whole layer's text of this tile, then the text.
  #|  if (haloWidth > 0 && halo[3] > 0) {
  #|    gl.uniform4f(p.u_color, halo[0] * halo[3], halo[1] * halo[3], halo[2] * halo[3], halo[3]);
  #|    gl.uniform1f(p.u_halo, haloWidth);
  #|    gl.drawElements(gl.TRIANGLES, m.count, m.type, 0);
  #|  }
  #|  gl.uniform4f(p.u_color, color[0] * color[3], color[1] * color[3], color[2] * color[3], color[3]);
  #|  gl.uniform1f(p.u_halo, 0);
  #|  gl.drawElements(gl.TRIANGLES, m.rangeCount ?? m.count, m.type, m.rangeOffset ?? 0);
  #|}

///|
/// A tile's slopes as a two-channel byte texture, filtered linearly.
extern "js" fn gl_upload_slopes(
  gl : Gl,
  slopes : JsBuffer,
  size : Int32,
) -> Mesh =
  #|(c, slopes, size) => {
  #|  const gl = c.gl;
  #|  const texture = gl.createTexture();
  #|  gl.bindTexture(gl.TEXTURE_2D, texture);
  #|  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
  #|  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RG8, size, size, 0, gl.RG, gl.UNSIGNED_BYTE, new Uint8Array(slopes));
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  #|  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  #|  return { texture, size, bytes: size * size * 2 };
  #|}

///|
extern "js" fn gl_slopes_side(
  gl : Gl,
  mesh : Mesh,
  side : Int32,
  slopes : Bytes,
) -> Unit =
  #|(c, m, side, slopes) => {
  #|  const gl = c.gl, n = m.size;
  #|  gl.bindTexture(gl.TEXTURE_2D, m.texture);
  #|  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
  #|  const [x, y, w, h] = [[0, 0, n, 1], [0, n - 1, n, 1], [0, 0, 1, n], [n - 1, 0, 1, n]][side];
  #|  gl.texSubImage2D(gl.TEXTURE_2D, 0, x, y, w, h, gl.RG, gl.UNSIGNED_BYTE, slopes);
  #|}

///|
/// `lat_light` is the tile's north and south latitude, then the light's azimuth
/// and exaggeration; colors are straight RGBA.
extern "js" fn gl_draw_hillshade(
  gl : Gl,
  mesh : Mesh,
  matrix : FixedArray[Double],
  clip : FixedArray[Double],
  lat_light : FixedArray[Double],
  shadow : FixedArray[Double],
  highlight : FixedArray[Double],
  accent : FixedArray[Double],
) -> Unit =
  #|(c, m, matrix, clip, ll, shadow, highlight, accent) => {
  #|  const gl = c.gl, p = c.hillshade;
  #|  const pre = (loc, v) => gl.uniform4f(loc, v[0] * v[3], v[1] * v[3], v[2] * v[3], v[3]);
  #|  gl.useProgram(p.program);
  #|  c.mat.set(matrix);
  #|  gl.uniformMatrix4fv(p.u_matrix, false, c.mat);
  #|  gl.uniform4f(p.u_clip, clip[0], clip[1], clip[2], clip[3]);
  #|  gl.uniform2f(p.u_lat, ll[0], ll[1]);
  #|  gl.uniform2f(p.u_light, ll[2], ll[3]);
  #|  pre(p.u_shadow, shadow);
  #|  pre(p.u_highlight, highlight);
  #|  pre(p.u_accent, accent);
  #|  gl.activeTexture(gl.TEXTURE0);
  #|  gl.bindTexture(gl.TEXTURE_2D, m.texture);
  #|  gl.uniform1i(p.u_image, 0);
  #|  gl.bindVertexArray(c.quad);
  #|  gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  #|}

///|
/// An offscreen draw target: a framebuffer with a color texture.
#external
pub type Target

///|
/// Sets the anchor elevation (meters) of every vertex of each label: `heights`
/// has one per label, whose indices are at `labels` (as for `gl_show`).
extern "js" fn gl_set_heights(
  gl : Gl,
  mesh : Mesh,
  labels : JsBuffer,
  stride : Int32,
  heights : FixedArray[Double],
) -> Unit =
  #|(c, m, labels, stride, heights) => {
  #|  const gl = c.gl, out = new Float32Array(m.vertices);
  #|  for (let i = 0; i < heights.length; i++) {
  #|    const first = labels[(i + 1) * stride - 2], count = labels[(i + 1) * stride - 1];
  #|    for (let k = first; k < first + count; k++) out[m.all[k]] = heights[i];
  #|  }
  #|  gl.bindBuffer(gl.ARRAY_BUFFER, m.ele);
  #|  gl.bufferData(gl.ARRAY_BUFFER, out, gl.DYNAMIC_DRAW);
  #|}
