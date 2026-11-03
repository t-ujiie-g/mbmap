// Builds and packs npm/, installs the tarball into the examples and the test
// pages that use it and builds the React example. Usage: node npm/prepare.mjs
import { execFileSync } from "node:child_process";
import { mkdir, rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ROOT } from "../lib/root.mjs";

const run = (cmd, args, cwd) => execFileSync(cmd, args, { cwd, stdio: ["ignore", "pipe", "inherit"] }).toString();

export async function prepareExamples() {
  const out = path.join(ROOT, "bench/dist/pack");
  run("npm", ["run", "-s", "build"], path.join(ROOT, "npm"));
  await rm(out, { recursive: true, force: true });
  await mkdir(out, { recursive: true });
  const [{ filename, files }] = JSON.parse(run("npm", ["pack", "--json", "--pack-destination", out], path.join(ROOT, "npm")));
  console.log(`${filename}: ${files.map((f) => f.path).join(", ")}`);
  const install = async (dir) => {
    const modules = path.join(ROOT, dir, "node_modules/mbmap");
    await rm(modules, { recursive: true, force: true });
    await mkdir(modules, { recursive: true });
    run("tar", ["xzf", path.join(out, filename), "--strip-components=1", "-C", modules], ROOT);
  };
  for (const page of ["npm", "element", "geojson", "analysis", "media", "custom"]) await install(`bench/npm/pages/${page}`);
  await install("examples/html");
  await install("examples/element");
  // npm ci empties node_modules, so the tarball goes in afterwards.
  run("npm", ["ci", "--no-audit", "--no-fund"], path.join(ROOT, "examples/react"));
  await install("examples/react");
  run("npm", ["run", "-s", "build"], path.join(ROOT, "examples/react"));
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  await prepareExamples();
}
