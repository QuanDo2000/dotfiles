export function isImprovement(candidate: number, accepted: number[], direction: "lower" | "higher"): boolean {
  if (!Number.isFinite(candidate) || accepted.length === 0 || accepted.some((value) => !Number.isFinite(value))) return false;
  const best = direction === "lower" ? Math.min(...accepted) : Math.max(...accepted);
  return direction === "lower" ? candidate < best : candidate > best;
}

export function formatCompletionSummary(
  entries: Array<Record<string, unknown>>,
  metricName: string,
  direction: "lower" | "higher",
  workspacePath: string,
): string {
  const accepted = entries.filter((entry) => entry.status === "baseline" || entry.status === "keep");
  const baseline = accepted.find((entry) => entry.status === "baseline")?.metric;
  const metrics = accepted.map((entry) => entry.metric).filter((metric): metric is number => typeof metric === "number" && Number.isFinite(metric));
  const best = metrics.length === 0 ? null : direction === "lower" ? Math.min(...metrics) : Math.max(...metrics);
  const improvement = typeof baseline === "number" && Number.isFinite(baseline) && baseline !== 0 && best !== null
    ? (direction === "lower" ? baseline - best : best - baseline) / Math.abs(baseline) * 100
    : null;
  return [
    "Autoresearch complete",
    `baseline ${metricName}: ${typeof baseline === "number" ? baseline : "missing"}`,
    `best ${metricName}: ${best ?? "missing"}`,
    `improvement: ${improvement === null ? "n/a" : `${improvement.toFixed(2)}%`}`,
    `accepted experiments: ${accepted.filter((entry) => entry.status === "keep").length}`,
    `workspace: ${workspacePath}`,
  ].join("\n");
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
