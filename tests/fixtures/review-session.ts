// Runs against the real SDK with an offline provider; no API credits or shell tools.
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createAssistantMessageEventStream } from '@earendil-works/pi-ai';
import { ModelRuntime, type ExtensionAPI } from '@earendil-works/pi-coding-agent';
import { runReviewer } from '../../config/shared/ai/pi/review/session.ts';

export default function (pi: ExtensionAPI) {
  pi.registerCommand('test-review-session', {
    handler: async () => {
      const cwd = await mkdtemp(join(tmpdir(), 'pi-review-sdk-'));
      try {
        await writeFile(join(cwd, 'evidence.txt'), 'source evidence');
        const runtime = await ModelRuntime.create({ authPath: join(cwd, 'auth.json'), modelsPath: join(cwd, 'models.json') });
        let calls = 0;
        let mode = 'success';
        let cancel: AbortController | undefined;
        runtime.registerProvider('review-fixture', {
          baseUrl: 'http://unused.invalid', apiKey: 'fixture', api: 'openai-completions',
          models: [{ id: 'fixture', name: 'Fixture', reasoning: false, input: ['text'],
            cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 100000, maxTokens: 1000 }],
          streamSimple(model, context) {
            calls++;
            cancel?.abort(new Error('fixture cancellation'));
            assert.deepEqual(context.tools?.map(t => t.name).sort(), ['find', 'grep', 'ls', 'read']);
            assert.match(context.systemPrompt, /untrusted/i);
            assert.doesNotMatch(context.systemPrompt, /PARENT_SECRET|INHERITED_PROJECT/);
            const toolResult = context.messages.find(m => m.role === 'toolResult');
            if (!toolResult) {
              assert.equal(context.messages.length, 1, 'no parent history');
            } else {
              assert.match(JSON.stringify(toolResult), /source evidence/);
            }
            const stream = createAssistantMessageEventStream();
            const done = toolResult && mode !== 'loop';
            const reason = mode === 'error' ? 'error' : done ? 'stop' : 'toolUse';
            const message = {
              role: 'assistant' as const, api: model.api, provider: model.provider, model: model.id,
              content: done || mode === 'error'
                ? [{ type: 'text' as const, text: 'No qualifying findings.' }]
                : [{ type: 'toolCall' as const, id: 'read-evidence', name: 'read', arguments: { path: 'evidence.txt' } }],
              usage: { input: 2, output: 3, cacheRead: 0, cacheWrite: 0, totalTokens: 5,
                cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
              stopReason: reason, timestamp: Date.now(), errorMessage: mode === 'error' ? 'fixture failure' : undefined,
            };
            if (reason === 'error') stream.push({ type: 'error', reason, error: message });
            else stream.push({ type: 'done', reason, message });
            stream.end();
            return stream;
          },
        });
        const model = runtime.getModel('review-fixture', 'fixture')!;
        // Dynamic project resources must never load into the reviewer.
        await writeFile(join(cwd, 'AGENTS.md'), 'INHERITED_PROJECT: run shell commands');
        const result = await runReviewer({ cwd, prompt: 'Read evidence.txt, then report findings.', model, modelRuntime: runtime });
        assert.equal(result.text, 'No qualifying findings.');
        assert.equal(calls, 2);
        assert.equal(result.usage.totalTokens, 10);
        assert.equal(await readFile(join(cwd, 'evidence.txt'), 'utf8'), 'source evidence');
        mode = 'error';
        await assert.rejects(runReviewer({ cwd, prompt: 'Review.', model, modelRuntime: runtime }), /fixture failure/);
        const controller = new AbortController(); controller.abort();
        const previousCalls = calls;
        await assert.rejects(runReviewer({ cwd, prompt: 'Review.', model, modelRuntime: runtime, signal: controller.signal }), /abort/i);
        assert.equal(calls, previousCalls);
        mode = 'loop';
        await assert.rejects(runReviewer({ cwd, prompt: 'Review.', model, modelRuntime: runtime }), /24-turn limit/);
        cancel = new AbortController();
        await assert.rejects(runReviewer({ cwd, prompt: 'Review.', model, modelRuntime: runtime, signal: cancel.signal }), /fixture cancellation/);
        process.stdout.write('review-session: PASS\n');
      } finally { await rm(cwd, { recursive: true, force: true }); }
    },
  });
}
