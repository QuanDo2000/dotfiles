import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { prepareReview, verifyReview } from '../../config/shared/ai/pi/review/target.ts';

test('review binds a clean checkout to exact commits without executing diff helpers', async () => {
  const cwd = mkdtempSync(join(tmpdir(), 'pi-review-test-'));
  const git = (...args) => execFileSync('git', args, { cwd, encoding: 'utf8' }).trim();
  try {
    git('init', '-q');
    git('config', 'user.name', 'Test');
    git('config', 'user.email', 'test@example.invalid');
    git('config', 'commit.gpgsign', 'false');
    writeFileSync(join(cwd, 'code.txt'), 'before\n');
    git('add', '.'); git('commit', '-qm', 'base');
    const base = git('rev-parse', 'HEAD');
    writeFileSync(join(cwd, 'code.txt'), 'after\n');
    git('commit', '-qam', 'head');
    const head = git('rev-parse', 'HEAD');
    git('config', 'diff.external', 'must-not-execute');
    const review = await prepareReview(cwd, base, head);
    assert.equal(review.base, base);
    assert.equal(review.head, head);
    assert.match(review.diff, /\+after/);
    await verifyReview(review);
    await assert.rejects(prepareReview(cwd, head, head), /empty/i);
    await assert.rejects(prepareReview(cwd, base, base), /HEAD/i);
    await assert.rejects(prepareReview(cwd, '--help', head), /commit/i);
    writeFileSync(join(cwd, 'code.txt'), 'dirty\n');
    await assert.rejects(verifyReview(review), /clean/i);
    await assert.rejects(prepareReview(cwd, base, head), /clean/i);
    git('restore', 'code.txt');
    writeFileSync(join(cwd, 'untracked.txt'), 'new');
    await assert.rejects(prepareReview(cwd, base, head), /clean/i);
  } finally { rmSync(cwd, { recursive: true, force: true }); }
});
