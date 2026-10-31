import assert from "node:assert/strict";
import test from "node:test";
import { referencesOf } from "../scripts/references.mjs";

test("static and dynamic imports and new URL references are found", () => {
  const js = 'import{Map as b}from"./index.js";const w=new URL("./worker.js",import.meta.url);import("./analysis.js");import"./side.js";';
  assert.deepEqual(referencesOf(js), ["./analysis.js", "./index.js", "./side.js", "./worker.js"]);
  // Bare specifiers and absolute URLs are not dist files.
  assert.deepEqual(referencesOf('import"react";new URL("https://x/y.js");'), []);
});
