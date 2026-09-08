#!/usr/bin/env node

import fs from 'node:fs';

const version = process.argv[2];
if (!/^\d+\.\d+\.\d+$/.test(version || '')) {
  console.error('Usage: node .github/scripts/apply-version.mjs X.Y.Z');
  process.exit(1);
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function writeJson(file, data) {
  fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`);
}

const pkg = readJson('package.json');
pkg.version = version;
writeJson('package.json', pkg);

const manifest = readJson('RELEASE-MANIFEST.json');
manifest.version = version;
manifest.release_channel = 'stable';
manifest.revision_date = new Date().toISOString().slice(0, 10);
writeJson('RELEASE-MANIFEST.json', manifest);

fs.writeFileSync('VERSION', `${version}\n`);

console.log(`HUB version set to ${version}`);
console.log(`Stable image: ghcr.io/wkarts/argws-connect-hub:${version}`);
console.log('Production channel tracks :latest; development tracks :develop.');
