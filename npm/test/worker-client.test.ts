import assert from "node:assert/strict";
import test from "node:test";
import { WorkerClient } from "../src/worker-client.ts";

class FakeWorker {
  static last: FakeWorker;
  url: string;
  options: unknown;
  posted: unknown[] = [];
  transfers: unknown[] = [];
  terminated = false;
  onmessage: ((e: { data: unknown }) => void) | null = null;
  onerror: ((e: { message?: string }) => void) | null = null;
  onmessageerror: (() => void) | null = null;

  constructor(url: string, options: unknown) {
    this.url = url;
    this.options = options;
    FakeWorker.last = this;
  }

  postMessage(message: unknown, transfer?: unknown): void {
    this.posted.push(message);
    this.transfers.push(transfer);
  }

  terminate(): void {
    this.terminated = true;
  }
}

Object.assign(globalThis, {
  Worker: FakeWorker,
  document: { baseURI: "https://x.org/maps/page.html" },
  location: { origin: "https://x.org" },
});

function started(): { client: WorkerClient; worker: FakeWorker } {
  const client = new WorkerClient("data");
  client.start("./data-worker.js", () => ({}));
  return { client, worker: FakeWorker.last };
}

test("start resolves the script against the page and sends init once", () => {
  const client = new WorkerClient("data");
  assert.equal(client.started, false);
  client.start("./data-worker.js", (page) => ({ page: page.href }));
  const worker = FakeWorker.last;
  assert.equal(worker.url, "https://x.org/maps/data-worker.js");
  assert.deepEqual(worker.options, { type: "module" });
  assert.deepEqual(worker.posted, [{ type: "init", page: "https://x.org/maps/page.html" }]);
  assert.equal(client.started, true);
  client.start("./other.js", () => ({}));
  assert.equal(FakeWorker.last, worker);
});

test("start refuses a worker from elsewhere", () => {
  const client = new WorkerClient("data");
  assert.throws(() => client.start("https://y.org/w.js", () => ({})), /same-origin/);
  assert.throws(() => client.start("data:text/javascript,", () => ({})), /same-origin/);
  assert.equal(client.started, false);
});

test("a call before start rejects", async () => {
  await assert.rejects(new WorkerClient("data").call("read", {}), /^Error: mbmap: data: the worker has not been started$/);
});

test("a call posts its op and arguments and takes its answer by id", async () => {
  const { client, worker } = started();
  const transfer = [new ArrayBuffer(1)];
  const [a, b] = [client.call("read", { x: 1 }, transfer), client.call("write", {})];
  assert.deepEqual(worker.posted.slice(1), [{ type: "call", id: 0, op: "read", x: 1 }, { type: "call", id: 1, op: "write" }]);
  assert.equal(worker.transfers[1], transfer);
  worker.onmessage!({ data: { type: "result", id: 1, value: "b" } });
  worker.onmessage!({ data: { type: "result", id: 0, value: "a" } });
  assert.deepEqual(await Promise.all([a, b]), ["a", "b"]);
});

test("an answer with an error rejects its call, named after the entry", async () => {
  const { client, worker } = started();
  const call = client.call("read", {});
  worker.onmessage!({ data: { type: "result", id: 0, error: "no such file" } });
  await assert.rejects(call, /^Error: mbmap: data: no such file$/);
});

test("answers with an unknown id, or that are not answers, are ignored", async () => {
  const { client, worker } = started();
  const call = client.call("read", {});
  for (const data of [{ type: "result", id: 7, value: "x" }, { type: "other", id: 0, value: "x" }, null, undefined, "result"]) worker.onmessage!({ data });
  worker.onmessage!({ data: { type: "result", id: 0, value: "kept" } });
  assert.equal(await call, "kept");
  worker.onmessage!({ data: { type: "result", id: 0, value: "twice" } });
});

test("onerror rejects every pending call and stops the worker", async () => {
  const { client, worker } = started();
  const calls = [client.call("read", {}), client.call("read", {})];
  worker.onerror!({ message: "failed to load" });
  for (const call of calls) await assert.rejects(call, /^Error: mbmap: data: failed to load$/);
  assert.equal(client.generation, 1);
  assert.equal(worker.terminated, true);
  assert.equal(client.started, false);
  await assert.rejects(client.call("read", {}), /has not been started/);
});

test("onerror without a message says the worker failed", async () => {
  const { client, worker } = started();
  const call = client.call("read", {});
  worker.onerror!({});
  await assert.rejects(call, /^Error: mbmap: data: the worker failed$/);
});

test("onmessageerror rejects pending calls", async () => {
  const { client, worker } = started();
  const call = client.call("read", {});
  worker.onmessageerror!();
  await assert.rejects(call, /^Error: mbmap: data: a message could not be read$/);
});

test("terminate rejects pending calls and lets the client start again", async () => {
  const { client, worker } = started();
  const call = client.call("read", {});
  const generation = client.generation;
  client.terminate();
  await assert.rejects(call, /^Error: mbmap: data: terminated$/);
  assert.equal(worker.terminated, true);
  assert.equal(client.generation, generation + 1);
  client.start("./data-worker.js", () => ({}));
  assert.notEqual(FakeWorker.last, worker);
  const next = client.call("read", {});
  FakeWorker.last.onmessage!({ data: { type: "result", id: 1, value: "again" } });
  assert.equal(await next, "again");
});
