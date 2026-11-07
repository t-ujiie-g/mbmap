// DE-9IM patterns as relate_worker takes them. Import-free, for `npm test`.

/**
 * A DE-9IM pattern (`"T*F**FFF*"`) packed for relate_worker: three bits a cell, F 0, `0` 1, `1` 2,
 * `2` 3, T 4, `*` 5; throws unless it has 9 such cells, or when disjoint features match it (a
 * pattern allowing F in all of the interior and boundary cells would list every disjoint pair).
 */
export function packPattern(pattern: string): number {
  const cells = pattern.toUpperCase();
  if (!/^[TF*012]{9}$/.test(cells)) throw new Error(`mbmap: analysis: ${pattern} is not a DE-9IM pattern`);
  if ([0, 1, 3, 4].every((k) => cells[k] === "F" || cells[k] === "*")) {
    throw new Error(`mbmap: analysis: disjoint features match ${pattern}; use relateMatrix for single pairs`);
  }
  return [...cells].reduce((packed, c, k) => packed | ("F012T*".indexOf(c) << (k * 3)), 0);
}
