// Command-line arguments of the bench scripts.

/** The value of `--key=value`, else `fallback`. */
export const arg = (key, fallback) => process.argv.find((a) => a.startsWith(`--${key}=`))?.split("=")[1] ?? fallback;
