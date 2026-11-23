---
name: skill-retrospective
description: Use when reflecting on conversation evidence.
---

# Skill Retrospective

Reflect on the current conversation or audit a bounded sample of past conversations. Produce evidence-linked recommendations and proposed diffs, not grades.

For the current conversation, use available context rather than searching session stores or unrelated projects; ask for a bounded export if context is missing. Identify a concrete correction, rework, or verification failure and its outcome. Check the owning instruction before proposing a generalizable fix; prefer code or tooling changes over restating sufficient guidance. Separate evidence from inference, and do not edit instructions, file tickets, or publish transcripts without authorization. Skip the historical sampling steps and continue at attribution.

## 1. Set scope and protect history (past conversations)

1. Identify the executing harness and its available history-search interface. If no bounded interface is available, ask for selected session references or exports. Do not inspect raw local session stores automatically.
2. Use the project scope, time window or maximum session count, and skill set the user already specified. Default to the current repository, broaden to other projects only within the authorized scope, and ask only for unresolved scope needed to keep the sample bounded (including whether global skills are in scope).
3. Keep transcript material local. Do not upload it, include secrets, or create a shareable artifact unless explicitly requested. Use a fresh private temporary directory outside repositories if scratch files are necessary.

Use bounded session search rather than scanning all history by default. State the selected scope, sampling method, exclusions, and evidence gaps.

## 2. Collect evidence (past conversations)

1. Inventory the skills in scope and read only the skills implicated by sampled conversations.
2. Search for concrete failure signals: repeated user correction, avoidable rework, redundant tool use, late or missing verification, wrong-file edits, and shipped defects.
3. Record successful skill use only as context. Reading or invoking a skill proves use, not causation or effectiveness.
4. Mark code quality as `insufficient evidence` when the resulting change or authoritative validation is unavailable. Do not convert missing evidence into a positive or negative result.

For each candidate issue, capture:

- session reference and bounded supporting evidence;
- concrete failure and impact;
- applicable skill or other owning instruction surface;
- whether the relevant instruction was absent, wrong, underspecified, or already sufficient.

## 3. Attribute before recommending

Cluster evidence by root cause and prioritize by frequency and severity. Propose a skill change only when all are true:

- a concrete instruction is missing, wrong, or underspecified;
- the owning skill or instruction surface is clear;
- the proposed rule would likely have prevented the observed failure;
- the gap recurs, or one severe occurrence proves a missing contract.

Do not propose a skill change when the existing instruction already required the correct behavior, the evidence is model variance, the real fix belongs to code or infrastructure, or the only edit would restate existing guidance. No justified change is a valid outcome.

## 4. Draft the smallest change

1. State the intended behavioral rule and owning surface in one sentence.
2. Read the current skill.
3. Prefer replacing existing guidance over appending another paragraph.
4. Draft the complete proposed file or a minimal unified diff outside the installed skill.
5. Do not modify installed skills without explicit user approval.

## 5. Report

Do not assign numeric grades or composite scores. Report:

- scope and sample limitations;
- up to three highest-impact findings;
- evidence and confidence for each finding;
- smallest proposed skill change and diff, when justified;
- reasons no change was proposed for rejected candidates;
- residual privacy, sampling, and attribution risks.

Keep quoted transcript text to the minimum needed to support a finding.
