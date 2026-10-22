# Benchmark interpretation and follow-through

Paths below are relative to this reference directory.

## Close the decision and choose the next target

Translate the result only as far as its measured boundary. A negative natural-selection delegation result supports removing default encouragement or exposure; it does not support deleting explicit orchestration capability without the separate explicit-orchestration supplement. When authorized to apply the verdict, change the narrowest production policy, leave one focused regression assertion, deploy it through the owning configuration path, read back the live behavior, and inspect the final diff for unrelated mutable-config backflow.

After closing a benchmark, distinguish “no further action for this decision” from “no other benchmark targets.” If asked what is next, inventory completed reports and unresolved decision boundaries, then rank candidates by expected decision leverage. Prefer a policy or prompt ablation that affects every run over another expensive replication of an already-covered natural-selection question. State the concrete configuration decision each candidate could change; skip experiments whose outcome would not alter behavior.

## Zero-selection interpretation

A natural-selection matrix with `0/N` candidate calls is still useful, but for a narrower decision:

- It measures **default-list adoption/exposure**, not the candidate's utility when invoked.
- Across a substantial representative matrix, zero selection plus tied correctness is operational evidence that the candidate does not earn default exposure. For a default-configuration decision, prefer removing it while retaining an explicit/on-demand path.
- Do not treat stochastic wall/token/call differences between no-call variants as evidence that the candidate itself helped or hurt task execution.
- Do not write “no evidence supports removal” merely because forced-use utility was unmeasured. State both conclusions: natural use was absent; forced-use utility remains unknown.
- When useful, report the exact one-sided binomial upper bound for the per-run selection rate (for `0/N` at 95% confidence: `1 - 0.05^(1/N)`).
- If utility matters independently, run a separately labeled forced-use or discoverability supplement; never mix it into the natural production matrix.
- Inspect the activation model before prescribing code changes. A globally imported extension that disables its tools at `session_start` and contributes zero active schema until an explicit command is already runtime-on-demand. Compare residual import latency/RSS with the cross-platform launcher and deployment complexity of relocating it; when the residual is negligible, no code change may be the smallest correct result. Remove only suggestion policy when the intended behavior is strictly user-invoked.

For bounded experiment-loop extensions, load `autoresearch-extension-ablation.md` for a Git/JJ matrix, forced-use evidence, child accounting, and activation-state interpretation.

When one resource improves while another regresses, quantify the exchange rate:

- tokens saved per added second;
- cost saved per added second;
- seconds saved per additional token/cost when time improves instead.

Interpret the result using the user's stated priority. Do not reject a candidate solely for a small latency or complexity penalty when token cost is the user's dominant concern.

## Prompt and cache accounting

Provider token schemas differ. Preserve all fields, inspect their semantics from raw events, and make overlap explicit:

- If `input` excludes cache activity: `prompt-accounted = input + cache_read + cache_write`; `total = prompt-accounted + output`.
- If `input` already includes cached tokens, as in Codex cumulative usage: `uncached = input - cached_input`; `total = input + output`. Never add `cached_input` to `input` again.

Add a verifier assertion for the chosen relationship and use the same formula in summaries, paired deltas, and cost calculations. Repeated system instructions compound across provider turns even when cached. Separate byte size from provider token count. A shorter output is not a total-token saving if repeated prompt context dominates.
