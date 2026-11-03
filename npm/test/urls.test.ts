import assert from "node:assert/strict";
import test from "node:test";
import { httpUrl, resolveTemplate, wasmUrl, workerScriptUrl } from "../src/urls.ts";

const base = new URL("https://example.com/styles/style.json");

test("tile templates resolve against the style and keep their placeholders", () => {
  assert.equal(resolveTemplate("tiles/{z}/{x}/{y}.pbf", base), "https://example.com/styles/tiles/{z}/{x}/{y}.pbf");
  assert.equal(resolveTemplate("/t/{z}/{x}/{y}.pbf", base), "https://example.com/t/{z}/{x}/{y}.pbf");
  assert.equal(resolveTemplate("https://cdn.test/{z}/{x}/{y}", base), "https://cdn.test/{z}/{x}/{y}");
  // Only the three placeholders are restored.
  assert.equal(resolveTemplate("t/{a}/{z}", base), "https://example.com/styles/t/%7Ba%7D/{z}");
});

test("httpUrl resolves against the base and refuses other schemes", () => {
  assert.equal(httpUrl("sprite", base, "the sprite"), "https://example.com/styles/sprite");
  assert.equal(httpUrl("http://a.test/s.json", "https://b.test/", "the style"), "http://a.test/s.json");
  for (const bad of ["data:image/png;base64,AA==", "blob:https://example.com/x", "file:///etc/passwd", "javascript:1"]) {
    assert.throws(() => httpUrl(bad, base, "the sprite"), /the sprite must be an http\(s\) URL/);
  }
});

test("tile templates must be http(s), PMTiles archives too", () => {
  assert.equal(resolveTemplate("pmtiles://https://cdn.test/a.pmtiles/{z}/{x}/{y}", base), "pmtiles://https://cdn.test/a.pmtiles/{z}/{x}/{y}");
  assert.equal(resolveTemplate("pmtiles://a.pmtiles/{z}/{x}/{y}", base), "pmtiles://https://example.com/styles/a.pmtiles/{z}/{x}/{y}");
  for (const bad of ["data:application/x-protobuf;base64,AA==#{z}", "blob:https://example.com/{z}", "pmtiles://data:,x/{z}/{x}/{y}"]) {
    assert.throws(() => resolveTemplate(bad, base), /tiles must be an http\(s\) URL/);
  }
});

test("workers load only from same-origin http(s) URLs", () => {
  const origin = "https://example.com";
  assert.equal(workerScriptUrl("./worker.js", base, origin), "https://example.com/styles/worker.js");
  assert.equal(workerScriptUrl(new URL("https://example.com/w.js"), base, origin), "https://example.com/w.js");
  for (const bad of ["data:text/javascript,1", "blob:https://example.com/x", "https://evil.test/w.js", "javascript:1"]) {
    assert.throws(() => workerScriptUrl(bad, base, origin), /same-origin http\(s\)/);
  }
});

test("wasm loads only from http(s) URLs", () => {
  assert.equal(wasmUrl("https://cdn.test/mbmap.wasm", base), "https://cdn.test/mbmap.wasm");
  for (const bad of ["data:application/wasm;base64,AA==", "file:///x.wasm"]) {
    assert.throws(() => wasmUrl(bad, base), /http\(s\)/);
  }
});
