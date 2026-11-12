// Drawing glTF models for mbmap/3d's layers in WebGL2: a model's primitives uploaded once, then drawn
// with its meters taken to clip space by a Web Mercator matrix and, on the globe, a unit-sphere one.
import { MAX_CLIP_PLANES, MAX_CLIP_POINTS, MAX_CLIP_RINGS, mercatorMeters, packClipping, type Clipping } from "../clipping";
import type { CustomRenderMethodInput } from "../custom";
import type { Material, Primitive } from "./gltf";
import { LIGHT, mul, normalMatrix } from "./place";

/** A model ready for drawing: its primitives, materials and decoded images. */
export interface DrawableModel {
  primitives: Primitive[];
  materials: Material[];
  images: ImageBitmap[];
}

/** Texels per edge of the shadow map (`@core.SHADOW_MAP_SIZE`). */
const SHADOW_SIZE = 2048;

const VERTEX = `#version 300 es
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv0;
layout(location = 3) in vec2 a_uv1;
layout(location = 4) in vec4 a_color;
layout(location = 5) in float a_feature;
layout(location = 6) in vec4 a_region;
uniform mat4 u_model;
uniform mat4 u_flat;
uniform mat4 u_globe;
uniform float u_t;
uniform mat3 u_normal;
uniform mat3 u_uv;
uniform int u_uv_set;
uniform float u_point;
uniform mat4 u_shadow;
uniform mat4 u_cut_frame;
out vec4 v_shadow;
out vec4 v_cut;
out vec3 v_enu;
out vec3 v_normal;
out vec2 v_uv;
out vec4 v_color;
out vec4 v_region;
flat out float v_feature;
void main() {
  v_region = a_region;
  vec4 p = u_model * vec4(a_pos, 1.0);
  v_feature = a_feature;
  v_enu = p.xyz;
  v_normal = u_normal * a_normal;
  v_uv = (u_uv * vec3(u_uv_set == 1 ? a_uv1 : a_uv0, 1.0)).xy;
  v_color = a_color;
  vec4 f = u_flat * p;
  v_shadow = u_shadow * p;
  gl_PointSize = u_point;
  gl_Position = u_t > 0.999 ? u_globe * p : u_t > 0.0 ? mix(f, u_globe * p, u_t) : f;
  v_cut = vec4((u_cut_frame * p).xyz, gl_Position.w);
}`;

