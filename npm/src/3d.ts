// `mbmap/3d`: glTF models read in a worker of their own (meshopt decoding in its wasm) and placed on
// the map at GeoJSON points by a custom layer, on Web Mercator and on the globe.
import type { CustomLayerInterface, CustomRenderMethodInput } from "./custom";
import type { Material, Primitive } from "./model/gltf";
import { LIGHT, Y_UP, finite3, mercatorFrame, mul, normalMatrix, placement, points, sphereFrame, value, type Value } from "./model/place";
import { wasmUrl } from "./urls";
import { WorkerClient } from "./worker-client";

/** Where the 3D worker (`workerUrl`) and its wasm (`wasmUrl`) are served; by default next to this module. */
export interface ModelOptions {
  workerUrl?: string | URL;
  wasmUrl?: string | URL;
}

/** A glTF model as read: its primitives, materials and decoded images. */
export interface LoadedModel {
  primitives: Primitive[];
  materials: Material[];
  images: ImageBitmap[];
}

export type { Value } from "./model/place";

/**
 * A model layer: `model` (a URL of a .glb or .gltf, or a model `loadModel` gave) at each point of
 * `data` (a GeoJSON Point, Feature or FeatureCollection; a third coordinate is the height in meters).
 * `scale` [x, y, z], `rotation` [x, y, z] in degrees about the east, north and up axes (z turns the
 * model clockwise seen from above) and `translation` [east, north, up] in meters, as Mapbox's
 * `model-scale`, `model-rotation` and `model-translation`; `opacity` 0 to 1.
 */
export interface ModelLayerOptions extends ModelOptions {
  id: string;
  model: string | LoadedModel;
  data: unknown;
  scale?: Value<[number, number, number]>;
  rotation?: Value<[number, number, number]>;
  translation?: Value<[number, number, number]>;
  opacity?: Value<number>;
}

const client = new WorkerClient("3d");

function start(options: ModelOptions): void {
  client.start(options.workerUrl ?? new URL("./3d-worker.js", import.meta.url), (page) => ({
    wasm: wasmUrl(options.wasmUrl ?? new URL("./3d.wasm", import.meta.url), page),
  }));
}

/** Reads the glTF model at `url` (.glb, or .gltf with its buffers and images beside it). */
export async function loadModel(url: string | URL, options: ModelOptions = {}): Promise<LoadedModel> {
  start(options);
  return client.call<LoadedModel>("load", { url: new URL(url, document.baseURI).href });
}

/** Stops the 3D worker; pending loads reject. */
export function terminate(): void {
  client.terminate();
}

const VERTEX = `#version 300 es
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv0;
layout(location = 3) in vec2 a_uv1;
layout(location = 4) in vec4 a_color;
uniform mat4 u_model;
uniform mat4 u_flat;
uniform mat4 u_globe;
uniform float u_t;
uniform mat3 u_normal;
uniform mat3 u_uv;
uniform int u_uv_set;
out vec3 v_enu;
out vec3 v_normal;
out vec2 v_uv;
out vec4 v_color;
void main() {
  vec4 p = u_model * vec4(a_pos, 1.0);
  v_enu = p.xyz;
  v_normal = u_normal * a_normal;
  v_uv = (u_uv * vec3(u_uv_set == 1 ? a_uv1 : a_uv0, 1.0)).xy;
  v_color = a_color;
  vec4 f = u_flat * p;
  gl_Position = u_t > 0.999 ? u_globe * p : u_t > 0.0 ? mix(f, u_globe * p, u_t) : f;
}`;

const FRAGMENT = `#version 300 es
precision highp float;
in vec3 v_enu;
in vec3 v_normal;
in vec2 v_uv;
in vec4 v_color;
uniform vec4 u_color;
uniform sampler2D u_image;
uniform bool u_textured;
uniform int u_shading;
uniform float u_cutoff;
uniform float u_opacity;
uniform vec3 u_light;
out vec4 o;
void main() {
  vec4 c = u_color * v_color;
  if (u_textured) c *= texture(u_image, v_uv);
  if (u_cutoff >= 0.0) { if (c.a < u_cutoff) discard; c.a = 1.0; }
  float lit = 1.0;
  if (u_shading == 1) lit = 0.55 + 0.45 * max(dot(normalize(v_normal), u_light), 0.0);
  else if (u_shading == 2) lit = 0.55 + 0.45 * abs(dot(normalize(cross(dFdx(v_enu), dFdy(v_enu))), u_light));
  float a = c.a * u_opacity;
  o = vec4(c.rgb * lit * a, a);
}`;

