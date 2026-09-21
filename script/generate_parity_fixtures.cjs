// Generate with the unpacked official @typesafe-ai/sdk v0.6.0 release artifact:
// node script/generate_parity_fixtures.cjs /path/to/package > spec/fixtures/js-0.6.0.json
const path = require('node:path');
const root = path.resolve(process.argv[2]);
const pkg = require(path.join(root, 'package.json'));
if (pkg.version !== '0.6.0') throw new Error('Expected official SDK 0.6.0');
const sdk = require(path.join(root, 'dist/index.cjs'));
(async () => {
  const questions = {
    yes: sdk.noul('Is it urgent?', {true: 'urgent', false: 'routine'}),
    category: sdk.choice(null, {billing: null, other: {description: 'other'}}),
    rating: sdk.score('Priority?', [null, 'medium', ['high']]),
  };
  let request;
  const client = new sdk.TypeSafeClient({apiKey: 'test', fetch: async (url, init) => {
    request = {url, method: init.method, body: JSON.parse(init.body)};
    return new Response(JSON.stringify({model: 'jev-latest', answers: {}, usage: {}}), {
      headers: {'content-type': 'application/json', 'x-typesafe-request-id': 'req-parity'},
    });
  }});
  const result = await client.systemOne({state: {document: 'example'}, questions,
    future_option: null, nested: {enabled: true}}).withResponse();
  const errors = [];
  for (const status of [400, 401, 403, 404, 408, 409, 422, 429, 500, 503, 599]) {
    for (const body of [{error: 'failure'}, {detail: [{loc: ['body', 'questions', 'q'], msg: 'invalid'}]}, {noise: 'x'.repeat(250)}]) {
      const error = sdk.APIError.fromResponse(status, body, new Headers({'x-typesafe-request-id': 'req-error', 'retry-after-ms': '12.5'}));
      errors.push({status, body, name: error.name, message: error.message,
        request_id: error.requestId, ...(status === 429 ? {retry_after_ms: error.retryAfterMs} : {})});
    }
  }
  const retry_headers = [];
  for (const headers of [{'retry-after-ms':'12.5'}, {'retry-after-ms':'2e2'}, {'retry-after':'0.0005'},
    {'retry-after':'-1'}, {'retry-after-ms':'invalid', 'retry-after':'1.5'}, {'retry-after':'garbage'},
    {'retry-after-ms':'', 'retry-after':'9'}, {'retry-after':'Infinity'}]) {
    const error = sdk.APIError.fromResponse(429, {}, new Headers(headers));
    retry_headers.push({headers, milliseconds: error.retryAfterMs ?? null});
  }
  process.stdout.write(JSON.stringify({upstream: {version: pkg.version,
    commit: '66880ccded6cb642dc1809620c2b108c33730214'}, questions, request,
    response_metadata: {status: result.response.status, request_id: result.requestId}, errors, retry_headers}, null, 2) + '\n');
})();
