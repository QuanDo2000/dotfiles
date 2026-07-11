import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const guidance =
  "Code discovery: prefer codebase-memory-mcp tools (search_graph, trace_path, " +
  "get_code_snippet, query_graph, search_code) over grep/file reads; run " +
  "index_repository first if the project is not indexed.";

export default function codebaseMemoryGuidance(pi: ExtensionAPI) {
  pi.on("before_agent_start", async (event) => ({
    systemPrompt: `${event.systemPrompt}\n\n${guidance}`,
  }));
}
