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
    rating: sdk.score('Priority?', ['low', 'medium', ['high']]),
  };
  const wireResult = {
    model: 'jev-latest',
    answers: {
      yes: {type: 'noul', noul: 0.08},
      category: {type: 'choice', choice: 'billing', confidence: 0.5,
        probabilities: {billing: 0.8, other: 0.2}},
      rating: {type: 'score', score: 1.35, confidence: 0.3,
        legend: {'0': 'low', '1': 'medium', '2': ['high']},
        probabilities: {'0': 0.1, '1': 0.45, '2': 0.45}},
    },
    usage: {input_tokens: 23, output_tokens: 12},
  };
  let request;
  const client = new sdk.TypeSafeClient({apiKey: 'test', fetch: async (url, init) => {
    request = {url, method: init.method, body: JSON.parse(init.body)};
    return new Response(JSON.stringify(wireResult), {
      headers: {'content-type': 'application/json', 'x-typesafe-request-id': 'req-parity'},
    });
  }});
  const result = await client.systemOne({state: {document: 'example'}, questions,
    future_option: null, nested: {enabled: true}}).withResponse();
  const errors = [];
  for (const status of [400, 401, 403, 404, 408, 409, 422, 429, 500, 503, 599]) {
    for (const body of [{error: ''}, {error: {message: ''}}, {message: ''}, {detail: ''}, {error: 'failure'}, {detail: [{loc: ['body', 'questions', 'q'], msg: 'invalid'}]}, {noise: 'x'.repeat(250)}]) {
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
  const retry_flags = [];
  for (const field of ['respectRetryAfter', 'apiConnectionError', 'apiTimeoutError']) {
    for (const value of [null, false, true]) {
      const configured = new sdk.TypeSafeClient({apiKey: 'test', retry: {[field]: value}});
      retry_flags.push({field: field.replace(/[A-Z]/g, c => `_${c.toLowerCase()}`),
        value, resolved: configured.retry[field]});
    }
  }
  process.stdout.write(JSON.stringify({upstream: {version: pkg.version,
    commit: '66880ccded6cb642dc1809620c2b108c33730214'}, questions, request, result: result.data, retry_flags,
    response_metadata: {status: result.response.status, request_id: result.requestId}, errors, retry_headers}, null, 2) + '\n');
})();
