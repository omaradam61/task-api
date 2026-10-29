const { test, before, after } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

// Use a throwaway data directory so tests never touch real data
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'taskapi-'));
const app = require('../src/app');

let server;
let base;

before(() => new Promise((resolve) => {
  server = app.listen(0, () => {
    base = `http://127.0.0.1:${server.address().port}`;
    resolve();
  });
}));

after(() => new Promise((resolve) => server.close(resolve)));

test('GET /health returns ok', async () => {
  const res = await fetch(`${base}/health`);
  assert.strictEqual(res.status, 200);
  assert.deepStrictEqual(await res.json(), { status: 'ok' });
});

test('GET / returns a welcome message', async () => {
  const body = await (await fetch(`${base}/`)).json();
  assert.match(body.message, /DevOps Task API/);
});

test('GET /version returns a version string', async () => {
  const body = await (await fetch(`${base}/version`)).json();
  assert.strictEqual(typeof body.version, 'string');
});

test('POST /tasks creates a task', async () => {
  const res = await fetch(`${base}/tasks`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title: 'Learn CI/CD' }),
  });
  assert.strictEqual(res.status, 201);
  assert.strictEqual((await res.json()).title, 'Learn CI/CD');
});

test('POST /tasks without a title returns 400', async () => {
  const res = await fetch(`${base}/tasks`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  });
  assert.strictEqual(res.status, 400);
});
