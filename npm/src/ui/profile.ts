// An elevation profile without its look: samples along a line's geodesics, their
// distance and elevation, the one pointed at. Measuring and elevations come from
// the page (mbmap/geodesic's `measure`, mbmap/analysis's `sampleDem`).
import { Store, type Controller } from "./controller";
import { nearestIndex, profileStats } from "./elevation";
import type { Measure, Position } from "./measurement";

/** The elevations in meters at `positions` (NaN where unknown). */
export type Elevation = (positions: Position[]) => Promise<ArrayLike<number>>;

/**
 * `positions` of the line (empty for none); `path` its samples, `distances` along it to each (m)
 * and `elevations` there (m, NaN without data); `length`, `min`, `max`, `gain` and `loss` in meters;
 * `active` the sample pointed at (-1 for none); `loading` while it is computed; `error` of the last
 * attempt.
 */
export interface ProfileState {
  positions: Position[];
  path: Position[];
  distances: number[];
  elevations: number[];
  length: number;
  min: number;
  max: number;
  gain: number;
  loss: number;
  active: number;
  loading: boolean;
  error: string | null;
}

/** `measure`: mbmap/geodesic's; `elevation`: the heights at positions; `samples`: about how many along the line (default 200). */
export interface ProfileOptions {
  measure: Measure;
  elevation: Elevation;
  samples?: number;
}

export interface Profile extends Controller<ProfileState> {
  setLine(positions: Position[]): Promise<void>;
  highlight(distance: number | null): void;
  clear(): void;
}

const EMPTY: ProfileState = {
  positions: [], path: [], distances: [], elevations: [], length: 0, min: NaN, max: NaN, gain: 0, loss: 0, active: -1, loading: false, error: null,
};

class ProfileStore extends Store<ProfileState> implements Profile {
  #options: ProfileOptions;
  #ticket = 0;

  constructor(options: ProfileOptions) {
    super(EMPTY);
    this.#options = options;
  }

  async setLine(positions: Position[]): Promise<void> {
    const ticket = ++this.#ticket;
    if (positions.length < 2) {
      this.set({ ...EMPTY, positions });
      return;
    }
    this.set({ positions, loading: true, error: null, active: -1 });
    const { measure, elevation, samples = 200 } = this.#options;
    try {
      const whole = await measure(positions, { closed: false });
      const step = Math.max(whole.length / samples, 0.01);
      const path = (await measure(positions, { closed: false, step })).path ?? positions;
      const [along, heights] = await Promise.all([measure(path, { closed: false }), elevation(path)]);
      // A later line, or a clear, has replaced this one.
      if (ticket !== this.#ticket) return;
      const elevations = Array.from(heights);
      this.set({ path, distances: Array.from(along.distances), elevations, length: along.length, ...profileStats(elevations), loading: false });
    } catch (err) {
      if (ticket === this.#ticket) this.set({ ...EMPTY, positions, error: err instanceof Error ? err.message : String(err) });
    }
  }

  highlight(distance: number | null): void {
    this.set({ active: distance === null ? -1 : nearestIndex(this.state.distances, distance) });
  }

  clear(): void {
    this.#ticket++;
    this.set(EMPTY);
  }
}

/** A profile controller; it takes no map, as the line comes from the page (a measurement, a feature). */
export function createProfile(options: ProfileOptions): Profile {
  return new ProfileStore(options);
}
