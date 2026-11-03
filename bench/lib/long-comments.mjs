// Lists comment blocks over three lines in the tracked sources (AGENTS.md §7.7);
// doc comments describing a type's items or options may stay longer.
// Usage: node bench/lib/long-comments.mjs (from the repo root).
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const files = execFileSync("git", ["ls-files", "*.mbt", "*.ts", "*.mjs", "*.js", "*.jsx"], { encoding: "utf8" })
  .split("\n")
  .filter((f) => f && !f.startsWith("bench/backend/"));
let count = 0;
for (const f of files) {
  const lines = readFileSync(f, "utf8").split("\n");
  for (let i = 0; i < lines.length; ) {
    const s = lines[i].trim();
    const line = (k) => lines[k]?.trim() ?? "";
    let n = 0;
    let j = i + 1;
    if (s.startsWith("//") && s !== "///|") {
      j = i;
      while (j < lines.length && line(j).startsWith("//") && line(j) !== "///|") j++;
      n = j - i;
    } else if (s.startsWith("/*")) {
      j = i;
      while (j < lines.length && !lines[j].includes("*/")) j++;
      n = j - i - 1;
      j++;
    }
    if (n > 3) {
      console.log(`${f}:${i + 1} (${n} lines) ${s.slice(0, 70)}`);
      count++;
    }
    i = j;
  }
}
console.log(`${count} blocks over 3 lines`);
