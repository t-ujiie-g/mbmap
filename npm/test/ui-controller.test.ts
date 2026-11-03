import assert from "node:assert/strict";
import test from "node:test";
import { Store } from "../src/ui/controller.ts";

class Counter extends Store<{ n: number; label: string }> {
  constructor(map: { on: (t: string, f: () => void) => void; off: (t: string, f: () => void) => void }) {
    super({ n: 0, label: "zero" });
    this.listen(map, "move", () => this.set({ n: this.state.n + 1 }));
  }
  rename(label: string): void {
    this.set({ label });
  }
}

function fakeMap() {
  const listeners = new Map<string, Set<() => void>>();
  return {
    on: (t: string, f: () => void) => void (listeners.get(t) ?? listeners.set(t, new Set()).get(t)!).add(f),
    off: (t: string, f: () => void) => void listeners.get(t)?.delete(f),
    fire: (t: string) => listeners.get(t)?.forEach((f) => f()),
    count: (t: string) => listeners.get(t)?.size ?? 0,
  };
}

test("Store: a new state object on each change, listeners told only of changes", () => {
  const map = fakeMap();
  const c = new Counter(map);
  const seen: { n: number; label: string }[] = [];
  const off = c.subscribe((s) => seen.push(s));
  const first = c.state;
  map.fire("move");
  c.rename("zero");
  c.rename("one");
  assert.deepEqual(seen, [{ n: 1, label: "zero" }, { n: 1, label: "one" }]);
  assert.notEqual(c.state, first);
  assert.deepEqual(first, { n: 0, label: "zero" });
  off();
  map.fire("move");
  assert.equal(seen.length, 2);
  assert.equal(c.state.n, 2);
});

test("Store: destroy stops listening to the map and drops listeners", () => {
  const map = fakeMap();
  const c = new Counter(map);
  let calls = 0;
  c.subscribe(() => calls++);
  assert.equal(map.count("move"), 1);
  c.destroy();
  assert.equal(map.count("move"), 0);
  c.rename("after");
  assert.equal(calls, 0);
});
