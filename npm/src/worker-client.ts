// The calls of a module entry to the worker it starts: `{type: "call", id, op, ...}` answered by
// `{type: "result", id, value | error}` (docs/FORMATS.md).
import { workerScriptUrl } from "./urls.ts";

export class WorkerClient {
  #name: string;
  #worker: Worker | null = null;
  #pending = new Map<number, { resolve: (v: any) => void; reject: (e: Error) => void }>();
  #next = 0;
  #generation = 0;

  /** `name` prefixes the errors: `mbmap: <name>: ...`. */
  constructor(name: string) {
    this.#name = name;
  }

  get started(): boolean {
    return this.#worker !== null;
  }

  /** Counts the workers stopped, so handles a worker gave can tell when it is gone (worker ids start again). */
  get generation(): number {
    return this.#generation;
  }

  /** Starts the worker at `script` (same-origin) unless it runs, and sends it `init`. */
  start(script: string | URL, init: (page: URL) => object): void {
    if (this.#worker) return;
    const page = new URL(document.baseURI);
    const w = new Worker(workerScriptUrl(script, page, location.origin), { type: "module" });
    w.onmessage = (e: MessageEvent) => {
      const msg = e.data;
      const call = msg?.type === "result" ? this.#pending.get(msg.id) : undefined;
      if (!call) return;
      this.#pending.delete(msg.id);
      if (typeof msg.error === "string") call.reject(new Error(`mbmap: ${this.#name}: ${msg.error}`));
      else call.resolve(msg.value);
    };
    // A worker that fails to load or run fails its calls rather than leaving them waiting.
    w.onerror = (e: ErrorEvent) => this.#fail(e.message || "the worker failed");
    w.onmessageerror = () => this.#fail("a message could not be read");
    w.postMessage({ type: "init", ...init(page) });
    this.#worker = w;
  }

  call<T>(op: string, args: object, transfer: Transferable[] = []): Promise<T> {
    const w = this.#worker;
    if (!w) return Promise.reject(new Error(`mbmap: ${this.#name}: the worker has not been started`));
    const id = this.#next++;
    return new Promise<T>((resolve, reject) => {
      this.#pending.set(id, { resolve, reject });
      w.postMessage({ type: "call", id, op, ...args }, transfer);
    });
  }

  /** Stops the worker; pending calls reject. */
  terminate(): void {
    this.#fail("terminated");
  }

  #fail(why: string): void {
    this.#worker?.terminate();
    this.#worker = null;
    this.#generation++;
    for (const p of this.#pending.values()) p.reject(new Error(`mbmap: ${this.#name}: ${why}`));
    this.#pending.clear();
  }
}
