---
name: tdd
description: Use for behavior-changing code or bug fixes.
---

# Focused verification

Follow governing verification, safety, and delivery policy. Before editing, name the observable outcome and credible failures. Reuse existing entry points and checks; add tests only for important uncovered failures.

For bugs, run the same symptom reproducer before and after the fix under equivalent conditions. Preserve baseline failure evidence; disclose when a safe baseline is unavailable.

Batch related edits, check affected behavior, and run required final gates. Do not rerun unchanged expensive checks or claim old results cover new behavior. Inspect actual exits and output; distinguish passed, failed, reused, skipped, and unverified checks.

Keep trials disposable. Reuse retained shared execution tools rather than making one-off harnesses; validate changed safety boundaries through their real entry points.