const FRAGMENT = `#version 300 es
precision highp float;
in vec3 v_enu;
in vec3 v_normal;
in vec2 v_uv;
in vec4 v_color;
in vec4 v_region;
flat in float v_feature;
uniform vec4 u_color;
uniform bool u_atlas;
uniform sampler2D u_image;
uniform bool u_textured;
uniform int u_shading;
uniform float u_cutoff;
uniform float u_opacity;
uniform vec3 u_light;
uniform bool u_lights;
uniform vec3 u_ambient;
uniform vec3 u_sun;
uniform vec2 u_pick;
uniform bool u_picking;
uniform float u_point;
uniform highp sampler2DShadow u_shadow_map;
uniform vec3 u_shadow_k;
in vec4 v_shadow;
in vec4 v_cut;
out vec4 o;
// The map's clipping, as its extrusions are cut (render_webgl2's cutFs): v_cut is east, north, up meters at its origin.
uniform int u_cut_count;
uniform bool u_cut_union;
uniform vec4 u_cut_planes[${MAX_CLIP_PLANES}];
uniform vec4 u_cut_edge;
uniform float u_cut_mpp;
uniform int u_cut_rings[${MAX_CLIP_RINGS}];
uniform int u_cut_ring_count;
uniform vec4 u_cut_poly[${MAX_CLIP_POINTS / 2}];
uniform bool u_cut_inverse;
vec2 cutVertex(int i) { vec4 v = u_cut_poly[i / 2]; return i % 2 == 0 ? v.xy : v.zw; }
bool inRings(vec2 p) {
  int start = 0;
  for (int r = 0; r < ${MAX_CLIP_RINGS}; r++) {
    if (r >= u_cut_ring_count) break;
    int n = u_cut_rings[r];
    bool inside = false;
    for (int i = 0; i < ${MAX_CLIP_POINTS}; i++) {
      if (i >= n) break;
      vec2 a = cutVertex(start + i), b = cutVertex(start + (i + 1) % n);
      if ((a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) inside = !inside;
    }
    if (inside) return true;
    start += n;
  }
  return false;
}
// Discards what is cut; the edge's color where the planes' band is, else alpha 0.
vec4 cut() {
  if (u_cut_ring_count > 0 && inRings(v_cut.xy) != u_cut_inverse) discard;
  if (u_cut_count == 0) return vec4(0.0);
  float amount = u_cut_union ? 1e30 : -1e30;
  for (int i = 0; i < ${MAX_CLIP_PLANES}; i++) {
    if (i >= u_cut_count) break;
    float d = (dot(u_cut_planes[i].xyz, v_cut.xyz) + u_cut_planes[i].w) / (v_cut.w * u_cut_mpp);
    amount = u_cut_union ? min(amount, d) : max(amount, d);
  }
  if (amount <= 0.0) discard;
  return amount < u_cut_edge.w ? vec4(u_cut_edge.rgb, 1.0) : vec4(0.0);
}
// As the map's extrusions (u_shadow_k: intensity or tint, depth per texel, mode): the share the light reaches.
float seen() {
  vec3 p = v_shadow.xyz / v_shadow.w * 0.5 + 0.5;
  if (u_shadow_k.z < 0.5 || v_shadow.w <= 0.0 || any(lessThan(p, vec3(0.0))) || any(greaterThan(p, vec3(1.0)))) return -1.0;
  float t = 0.5 / ${SHADOW_SIZE}.0, d = p.z - 2.0 * u_shadow_k.y;
  return (texture(u_shadow_map, vec3(p.xy + vec2(-t, -t), d)) + texture(u_shadow_map, vec3(p.xy + vec2(t, -t), d)) +
    texture(u_shadow_map, vec3(p.xy + vec2(-t, t), d)) + texture(u_shadow_map, vec3(p.xy + vec2(t, t), d))) / 4.0;
}
float sunlit() { float s = seen(); return u_shadow_k.z > 2.5 || s < 0.0 ? 1.0 : 1.0 - u_shadow_k.x * (1.0 - s); }
void main() {
  if (u_point > 0.0 && length(gl_PointCoord - 0.5) > 0.5) discard;
  vec4 edge = cut();
  if (u_picking) {
    float f = clamp(floor(v_feature + 0.5), 0.0, 65535.0);
    o = vec4(u_pick, floor(f / 256.0) / 255.0, mod(f, 256.0) / 255.0);
    return;
  }
  vec4 c = u_color * v_color;
  // An I3S atlas: the texture's part for this vertex is its uvRegion, which the uvs repeat in.
  if (u_textured) c *= texture(u_image, u_atlas ? v_region.xy + fract(v_uv) * (v_region.zw - v_region.xy) : v_uv);
  if (u_cutoff >= 0.0) { if (c.a < u_cutoff) discard; c.a = 1.0; }
  float d = u_shading == 1 ? max(dot(normalize(v_normal), u_light), 0.0) : abs(dot(normalize(cross(dFdx(v_enu), dFdy(v_enu))), u_light));
  // The style's lights (ambient plus a directional one), else a fixed light from Mapbox's default direction.
  vec3 lit = u_shading == 0 ? vec3(1.0) : u_lights ? u_ambient + u_sun * d * sunlit() : vec3(0.55 + 0.45 * d);
  float a = c.a * u_opacity;
  o = vec4(c.rgb * lit * a, a);
  float s = u_shadow_k.z > 2.5 ? seen() : -1.0;
  if (s >= 0.0) o.rgb = mix(o.rgb, (s > 0.5 ? vec3(0.2, 0.8, 0.3) : vec3(0.9, 0.2, 0.15)) * a, u_shadow_k.x);
  if (edge.a > 0.0) o = edge;
}`;

const UNIFORMS = ["u_model", "u_flat", "u_globe", "u_t", "u_normal", "u_uv", "u_uv_set", "u_color", "u_image", "u_textured", "u_shading", "u_cutoff", "u_opacity", "u_light", "u_pick", "u_picking", "u_point", "u_atlas", "u_lights", "u_ambient", "u_sun", "u_shadow", "u_shadow_map", "u_shadow_k", "u_cut_frame", "u_cut_count", "u_cut_union", "u_cut_planes", "u_cut_edge", "u_cut_mpp", "u_cut_rings", "u_cut_ring_count", "u_cut_poly", "u_cut_inverse"] as const;
type Uniforms = Record<(typeof UNIFORMS)[number], WebGLUniformLocation | null>;

