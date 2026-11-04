// The MoonBit exports of bundle/main (esbuild aliases "mbmap-engine" to its
// js build). Keep in sync with bundle/main/main.mbt.
declare module "mbmap-engine" {
  export interface EngineMap {
    readonly __engineMap: unique symbol;
  }
  /** Tiles of GeoJSON sources, by source id (see map/dom.mbt `Provider`). */
  export type Provider = (source: string, z: number, x: number, y: number) => Promise<ArrayBuffer | null>;
  export function create_map(
    canvas: HTMLCanvasElement,
    style: string,
    lng: number,
    lat: number,
    zoom: number,
    bearing: number,
    pitch: number,
    workerUrl: string,
    wasmUrl: string,
    workers: number,
    geojson: Provider | null,
    font: string,
    limits: number[],
    strict: boolean,
  ): EngineMap;
  export function map_camera(map: EngineMap): { lng: number; lat: number; zoom: number; bearing: number; pitch: number };
  export function map_set_camera(map: EngineMap, lng: number, lat: number, zoom: number, bearing: number, pitch: number): void;
  export function map_on_move(map: EngineMap, f: () => void): number;
  export function map_on_idle(map: EngineMap, f: () => void): number;
  export function map_on_render(map: EngineMap, f: () => void): number;
  export function map_off(map: EngineMap, id: number): void;
  export function map_destroy(map: EngineMap): void;
  export function map_set_limits(map: EngineMap, limits: number[]): void;
  export function map_ease_to(map: EngineMap, target: number[], duration: number, easing: (t: number) => number, id: string): void;
  export function map_fly_to(map: EngineMap, target: number[], options: number[], easing: (t: number) => number): void;
  export function map_stop(map: EngineMap): void;
  export function map_motion(map: EngineMap): number;
  export function map_project(map: EngineMap, lng: number, lat: number): number[];
  export function map_unproject(map: EngineMap, x: number, y: number): number[];
  export function map_locate(map: EngineMap, points: number[]): number[];
  export function map_is_idle(map: EngineMap): boolean;
  export function map_constrained_zoom(map: EngineMap, zoom: number): number;
  export function map_paint_at(map: EngineMap, id: string, props: Record<string, unknown>): PaintValues | null;
  export function map_max_region(map: EngineMap): number;
  export function map_render_region(map: EngineMap, ratio: number, x: number, y: number, width: number, height: number): Uint8ClampedArray<ArrayBuffer>;
  export function map_bounds(map: EngineMap): number[];
  export function map_camera_for_bounds(map: EngineMap, input: number[]): number[];
  export function map_set_handler(map: EngineMap, handler: number, enabled: boolean): void;
  export function map_handler_enabled(map: EngineMap, handler: number): boolean;
  export function map_on_move_start(map: EngineMap, f: (e: Event | null) => void): number;
  export function map_on_move_end(map: EngineMap, f: (e: Event | null) => void): number;
  export function map_input_event(map: EngineMap): Event | null;
  export function default_easing(t: number): number;
  /** "" once drawn, or why the style was refused (the current one stays). */
  export function map_set_style(map: EngineMap, style: string, strict: boolean): string;
  /** What the current style leaves out: path, message, path, ... */
  export function map_warnings(map: EngineMap): string[];
  /** A GeoJSON source's `clusterProperties` (JSON text) compiled for its worker; empty if they cannot be. */
  export function compile_cluster_properties(json: string): Uint8Array;
  export function map_reload_source(map: EngineMap, id: string): void;
  /** Shows `picture` (null for nothing) for image, video or canvas source `id`, placed by `quad` (media.ts `quadOf`). */
  export function map_set_media(map: EngineMap, id: string, picture: TexImageSource | null, quad: number[]): void;
  export function map_set_media_quad(map: EngineMap, id: string, quad: number[]): void;
  export function map_set_media_playing(map: EngineMap, id: string, playing: boolean): void;
  /** Draws the style's custom layers through `f` (npm/src/custom.ts), with `Map::custom_numbers`. */
  export function map_set_custom_renderer(map: EngineMap, f: (id: string, prerender: boolean, numbers: number[]) => void): void;
  export function map_gl(map: EngineMap): WebGL2RenderingContext;
  export function map_trigger_repaint(map: EngineMap): void;
  /** One tile's hits: their layers' ids (-1 for a source query), feature indices, depths and GeoJSON features. */
  export interface PaintValues {
    color: number[];
    width: number;
    radius: number;
    stroke: number[];
    strokeWidth: number;
    halo: number[];
    haloWidth: number;
  }
  export interface TileResult {
    z: number;
    x: number;
    y: number;
    hits: { layer: string | number; index: number; distance: number; feature: import("./query").GeoJSONFeature }[];
  }
  /** "" once sent (`done` gets each tile's hits), or why the query cannot run. */
  export function map_query_rendered(
    map: EngineMap,
    points: number[],
    allLayers: boolean,
    layers: string[],
    filter: string,
    done: (tiles: TileResult[]) => void,
  ): string;
  export function map_add_image(map: EngineMap, name: string, width: number, height: number, data: Uint8Array, pixelRatio: number, sdf: boolean): boolean;
  export function map_remove_image(map: EngineMap, name: string): boolean;
  export function map_has_image(map: EngineMap, name: string): boolean;
  export function map_image_names(map: EngineMap): string[];
  export function map_on_missing_image(map: EngineMap, f: (name: string) => void): void;
  export function map_hold_images(map: EngineMap, loading: boolean): void;
  export function map_set_feature_state(map: EngineMap, source: string, sourceLayer: string, id: string, state: Record<string, unknown> | null): void;
  export function map_set_transform_request(map: EngineMap, f: ((url: string, resourceType: "Tile") => unknown) | null): void;
  export function map_query_source(map: EngineMap, source: string, sourceLayer: string, filter: string, done: (tiles: TileResult[]) => void): string;
}