const UNIFORMS = ["u_model", "u_flat", "u_globe", "u_t", "u_normal", "u_uv", "u_uv_set", "u_color", "u_image", "u_textured", "u_shading", "u_cutoff", "u_opacity", "u_light"] as const;
type Uniforms = Record<(typeof UNIFORMS)[number], WebGLUniformLocation | null>;

/** A primitive on the GPU: its vertex array, how to draw it, and what it is drawn with. */
interface Mesh {
  vao: WebGLVertexArrayObject;
  buffers: WebGLBuffer[];
  mode: number;
  count: number;
  indexType: number;
  matrix: Float64Array;
  material?: Material;
  shading: number;
}

/** A point the model stands at, with its own transform. */
interface Instance {
  lng: number;
  lat: number;
  height: number;
  transform: Float64Array;
  opacity: number;
}

const ATTRIBUTE_LOCATIONS: Record<string, number> = { POSITION: 0, NORMAL: 1, TEXCOORD_0: 2, TEXCOORD_1: 3, COLOR_0: 4 };
const DEFAULTS: Record<number, number[]> = { 1: [0, 0, 1, 0], 2: [0, 0, 0, 0], 3: [0, 0, 0, 0], 4: [1, 1, 1, 1] };
const IDENTITY3 = new Float32Array([1, 0, 0, 0, 1, 0, 0, 0, 1]);

/** A custom layer drawing a glTF model at each point of its data (`modelLayer`). */
export class ModelLayer implements CustomLayerInterface {
  readonly id: string;
  readonly type = "custom" as const;
  readonly renderingMode = "3d" as const;
  /** Settles once the model is loaded (or rejects with why it was not). */
  readonly ready: Promise<void>;
  #options: ModelLayerOptions;
  #model: LoadedModel | null = null;
  #instances: Instance[] = [];
  #map: { triggerRepaint?: () => void } | null = null;
  #gl: WebGL2RenderingContext | null = null;
  #program: WebGLProgram | null = null;
  #uniforms: Uniforms | null = null;
  #meshes: Mesh[] = [];
  #textures: WebGLTexture[] = [];

