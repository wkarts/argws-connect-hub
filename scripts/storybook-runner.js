#!/usr/bin/env node

const { spawnSync } = require('child_process');
const path = require('path');

const mode = process.argv[2] === 'build' ? 'build-storybook' : 'start-storybook';
const suffix = process.platform === 'win32' ? '.cmd' : '';
const executable = path.join(__dirname, '..', 'node_modules', '.bin', `${mode}${suffix}`);
const args = mode === 'start-storybook' ? ['-p', '6006'] : [];

const env = {
  ...process.env,
  STORYBOOK_DISABLE_TELEMETRY: '1',
};

const result = spawnSync(executable, args, {
  stdio: 'inherit',
  env,
  shell: process.platform === 'win32',
});

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

process.exit(result.status ?? 1);
