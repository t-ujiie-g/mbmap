// node --test bench/lib/serve.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { ROOT } from "./root.mjs";
import { resolveRequestPath } from "./serve.mjs";

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
