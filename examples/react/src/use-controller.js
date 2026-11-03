// A controller's state in a component: `mbmap/ui` and `mbmap/search` controllers
// fit `useSyncExternalStore` as they are.
import { useSyncExternalStore } from "react";

export function useController(c) {
  return useSyncExternalStore(c.subscribe, () => c.state);
}
