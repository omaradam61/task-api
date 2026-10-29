const fs = require('node:fs');
const path = require('node:path');

const dataDir = process.env.DATA_DIR || path.join(__dirname, '..', 'data');
const dataFile = path.join(dataDir, 'tasks.json');

function load() {
  try {
    return JSON.parse(fs.readFileSync(dataFile, 'utf8'));
  } catch {
    return [];
  }
}

function save(tasks) {
  fs.mkdirSync(dataDir, { recursive: true });
  fs.writeFileSync(dataFile, JSON.stringify(tasks, null, 2));
}

module.exports = { load, save, dataFile };
