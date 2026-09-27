---
name: blast-radius
description: Assess what a named change could break beyond its diff, with evidence for the safety assumptions.
---

# Blast radius

Use when asked “what could this break?” for a specific diff or proposed change. This is a read-only assessment, not approval to write a repro, change code, or ship.

1. Pin the comparison or named snapshot. Read the changed behavior and follow callers and downstream consumers, including data formats, platform variants, and pinned dependencies where relevant. Search alone does not establish that a path is safe.
2. Name the one or two facts on which safety depends. For each, distinguish source evidence, a traced failure path, an executed check, and behavior observed in the real application. Run a safe check only when authorized and feasible; otherwise mark the fact unverified.
3. Report evidence-backed risks with exact paths and concrete failure conditions. Separate checked-and-cleared risks from unknowns; do not invent callers or pad with hypothetical defects.
4. Recommend the smallest check that would settle each material unknown. Leave code reviews under the governing finding format and leave merges under the governing delivery policy.
