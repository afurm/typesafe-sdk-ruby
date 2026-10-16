// Generate with the unpacked official @typesafe-ai/sdk v0.7.0 release artifact (Node.js 22.15+):
// node script/generate_parity_fixtures.cjs /path/to/package > spec/fixtures/js-0.7.0.json
const path = require('node:path');
const {zstdDecompressSync} = require('node:zlib');
const root = path.resolve(process.argv[2]);
const pkg = require(path.join(root, 'package.json'));
if (pkg.version !== '0.7.0') throw new Error('Expected official SDK 0.7.0');
const sdk = require(path.join(root, 'dist/index.cjs'));
const PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
const JPEG = '/9j/AA==';

// Record each request as sent: headers, the JSON (or multipart `request` part), and file parts.
const recorder = (wireResult) => {
  const requests = [];
  const fetch = async (url, init) => {
    const headers = new Headers(init.headers);
    let raw = init.body;
    if (headers.get('content-encoding') === 'zstd') raw = zstdDecompressSync(init.body);
    let body;
    let parts;
    if (headers.get('content-type').startsWith('multipart/form-data')) {
      const form = await new Response(raw instanceof Blob ? raw : new Blob([raw]),
        {headers: {'content-type': headers.get('content-type')}}).formData();
      body = JSON.parse(form.get('request'));
      parts = [];
      for (const [name, value] of form) {
        if (name === 'request') continue;
        parts.push({name, filename: value.name, content_type: value.type,
          data_base64: Buffer.from(await value.arrayBuffer()).toString('base64')});
      }
    } else {
      body = JSON.parse(typeof raw === 'string' ? raw : Buffer.from(raw).toString('utf8'));
    }
    requests.push({url, method: init.method, content_type: headers.get('content-type').split(';')[0],
      content_encoding: headers.get('content-encoding'), body, ...(parts ? {parts} : {})});
    return new Response(JSON.stringify(wireResult), {
      headers: {'content-type': 'application/json', 'x-typesafe-request-id': 'req-parity'},
    });
  };
  return {fetch, requests};
};

// Replace generated image references, which are random, with stable labels.
const normalize = (value, labels) => {
  let json = JSON.stringify(value);
  for (const [label, asset] of Object.entries(labels)) json = json.replaceAll(String(asset), `<ref:${label}>`);
  return JSON.parse(json);
};

const message = async (call) => {
  try { await call(); } catch (err) { return err.message; }
  throw new Error('Expected an error');
};

(async () => {
  const questions = {
    yes: sdk.noul('Is it urgent?', {true: 'urgent', false: 'routine'}),
    category: sdk.choice(null, {billing: null, other: {description: 'other'}}),
    rating: sdk.score('Priority?', ['low', 'medium', ['high']]),
    where: sdk.box('The damaged area'),
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
      where: {type: 'box', box: {top: 0.1, bottom: 0.6, left: 0.25, right: 0.75}, confidence: null},
    },
    usage: {input_tokens: 23, output_tokens: null},
  };
  const main = recorder(wireResult);
  let client = new sdk.TypeSafeClient({apiKey: 'test', fetch: main.fetch});
  const result = await client.systemOne({state: {document: 'example', score: NaN,
    limits: [1, Infinity, -Infinity]}, questions, future_option: null, nested: {enabled: true}}).withResponse();

  // Assets: names, images placed in content, withAssets text, and an image under a name and its reference.
  const assets = recorder(wireResult);
  client = new sdk.TypeSafeClient({apiKey: 'test', fetch: assets.fetch});
  await client.systemOne({
    state: 'Inspect <a> and <b>',
    questions: {q: sdk.noul('Is <a> like <b>?')},
    assets: {'<a>': sdk.Image.fromBase64(PNG), '<b>': sdk.Image.fromBase64(JPEG)},
  });
  const photo = sdk.Image.fromBase64(PNG);
  const listing = sdk.Image.fromBase64(JPEG);
  const gif = sdk.image(new TextEncoder().encode('GIF89a'));
  await client.systemOne({
    state: {photo, caption: sdk.withAssets`Inspect ${photo} beside ${listing}`, other: gif},
    questions: {
      q1: sdk.noul([photo]),
      q2: sdk.score(sdk.withAssets`Rate ${listing} (${1})`, ['bad', 'good']),
      q3: sdk.noul(sdk.withAssets.join(['Is', photo, 'clear?'], ' ')),
      q4: sdk.box(listing),
    },
    assets: {'<photo>': photo},
  });
  await client.systemOne({state: `Compare <photo> with ${photo}`, questions: {q: sdk.noul('?')},
    assets: {'<photo>': photo}});
  const asset_requests = normalize(assets.requests, {photo, listing, gif});

  const joined = sdk.withAssets.join([photo, 'and', sdk.withAssets`${listing}`, null, 1], ' ');
  const join_texts = normalize({
    spaced: joined.text,
    spaced_assets: joined.assets.map(String),
    default_separator: sdk.withAssets.join([photo, listing]).text,
    empty: sdk.withAssets.join([]).text,
  }, {photo, listing});

  const asset_errors = normalize({
    unreferenced: await message(() => client.systemOne({state: 'Inspect <photo>', questions: {q: sdk.noul('?')},
      assets: {'<photo>': photo, '<unused>': sdk.Image.fromBase64(PNG), '<"quoted">': photo}})),
    last_name_wins: await message(() => client.systemOne({state: photo, questions: {q: sdk.noul('?')},
      assets: {'<first>': photo, '<second>': photo}})),
    missing_reference: await message(() => client.systemOne({state: `Inspect ${photo}`,
      questions: {q: sdk.noul('?')}})),
    empty_image: await message(() => sdk.image(new Uint8Array(0))),
    invalid_base64: await message(() => sdk.Image.fromBase64('not base64!')),
    data_url: await message(() => sdk.Image.fromBase64(`data:image/png;base64,${PNG}`)),
    empty_base64: await message(() => sdk.Image.fromBase64('')),
  }, {photo});

  const base64 = [];
  for (const text of [PNG, ' iVBO Rw0K\n', 'AQID', 'AQI', 'AQ==', 'AQ', 'AQ=', 'A', 'AQ=A', '====']) {
    try {
      base64.push({text, hex: Buffer.from(sdk.Image.fromBase64(text).data).toString('hex')});
    } catch (err) {
      base64.push({text, error: err.message});
    }
  }

  const compression = [];
  for (const state of ['x', 'x'.repeat(1024), 'é'.repeat(512)]) {
    const recorded = recorder(wireResult);
    await new sdk.TypeSafeClient({apiKey: 'test', fetch: recorded.fetch})
      .systemOne({state, questions: {q: sdk.noul('?')}});
    compression.push({state_length: state.length, state_char: state[0],
      content_encoding: recorded.requests[0].content_encoding,
      state_received: recorded.requests[0].body.state === state});
  }

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
    commit: 'b844cd1aca12855a5d24a2df52a1401c86e7d37a'}, questions, request: main.requests[0], result: result.data,
    retry_flags, response_metadata: {status: result.response.status, request_id: result.requestId},
    asset_requests, join_texts, asset_errors, base64, compression, errors, retry_headers}, null, 2) + '\n');
})();
