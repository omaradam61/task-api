const express = require('express');
const os = require('node:os');
const store = require('./store');
const pkg = require('../package.json');

const VERSION = process.env.APP_VERSION || pkg.version;
const ENVIRONMENT = process.env.APP_ENV || 'development';

const app = express();
app.use(express.json());

let tasks = store.load();

app.get('/', (req, res) => {
  res.json({ message: 'Welcome to the DevOps Task API', version: VERSION });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.get('/version', (req, res) => {
  res.json({ version: VERSION, environment: ENVIRONMENT, hostname: os.hostname() });
});

app.get('/tasks', (req, res) => {
  res.json(tasks);
});

app.post('/tasks', (req, res) => {
  const title = String(req.body?.title ?? '').trim();
  if (!title) {
    return res.status(400).json({ error: 'title is required' });
  }
  const id = tasks.length ? Math.max(...tasks.map((t) => t.id)) + 1 : 1;
  const task = { id, title, done: false };
  tasks.push(task);
  store.save(tasks);
  res.status(201).json(task);
});

// Unknown routes: answer in JSON like the rest of the API
app.use((req, res) => {
  res.status(404).json({ error: 'not found' });
});

// Errors (e.g. malformed JSON bodies): JSON instead of an HTML error page
app.use((err, req, res, next) => {
  const status = err.status || err.statusCode || 500;
  if (status >= 500) console.error(err);
  res.status(status).json({ error: status >= 500 ? 'internal server error' : err.message });
});

module.exports = app;