  constructor(options: ModelLayerOptions) {
    this.id = options.id;
    this.#options = options;
    this.setData(options.data);
    const model = typeof options.model === "string" ? loadModel(options.model, options) : Promise.resolve(options.model);
    this.ready = model.then((m) => {
      this.#model = m;
      if (this.#gl) this.#upload(this.#gl);
      this.#map?.triggerRepaint?.();
    });
  }

  /** Places the model at the points of `data` from now on. */
  setData(data: unknown): void {
    const o = this.#options;
    this.#instances = points(data).map(({ coords, props }) => {
      const scale = finite3(value(o.scale, props, [1, 1, 1]), [1, 1, 1]);
      const rotation = finite3(value(o.rotation, props, [0, 0, 0]), [0, 0, 0]);
      const translation = finite3(value(o.translation, props, [0, 0, 0]), [0, 0, 0]);
      const opacity = Number(value(o.opacity, props, 1));
      return {
        lng: coords[0],
        lat: Math.max(-85.051129, Math.min(85.051129, coords[1])),
        height: Number.isFinite(coords[2]) ? coords[2] : 0,
        transform: placement(scale, rotation, translation),
        opacity: Number.isFinite(opacity) ? Math.max(0, Math.min(1, opacity)) : 1,
      };
    });
    this.#map?.triggerRepaint?.();
  }

  onAdd(map: unknown, gl: WebGL2RenderingContext): void {
    this.#map = map as { triggerRepaint?: () => void };
    this.#gl = gl;
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
    this.#uniforms = Object.fromEntries(UNIFORMS.map((u) => [u, gl.getUniformLocation(p, u)])) as Uniforms;
    if (this.#model) this.#upload(gl);
  }

  onRemove(_map: unknown, gl: WebGL2RenderingContext): void {
    this.#release(gl);
    if (this.#program) gl.deleteProgram(this.#program);
    this.#program = null;
    this.#map = null;
    this.#gl = null;
  }

  #release(gl: WebGL2RenderingContext): void {
    for (const m of this.#meshes) {
      gl.deleteVertexArray(m.vao);
      for (const b of m.buffers) gl.deleteBuffer(b);
    }
    for (const t of this.#textures) gl.deleteTexture(t);
    this.#meshes = [];
    this.#textures = [];
  }

  #upload(gl: WebGL2RenderingContext): void {
    const model = this.#model!;
    this.#release(gl);
    this.#textures = model.images.map((image) => {
      const t = gl.createTexture()!;
      gl.bindTexture(gl.TEXTURE_2D, t);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
      gl.generateMipmap(gl.TEXTURE_2D);
      return t;
    });
    gl.bindTexture(gl.TEXTURE_2D, null);
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
        if (!v || p.attributes[name]) continue;
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
      const matrix = mul(Y_UP, p.matrix);
      const shading = material?.unlit ? 0 : p.attributes.NORMAL ? 1 : 2;
      this.#meshes.push({ vao, buffers, mode: p.mode, count, indexType, matrix, material, shading });
    }
  }

  render(gl: WebGL2RenderingContext, options: CustomRenderMethodInput): void {
    const u = this.#uniforms;
    if (!u || !this.#program || !this.#meshes.length || !this.#instances.length) return;
    const d = options.defaultProjectionData;
    const t = d.projectionTransition;
    // On the globe `mainMatrix` is Float32 and the full-precision globe matrix is the model-view-projection.
    const flat = t > 0 ? d.fallbackMatrix : d.mainMatrix;
    const plane = d.clippingPlane;
    gl.useProgram(this.#program);
    gl.uniform1f(u.u_t, t);
    gl.uniform3fv(u.u_light, LIGHT);
    gl.uniform1i(u.u_image, 0);
    gl.activeTexture(gl.TEXTURE0);
    for (const pass of [0, 1]) {
      gl.depthMask(pass === 0);
      for (const inst of this.#instances) {
        const translucent = inst.opacity < 1;
        const frame = sphereFrame(inst.lng, inst.lat, inst.height);
        if (t > 0 && frame[12] * plane[0] + frame[13] * plane[1] + frame[14] * plane[2] + plane[3] < 0) continue;
        const flatMatrix = mul(flat, mercatorFrame(inst.lng, inst.lat, inst.height));
        gl.uniformMatrix4fv(u.u_flat, false, new Float32Array(flatMatrix));
        if (t > 0) gl.uniformMatrix4fv(u.u_globe, false, new Float32Array(mul(options.modelViewProjectionMatrix, frame)));
        gl.uniform1f(u.u_opacity, inst.opacity);
        for (const m of this.#meshes) {
          const blend = translucent || m.material?.alphaMode === "BLEND";
          if (blend !== (pass === 1)) continue;
          this.#draw(gl, u, m, mul(inst.transform, m.matrix), inst.transform);
        }
      }
    }
    gl.depthMask(true);
  }

  #draw(gl: WebGL2RenderingContext, u: Uniforms, m: Mesh, model: Float64Array, placed: Float64Array): void {
    const mat = m.material;
    gl.uniformMatrix4fv(u.u_model, false, new Float32Array(model));
    gl.uniformMatrix3fv(u.u_normal, false, normalMatrix(mul(placed, m.matrix)));
    gl.uniform4fv(u.u_color, mat?.color ?? [1, 1, 1, 1]);
    gl.uniform1i(u.u_shading, m.shading);
    gl.uniform1f(u.u_cutoff, mat?.alphaMode === "MASK" ? mat.alphaCutoff : -1);
    const tex = mat?.texture;
    const texture = tex ? this.#textures[tex.image] : undefined;
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

/** A custom layer for `map.addLayer` drawing a glTF model at each point of `options.data`. */
export function modelLayer(options: ModelLayerOptions): ModelLayer {
  return new ModelLayer(options);
}
