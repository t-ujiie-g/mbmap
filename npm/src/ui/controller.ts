// The shape every `mbmap/ui` controller has (VISION §6): its `state` as a value,
// operations as methods, and `subscribe` for changes. Import-free.

/**
 * `state` is a new object whenever something in it changes (so React's `useSyncExternalStore` can
 * take `subscribe` and `() => c.state` as they are); `subscribe` returns the unsubscribe function
 * and does not call the listener at once; `destroy` stops listening to the map.
 */
export interface Controller<S> {
  readonly state: S;
  subscribe(listener: (state: S) => void): () => void;
  destroy(): void;
}

/** The map events a controller listens to, as the facade's `on` / `off` take them. */
export interface Events {
  on(type: string, listener: (e: any) => void): unknown;
  off(type: string, listener: (e: any) => void): unknown;
}

/** State, listeners and the map listeners to remove: the common part of every controller. */
export class Store<S extends object> implements Controller<S> {
  #state: S;
  #listeners = new Set<(state: S) => void>();
  #cleanups: (() => void)[] = [];

  constructor(state: S) {
    this.#state = state;
  }

  get state(): S {
    return this.#state;
  }

  subscribe = (listener: (state: S) => void): (() => void) => {
    this.#listeners.add(listener);
    return () => {
      this.#listeners.delete(listener);
    };
  };

  /** Merges `patch` into the state; listeners hear of it only if a value changed. */
  protected set(patch: Partial<S>): void {
    const next = { ...this.#state, ...patch };
    if (Object.keys(next).every((k) => Object.is(next[k as keyof S], this.#state[k as keyof S]))) return;
    this.#state = next;
    for (const f of [...this.#listeners]) {
      try {
        f(next);
      } catch (err) {
        queueMicrotask(() => {
          throw err;
        });
      }
    }
  }

  /** Listens to `type` on `map` until `destroy`. */
  protected listen(map: Events, type: string, f: (e: any) => void): void {
    map.on(type, f);
    this.#cleanups.push(() => map.off(type, f));
  }

  /** Runs `f` on `destroy`. */
  protected onDestroy(f: () => void): void {
    this.#cleanups.push(f);
  }

  destroy(): void {
    for (const f of this.#cleanups.splice(0)) f();
    this.#listeners.clear();
  }
}
