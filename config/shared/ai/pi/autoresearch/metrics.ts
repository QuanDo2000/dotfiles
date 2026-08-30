export function isImprovement(candidate: number, accepted: number[], direction: "lower" | "higher"): boolean {
  if (!Number.isFinite(candidate) || accepted.length === 0 || accepted.some((value) => !Number.isFinite(value))) return false;
  const best = direction === "lower" ? Math.min(...accepted) : Math.max(...accepted);
  return direction === "lower" ? candidate < best : candidate > best;
}

export function parseMetrics(output: string): Record<string, number> {
  const metrics: Record<string, number> = Object.create(null) as Record<string, number>;
  const pattern = /^METRIC\s+([A-Za-z][A-Za-z0-9_.-]*)=(-?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?)\s*$/;
  for (const line of output.split(/\r?\n/)) {
    const match = pattern.exec(line.trim());
    if (match) {
      const value = Number(match[2]);
      if (Number.isFinite(value)) metrics[match[1]] = value;
    }
  }
  return metrics;
}
