# Subagent Portfolio Audit

Use evidence from real activity before recommending role removal. This is a read-only audit until configuration changes are approved; there is no mandatory role roster.

## Bound the evidence

Agree on projects and a time/session limit. Use a bounded history interface or selected exports, not an automatic raw-session scan. Keep transcripts local, redact secrets, and disclose sampling gaps.

Collect parent launch/wait/steer/stop/completion events; child role/model, status, duration, tool errors, usage, and final handoff; and resolved routing/lifecycle limits. Count completed handoffs, duplicate waves on unchanged targets, tool/output share, and waits per child. Separate launch failures from owner-process loss and tool errors from heuristic error-text matches.

## Attribute before cutting

- Successful completion alone does not prove quality or unique value; inspect whether the result satisfied its task.
- High useful output but excessive share suggests narrower scope or less fan-out before role removal.
- Low use with a unique safety/capability boundary can justify retention. Low use with overlapping capability is a candidate for reversible disablement, not automatic deletion.
- Useful evidence without a summary indicates a lifecycle/handoff problem. A wait is not waste when same-turn synthesis truly depends on it.

Follow the owning orchestration skill for reviewer count, evidence packets, and parent verification rather than duplicating those rules. Choose the smallest correction that addresses the measured cause; do not reduce concurrency, change models, or invent roles merely to hit a template.

## Verify authorized changes

Record baseline and a representative re-audit window. Parse effective config through the runtime; confirm discovery, intended models/tools, and the smallest relevant smoke/check. Verify source and live configuration separately and avoid broad activation that would include unrelated dirty work.

Disable before deleting; check dependencies and retain rollback until the observation period supports removal. Re-measure completion quality, handoffs, and cost before claiming improvement. Missing quality evidence is a limitation, not proof that a role is useful or useless.