/** A primitive on the GPU: its vertex array, how to draw it, and what it is drawn with. */
export interface Mesh {
  vao: WebGLVertexArrayObject;
  buffers: WebGLBuffer[];
  mode: number;
  count: number;
  indexType: number;
  matrix: Float64Array;
  material?: Material;
  shading: number;
  atlas: boolean;
}

/** Where each attribute goes; a feature's id (`_BATCHID` in b3dm, EXT_mesh_features' `_FEATURE_ID_0`) at 5, for picking; an I3S atlas region at 6. */
const ATTRIBUTE_LOCATIONS: Record<string, number> = { POSITION: 0, NORMAL: 1, TEXCOORD_0: 2, TEXCOORD_1: 3, COLOR_0: 4, _BATCHID: 5, _FEATURE_ID_0: 5, _UV_REGION: 6 };
const DEFAULTS: Record<number, number[]> = { 1: [0, 0, 1, 0], 2: [0, 0, 0, 0], 3: [0, 0, 0, 0], 4: [1, 1, 1, 1], 5: [0, 0, 0, 0], 6: [0, 0, 1, 1] };
const POINTS = 0;
const IDENTITY3 = new Float32Array([1, 0, 0, 0, 1, 0, 0, 0, 1]);

/** A model on the GPU: its meshes and textures. */
export interface GpuModel {
  meshes: Mesh[];
  textures: WebGLTexture[];
}

/** Uploads `model`; `axis` (meters, column-major) goes before each primitive's node matrix. */
export function uploadModel(gl: WebGL2RenderingContext, model: DrawableModel, axis: ArrayLike<number>): GpuModel {
  const textures = model.images.map((image) => {
    const t = gl.createTexture()!;
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
    gl.generateMipmap(gl.TEXTURE_2D);
    return t;
  });
  gl.bindTexture(gl.TEXTURE_2D, null);
  const meshes: Mesh[] = [];
  for (const p of model.primitives) {
    const vao = gl.createVertexArray()!;
    gl.bindVertexArray(vao);
    const buffers: WebGLBuffer[] = [];
    for (const [name, a] of Object.entries(p.attributes)) {
      const at = ATTRIBUTE_LOCATIONS[name];
      if (at === undefined) continue;
      const b = gl.createBuffer()!;
      gl.bindBuffer(gl.ARRAY_BUFFER, b);
      gl.bufferData(gl.ARRAY_BUFFER, a.data, gl.STATIC_DRAW);
      gl.enableVertexAttribArray(at);
      gl.vertexAttribPointer(at, a.size, a.type, a.normalized, 0, 0);
      buffers.push(b);
    }
    for (const [name, at] of Object.entries(ATTRIBUTE_LOCATIONS)) {
      const v = DEFAULTS[at];
      if (!v || Object.keys(p.attributes).some((n) => ATTRIBUTE_LOCATIONS[n] === at) || (at === 5 && name !== "_BATCHID")) continue;
      gl.disableVertexAttribArray(at);
      gl.vertexAttrib4f(at, v[0], v[1], v[2], v[3]);
    }
    let count = p.attributes.POSITION.data.length / p.attributes.POSITION.size;
    let indexType = 0;
    if (p.indices) {
      const b = gl.createBuffer()!;
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, b);
      gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, p.indices, gl.STATIC_DRAW);
      buffers.push(b);
      count = p.indices.length;
      indexType = p.indices instanceof Uint8Array ? gl.UNSIGNED_BYTE : p.indices instanceof Uint16Array ? gl.UNSIGNED_SHORT : gl.UNSIGNED_INT;
    }
    gl.bindVertexArray(null);
    const material = model.materials[p.material];
    const matrix = mul(axis, p.matrix);
    // Points without normals have no surface to light.
    const shading = material?.unlit ? 0 : p.attributes.NORMAL ? 1 : p.mode === POINTS ? 0 : 2;
    meshes.push({ vao, buffers, mode: p.mode, count, indexType, matrix, material, shading, atlas: Boolean(p.attributes._UV_REGION) });
  }
  return { meshes, textures };
}

/** Frees what `uploadModel` made. */
export function releaseModel(gl: WebGL2RenderingContext, model: GpuModel): void {
  for (const m of model.meshes) {
    gl.deleteVertexArray(m.vao);
    for (const b of m.buffers) gl.deleteBuffer(b);
  }
  for (const t of model.textures) gl.deleteTexture(t);
}

