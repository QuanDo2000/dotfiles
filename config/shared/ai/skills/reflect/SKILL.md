---
name: reflect
description: Review this conversation for a reusable lesson and propose a bounded skill or instruction change.
---

# Reflect

Use for “reflect” on the current conversation. For a sample of past conversations, use `skill-retrospective` instead. Do not search raw session stores or unrelated projects to reconstruct this conversation; if context is missing, ask for a bounded export.

1. Identify a concrete correction, rework, or verification failure in the conversation, with its outcome. Reading a skill is not evidence that it helped.
2. Check the owning instruction and whether it already required the right behavior. Prefer fixing code or tooling over restating a sufficient rule. A one-off without a generalizable cause does not earn a skill edit.
3. If a gap remains, propose the smallest change to one owning file. Prefer replacement over appended rules; explain how it would have prevented the failure. Separate evidence from inference.
4. Report the proposal and rejected candidates. Do not edit instructions, file a ticket, or publish transcript material without authorization.
