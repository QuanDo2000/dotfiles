// Opt-in live-network regression: node (or bun) tests/ai/tls-distrust-smoke.mjs
// Both the runtime's Node-compatible HTTPS API and native fetch must reject.
import assert from 'node:assert/strict';
import https from 'node:https';

const compromised = 'https://dv-g3b-emudhra.we-have-a-problem.com/';
const normal = 'https://nodejs.org/';
const certificateErrors = new Set([
  'CERT_REVOKED',
  'UNABLE_TO_GET_ISSUER_CERT_LOCALLY',
  'UNABLE_TO_VERIFY_LEAF_SIGNATURE',
]);
const transports = {
  https: url => new Promise((resolve, reject) => {
    const request = https.get(url, response => {
      response.resume();
      resolve(response.statusCode);
    });
    request.setTimeout(15000, () => request.destroy(new Error('HTTPS timeout')));
    request.on('error', reject);
  }),
  fetch: async url => {
    const response = await fetch(url, { signal: AbortSignal.timeout(15000) });
    await response.body?.cancel();
    return response.status;
  },
};

for (const [name, get] of Object.entries(transports)) {
  let error;
  try {
    await get(compromised);
  } catch (caught) {
    error = caught;
  }
  const code = error?.cause?.code ?? error?.code;
  assert(certificateErrors.has(code), `${name}: expected certificate rejection, got ${error ?? 'HTTP success'}`);
  console.log(`${name}: compromised chain rejected (${code})`);
  const status = await get(normal);
  assert(status >= 200 && status < 400, `${name}: normal HTTPS returned ${status}`);
  console.log(`${name}: normal HTTPS succeeded (${status})`);
}