/** The program models are drawn with. */
export class ModelProgram {
  #program: WebGLProgram;
  #u: Uniforms;
  #pointSize = 2;
  #input: CustomRenderMethodInput | null = null;
  #casting = false;
  #cutFrame: Float64Array | null = null;

  constructor(gl: WebGL2RenderingContext) {
    const shader = (type: number, source: string) => {
      const s = gl.createShader(type)!;
      gl.shaderSource(s, source);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(`mbmap: 3d: ${gl.getShaderInfoLog(s)}`);
      return s;
    };
    const p = gl.createProgram()!;
    const shaders = [shader(gl.VERTEX_SHADER, VERTEX), shader(gl.FRAGMENT_SHADER, FRAGMENT)];
    for (const s of shaders) gl.attachShader(p, s);
    gl.linkProgram(p);
    for (const s of shaders) gl.deleteShader(s);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(`mbmap: 3d: ${gl.getProgramInfoLog(p)}`);
    this.#program = p;
    this.#u = Object.fromEntries(UNIFORMS.map((u) => [u, gl.getUniformLocation(p, u)])) as Uniforms;
    gl.useProgram(p);
    gl.uniform1i(this.#u.u_shadow_map, 7);
  }

  /** While picking, what the next draws write besides their feature id: `id` (0 to 65535) in two bytes. */
  setPickId(gl: WebGL2RenderingContext, id: number): void {
    gl.uniform2f(this.#u.u_pick, Math.floor(id / 256) / 255, (id % 256) / 255);
  }

  /** The diameter points are drawn with from the next draw on, in device pixels. */
  setPointSize(size: number): void {
    this.#pointSize = Math.max(1, size);
  }

  delete(gl: WebGL2RenderingContext): void {
    gl.deleteProgram(this.#program);
  }

  /**
   * Starts drawing with `input`'s matrices and lights: colors, or `picking` ids, or `casting` into the shadow
   * map (the matrices then the light's; no blended meshes, no points), cut by `clip` (the map's clipping and the
   * meters a pixel spans per unit of clip w).
   */
  begin(gl: WebGL2RenderingContext, input: CustomRenderMethodInput, picking = false, casting = false, clip?: { cut: Clipping; mpp: number }): void {
    const u = this.#u;
    const lights = input.lights;
    const shadow = !picking && !casting ? input.shadow : undefined;
    this.#input = input;
    this.#casting = casting;
    gl.useProgram(this.#program);
    gl.uniform1f(u.u_t, input.defaultProjectionData.projectionTransition);
    gl.uniform1i(u.u_picking, picking ? 1 : 0);
    gl.uniform3f(u.u_shadow_k, shadow?.intensity ?? 0, shadow?.texel ?? 0, shadow?.mode ?? 0);
    this.#clip(gl, clip);
    gl.uniform3fv(u.u_light, lights ? Array.from(lights.direction) : LIGHT);
    gl.uniform1i(u.u_lights, lights ? 1 : 0);
    if (lights) {
      gl.uniform3fv(u.u_ambient, Array.from(lights.ambient));
      gl.uniform3fv(u.u_sun, Array.from(lights.directional));
    }
    gl.uniform1i(u.u_image, 0);
    gl.activeTexture(gl.TEXTURE0);
  }

  /** Sets the clipping's uniforms from `packClipping`'s numbers, and the frame from Mercator to the origin's meters. */
  #clip(gl: WebGL2RenderingContext, clip?: { cut: Clipping; mpp: number }): void {
    const u = this.#u;
    const n = clip ? packClipping(clip.cut) : [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    const planes = n[9];
    const rings = n[10 + 4 * planes];
    gl.uniform1i(u.u_cut_count, planes);
    gl.uniform1i(u.u_cut_ring_count, rings);
    this.#cutFrame = null;
    if (!clip || (!planes && !rings)) return;
    const [lng, lat, h] = n;
    const m = mercatorMeters(lat);
    const [x, y] = [(lng + 180) / 360, 0.5 - Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360)) / (2 * Math.PI)];
    this.#cutFrame = new Float64Array([m, 0, 0, 0, 0, -m, 0, 0, 0, 0, m, 0, -x * m, y * m, -h, 1]);
    const pad = (a: number[], k: number) => new Float32Array(k).fill(0).map((_, i) => a[i] ?? 0);
    gl.uniform1i(u.u_cut_union, n[3]);
    gl.uniform1i(u.u_cut_inverse, n[4]);
    gl.uniform4f(u.u_cut_edge, n[6], n[7], n[8], n[5]);
    gl.uniform1f(u.u_cut_mpp, clip.mpp);
    gl.uniform4fv(u.u_cut_planes, pad(n.slice(10, 10 + 4 * planes), 4 * MAX_CLIP_PLANES));
    gl.uniform1iv(u.u_cut_rings, new Int32Array(pad(n.slice(11 + 4 * planes, 11 + 4 * planes + rings), MAX_CLIP_RINGS)));
    gl.uniform4fv(u.u_cut_poly, pad(n.slice(11 + 4 * planes + rings), 2 * MAX_CLIP_POINTS));
  }

  /**
   * Draws `model`'s meshes of `pass` (0: opaque, 1: blended, or all with `translucent`): `place` (meters to meters)
   * before each mesh's matrix, then `mercator` and `sphere` (`mercatorFrame`, `sphereFrame`) to Mercator and the
   * unit sphere; `feature` is the id meshes without an id attribute are picked with.
   */
  draw(gl: WebGL2RenderingContext, model: GpuModel, place: ArrayLike<number>, mercator: Float64Array, sphere: Float64Array, opacity: number, translucent: boolean, pass: number, feature?: number): void {
    const u = this.#u;
    const input = this.#input!;
    const d = input.defaultProjectionData;
    const t = d.projectionTransition;
    const s = input.shadow;
    // An instance's feature id, for meshes with no id attribute of their own.
    gl.vertexAttrib4f(5, feature ?? 0, 0, 0, 0);
    gl.uniformMatrix4fv(u.u_flat, false, new Float32Array(mul(t > 0 ? d.fallbackMatrix : d.mainMatrix, mercator)));
    if (t > 0) gl.uniformMatrix4fv(u.u_globe, false, new Float32Array(mul(input.modelViewProjectionMatrix, sphere)));
    if (s) gl.uniformMatrix4fv(u.u_shadow, false, new Float32Array(s.mode === 2 ? mul(s.sphere, sphere) : mul(s.mercator, mercator)));
    if (this.#cutFrame) gl.uniformMatrix4fv(u.u_cut_frame, false, new Float32Array(mul(this.#cutFrame, mercator)));
    gl.uniform1f(u.u_opacity, opacity);
    for (const m of model.meshes) {
      const blend = translucent || m.material?.alphaMode === "BLEND";
      if (blend !== (pass === 1) || (this.#casting && m.mode === POINTS)) continue;
      this.#mesh(gl, model, m, mul(place, m.matrix));
    }
  }

  #mesh(gl: WebGL2RenderingContext, model: GpuModel, m: Mesh, matrix: Float64Array): void {
    const u = this.#u;
    const mat = m.material;
    gl.uniformMatrix4fv(u.u_model, false, new Float32Array(matrix));
    gl.uniformMatrix3fv(u.u_normal, false, normalMatrix(matrix));
    gl.uniform4fv(u.u_color, mat?.color ?? [1, 1, 1, 1]);
    gl.uniform1i(u.u_shading, m.shading);
    gl.uniform1f(u.u_point, m.mode === POINTS ? this.#pointSize : 0);
    gl.uniform1i(u.u_atlas, m.atlas ? 1 : 0);
    gl.uniform1f(u.u_cutoff, mat?.alphaMode === "MASK" ? mat.alphaCutoff : -1);
    const tex = mat?.texture;
    const texture = tex ? model.textures[tex.image] : undefined;
    gl.uniform1i(u.u_textured, texture ? 1 : 0);
    if (tex && texture) {
      gl.bindTexture(gl.TEXTURE_2D, texture);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, tex.wrapS);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, tex.wrapT);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, tex.minFilter);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, tex.magFilter);
      gl.uniformMatrix3fv(u.u_uv, false, tex.matrix ? new Float32Array(tex.matrix) : IDENTITY3);
      gl.uniform1i(u.u_uv_set, tex.texCoord);
    } else {
      gl.uniformMatrix3fv(u.u_uv, false, IDENTITY3);
      gl.uniform1i(u.u_uv_set, 0);
    }
    gl.bindVertexArray(m.vao);
    if (m.indexType) gl.drawElements(m.mode, m.count, m.indexType, 0);
    else gl.drawArrays(m.mode, 0, m.count);
    gl.bindVertexArray(null);
  }
}
