import assert from 'node:assert/strict';
import * as piAI from '@earendil-works/pi-ai';
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';
import registerReview from '../../config/shared/ai/pi/review/index.ts';

export default function (pi: ExtensionAPI) {
  registerReview(pi);
  let childCalls = 0;
  let parentSession: string;
  pi.on('session_start', (_event, ctx) => { parentSession = ctx.sessionManager.getSessionId(); });
  pi.on('tool_result', (event, ctx) => {
    assert.equal(ctx.sessionManager.getSessionId(), parentSession);
    if (event.toolName === 'review') assert.equal(event.isError, false, JSON.stringify(event.content));
  });
  pi.registerProvider('review-tool-fixture', {
    baseUrl: 'http://unused.invalid', apiKey: 'fixture', api: 'openai-completions',
    models: [{ id: 'fixture', name: 'Fixture', reasoning: false, input: ['text'],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 100000, maxTokens: 1000 }],
    streamSimple(model, context) {
      const systemPrompt = context.systemPrompt ?? piAI.getCurrentSystemPrompt(context.messages);
      const child = systemPrompt.startsWith('# Independent code review');
      const results = context.messages.filter(m => m.role === 'toolResult');
      if (child) {
        childCalls++;
        assert.deepEqual(context.messages.filter(m => m.role !== 'system').map(m => m.role), ['user']);
        const tools = context.tools ?? piAI.getCurrentTools(context.messages);
        assert.deepEqual(tools.map(t => t.name).sort(), ['find', 'grep', 'ls', 'read']);
      } else if (results.length === 2) {
        assert.equal(childCalls, 1, 'identical completed review must be reused');
        assert.match(JSON.stringify(results[1]), /Reused completed review/);
        assert.match(JSON.stringify(results[0]), /Reviewed /);
      }
      const done = child || results.length === 2;
      const stream = piAI.createAssistantMessageEventStream();
      const reason = done ? 'stop' : 'toolUse';
      stream.push({ type: 'done', reason, message: {
        role: 'assistant', api: model.api, provider: model.provider, model: model.id,
        content: done ? [{ type: 'text', text: child ? 'No qualifying findings.' : 'review-tool: PASS' }]
          : [{ type: 'toolCall', id: `review-${results.length}`, name: 'review', arguments: {
            cwd: process.env.REVIEW_TEST_CWD, base: process.env.REVIEW_TEST_BASE, head: process.env.REVIEW_TEST_HEAD,
          } }],
        usage: { input: 1, output: 1, cacheRead: 0, cacheWrite: 0, totalTokens: 2,
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
        stopReason: reason, timestamp: Date.now(),
      } });
      stream.end();
      return stream;
    },
  });
}
