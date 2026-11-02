// node --test bench/lib/serve.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { ROOT } from "./root.mjs";
import { byteRange, resolveRequestPath } from "./serve.mjs";

test("serves files under the repository root", () => {
  assert.equal(resolveRequestPath("/bench/maplibre/style.json"), path.join(ROOT, "bench/maplibre/style.json"));
  assert.equal(resolveRequestPath("/bench/../bench/README.md"), path.join(ROOT, "bench/README.md"));
});

test("never resolves outside the root, including sibling-prefix directories", () => {
  for (const p of ["/..%2fmbmap-other%2fx", "/..%2f..%2fetc%2fpasswd", "/%2e%2e/x"]) {
    const file = resolveRequestPath(p);
    assert.ok(file === null || !path.relative(ROOT, file).startsWith(".."), `${p} -> ${file}`);
  }
  assert.equal(resolveRequestPath("/"), null);
});

test("rejects dotfiles, NUL bytes and malformed escapes", () => {
  for (const p of ["/.git/HEAD", "/bench/.env", "/a%00b", "/%E0%A4%A"]) {
    assert.equal(resolveRequestPath(p), null, p);
  }
});

test("byteRange takes one range, clamps its end and refuses others", () => {
  assert.deepEqual(byteRange("bytes=0-99", 1000), [0, 99]);
  assert.deepEqual(byteRange("bytes=900-", 1000), [900, 999]);
  assert.deepEqual(byteRange("bytes=900-5000", 1000), [900, 999]);
  assert.equal(byteRange(undefined, 1000), null);
  assert.equal(byteRange("bytes=1000-", 1000), "bad");
  assert.equal(byteRange("bytes=0-1,5-9", 1000), "bad");
  assert.equal(byteRange("items=0-1", 1000), "bad");
});
