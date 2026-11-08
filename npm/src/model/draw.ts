// Drawing glTF models for mbmap/3d's layers in WebGL2: a model's primitives uploaded once, then drawn
// with its meters taken to clip space by a Web Mercator matrix and, on the globe, a unit-sphere one.
import type { Material, Primitive } from "./gltf";
import { LIGHT, mul, normalMatrix } from "./place";

/** A model ready for drawing: its primitives, materials and decoded images. */
export interface DrawableModel {
  primitives: Primitive[];
  materials: Material[];
  images: ImageBitmap[];
}

const VERTEX = `#version 300 es
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv0;
layout(location = 3) in vec2 a_uv1;
layout(location = 4) in vec4 a_color;
layout(location = 5) in float a_feature;
uniform mat4 u_model;
uniform mat4 u_flat;
uniform mat4 u_globe;
uniform float u_t;
uniform mat3 u_normal;
uniform mat3 u_uv;
uniform int u_uv_set;
uniform float u_point;
out vec3 v_enu;
out vec3 v_normal;
out vec2 v_uv;
out vec4 v_color;
flat out float v_feature;
void main() {
  vec4 p = u_model * vec4(a_pos, 1.0);
  v_feature = a_feature;
  v_enu = p.xyz;
  v_normal = u_normal * a_normal;
  v_uv = (u_uv * vec3(u_uv_set == 1 ? a_uv1 : a_uv0, 1.0)).xy;
  v_color = a_color;
  vec4 f = u_flat * p;
  gl_PointSize = u_point;
  gl_Position = u_t > 0.999 ? u_globe * p : u_t > 0.0 ? mix(f, u_globe * p, u_t) : f;
}`;

const FRAGMENT = `#version 300 es
precision highp float;
in vec3 v_enu;
in vec3 v_normal;
in vec2 v_uv;
in vec4 v_color;
flat in float v_feature;
uniform vec4 u_color;
uniform sampler2D u_image;
uniform bool u_textured;
uniform int u_shading;
uniform float u_cutoff;
uniform float u_opacity;
uniform vec3 u_light;
uniform vec2 u_pick;
uniform bool u_picking;
uniform float u_point;
out vec4 o;
void main() {
  if (u_point > 0.0 && length(gl_PointCoord - 0.5) > 0.5) discard;
  if (u_picking) {
    float f = clamp(floor(v_feature + 0.5), 0.0, 65535.0);
    o = vec4(u_pick, floor(f / 256.0) / 255.0, mod(f, 256.0) / 255.0);
    return;
  }
  vec4 c = u_color * v_color;
  if (u_textured) c *= texture(u_image, v_uv);
  if (u_cutoff >= 0.0) { if (c.a < u_cutoff) discard; c.a = 1.0; }
  float lit = 1.0;
  if (u_shading == 1) lit = 0.55 + 0.45 * max(dot(normalize(v_normal), u_light), 0.0);
  else if (u_shading == 2) lit = 0.55 + 0.45 * abs(dot(normalize(cross(dFdx(v_enu), dFdy(v_enu))), u_light));
  float a = c.a * u_opacity;
  o = vec4(c.rgb * lit * a, a);
}`;

const UNIFORMS = ["u_model", "u_flat", "u_globe", "u_t", "u_normal", "u_uv", "u_uv_set", "u_color", "u_image", "u_textured", "u_shading", "u_cutoff", "u_opacity", "u_light", "u_pick", "u_picking", "u_point"] as const;
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
}

/** Where each attribute goes; a feature's id (`_BATCHID` in b3dm, EXT_mesh_features' `_FEATURE_ID_0`) at 5, for picking. */
const ATTRIBUTE_LOCATIONS: Record<string, number> = { POSITION: 0, NORMAL: 1, TEXCOORD_0: 2, TEXCOORD_1: 3, COLOR_0: 4, _BATCHID: 5, _FEATURE_ID_0: 5 };
const DEFAULTS: Record<number, number[]> = { 1: [0, 0, 1, 0], 2: [0, 0, 0, 0], 3: [0, 0, 0, 0], 4: [1, 1, 1, 1], 5: [0, 0, 0, 0] };
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
    meshes.push({ vao, buffers, mode: p.mode, count, indexType, matrix, material, shading });
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

  constructor(gl: WebGL2RenderingContext) {
    const shader = (type: number, source: string) => {
      const s = gl.createShader(type)!;
      gl.shaderSource(s, source);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(`mbmap: 3d: ${gl.getShaderInfoLog(s)}`);
      return s;
    };
    const p = gl.createProgram()!;
    gl.attachShader(p, shader(gl.VERTEX_SHADER, VERTEX));
    gl.attachShader(p, shader(gl.FRAGMENT_SHADER, FRAGMENT));
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(`mbmap: 3d: ${gl.getProgramInfoLog(p)}`);
    this.#program = p;
    this.#u = Object.fromEntries(UNIFORMS.map((u) => [u, gl.getUniformLocation(p, u)])) as Uniforms;
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

  /** Starts drawing with the globe's `transition` (0: Web Mercator only), colors or, `picking`, ids. */
  begin(gl: WebGL2RenderingContext, transition: number, picking = false): void {
    const u = this.#u;
    gl.useProgram(this.#program);
    gl.uniform1f(u.u_t, transition);
    gl.uniform1i(u.u_picking, picking ? 1 : 0);
    gl.uniform3fv(u.u_light, LIGHT);
    gl.uniform1i(u.u_image, 0);
    gl.activeTexture(gl.TEXTURE0);
  }

  /**
   * Draws `model`'s meshes of `pass` (0: opaque, 1: blended, or all of them with `translucent`): `place`
   * (meters to meters) goes before each mesh's matrix, then `flat` and `globe` take meters to clip space;
   * `feature` is the id meshes without an id attribute are picked with.
   */
  draw(gl: WebGL2RenderingContext, model: GpuModel, place: ArrayLike<number>, flat: ArrayLike<number>, globe: ArrayLike<number> | null, opacity: number, translucent: boolean, pass: number, feature?: number): void {
    const u = this.#u;
    // An instance's feature id, for meshes with no id attribute of their own.
    gl.vertexAttrib4f(5, feature ?? 0, 0, 0, 0);
    gl.uniformMatrix4fv(u.u_flat, false, new Float32Array(flat));
    if (globe) gl.uniformMatrix4fv(u.u_globe, false, new Float32Array(globe));
    gl.uniform1f(u.u_opacity, opacity);
    for (const m of model.meshes) {
      const blend = translucent || m.material?.alphaMode === "BLEND";
      if (blend !== (pass === 1)) continue;
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
