import { afterEach, expect, it, vi } from 'vitest';
import { fauxAssistantMessage } from '@earendil-works/pi-ai';
import { createHarness, getUserTexts, type Harness } from './harness.ts';
const harnesses: Harness[] = [];
afterEach(() => { vi.restoreAllMocks(); while (harnesses.length) harnesses.pop()!.cleanup(); });
function deferred() { let resolve!: () => void; const promise = new Promise<void>(r => { resolve = r; }); return {promise, resolve}; }
function seed(h: Harness) {
 const model = h.getModel();
 h.sessionManager.appendMessage({role:'user', content:[{type:'text',text:'x'.repeat(500)}],timestamp:1});
 h.sessionManager.appendMessage({...fauxAssistantMessage('y'.repeat(200),{timestamp:2}),api:model.api,provider:model.provider,model:model.id,usage:{input:100,output:0,cacheRead:0,cacheWrite:0,totalTokens:100,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}}});
 h.session.agent.state.messages = h.sessionManager.buildSessionContext().messages;
}
for (const mode of ['success','error','abort','cancel']) it(`compaction_end exposes cleared state: ${mode}`, async () => {
 const h = await createHarness({settings:{compaction:{keepRecentTokens:1}},extensionFactories:[pi => {
  pi.on('session_before_compact', event => mode === 'cancel' ? {cancel:true} : mode === 'success' ? {compaction:{summary:'extension summary',firstKeptEntryId:event.preparation.firstKeptEntryId,tokensBefore:event.preparation.tokensBefore}} : undefined);
 }]}); harnesses.push(h); seed(h);
 if(mode==='error') vi.spyOn(h.session.modelRuntime,'getAuth').mockRejectedValue(new Error('retirement synthetic auth failure'));
 const observed: unknown[]=[];
 h.session.subscribe(event => { if(event.type==='compaction_start' && mode==='abort') h.session.abortCompaction(); if(event.type==='compaction_end') observed.push({compacting:h.session.isCompacting,aborted:event.aborted,error:event.errorMessage,result:!!event.result}); });
 const returned=await (h.session as any)._runAutoCompaction('threshold',false);
 console.log(JSON.stringify({mode,returned,observed,idleAfter:h.session.isIdle,fauxCalls:h.faux.state.callCount}));
 expect(observed).toHaveLength(1); expect(observed[0]).toMatchObject({compacting:false,aborted:mode==='abort'||mode==='cancel',result:mode==='success'}); expect(h.session.isIdle).toBe(true);
});
it('late steering is delivered after the native no-continuation settlement decision', async () => {
 const reached=deferred(),release=deferred(),inputEntered=deferred(),inputRelease=deferred();
 const h=await createHarness({settings:{compaction:{enabled:false},retry:{enabled:false}},extensionFactories:[pi=>{ pi.on('input',async event=>{if(event.text==='late steering'){inputEntered.resolve();await inputRelease.promise;} return {action:'continue'};}); }]});harnesses.push(h);
 h.setResponses([fauxAssistantMessage('first'),fauxAssistantMessage('second')]);
 const native=(h.session as any)._runBeforeSettleBoundary.bind(h.session);let first=true;
 // Scheduling barrier only: call owning native method and preserve its exact result.
 vi.spyOn(h.session as any,'_runBeforeSettleBoundary').mockImplementation(async()=>{const result=await native();if(first){first=false;reached.resolve();await release.promise;}return result;});
 const originalRun=h.session.prompt('initial');await reached.promise;
 expect(h.session.isStreaming).toBe(true);expect(h.session.agent.state.isStreaming).toBe(false);
 let classification:string|undefined;
 const late=h.session.prompt('late steering',{streamingBehavior:'steer',preflightResult:r=>{classification=r;}});
 await inputEntered.promise;inputRelease.resolve();await new Promise(r=>setImmediate(r));release.resolve();
 await Promise.all([originalRun,late]);await h.session.waitForIdle();
 const observed={classification,texts:getUserTexts(h),pending:h.session.pendingMessageCount,coreQueued:h.session.agent.hasQueuedMessages(),idle:h.session.isIdle,fauxCalls:h.faux.state.callCount,settled:h.eventsOfType('agent_settled').length};
 console.log(JSON.stringify({mode:'late-steering',...observed}));
 expect(observed).toMatchObject({classification:'started',texts:['initial','late steering'],pending:0,coreQueued:false,idle:true,fauxCalls:2,settled:2});
});
