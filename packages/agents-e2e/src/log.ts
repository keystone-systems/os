// Logfmt stderr output (NFR-005)

export function emit(
  level: string,
  msg: string,
  fields: Record<string, string> = {},
) {
  const ts = new Date().toISOString();
  let line = `ts=${ts} level=${level} component=e2e msg="${msg}"`;
  for (const [k, v] of Object.entries(fields)) {
    line += ` ${k}="${v}"`;
  }
  console.error(line);
}
