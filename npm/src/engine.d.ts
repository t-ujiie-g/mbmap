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
  ): EngineMap;
  export function map_camera(map: EngineMap): { lng: number; lat: number; zoom: number; bearing: number; pitch: number };
  export function map_set_camera(map: EngineMap, lng: number, lat: number, zoom: number, bearing: number, pitch: number): void;
  export function map_on_move(map: EngineMap, f: () => void): number;
  export function map_on_idle(map: EngineMap, f: () => void): number;
  export function map_off(map: EngineMap, id: number): void;
  export function map_destroy(map: EngineMap): void;
  export function map_set_limits(map: EngineMap, limits: number[]): void;
  export function map_ease_to(map: EngineMap, target: number[], duration: number, easing: (t: number) => number, id: string): void;
  export function map_fly_to(map: EngineMap, target: number[], options: number[], easing: (t: number) => number): void;
  export function map_stop(map: EngineMap): void;
  export function map_motion(map: EngineMap): number;
  export function map_project(map: EngineMap, lng: number, lat: number): number[];
  export function map_unproject(map: EngineMap, x: number, y: number): number[];
  export function map_bounds(map: EngineMap): number[];
  export function map_camera_for_bounds(map: EngineMap, input: number[]): number[];
  export function map_set_handler(map: EngineMap, handler: number, enabled: boolean): void;
  export function map_handler_enabled(map: EngineMap, handler: number): boolean;
  export function map_on_move_start(map: EngineMap, f: (e: Event | null) => void): number;
  export function map_on_move_end(map: EngineMap, f: (e: Event | null) => void): number;
  export function map_input_event(map: EngineMap): Event | null;
  export function default_easing(t: number): number;
}
