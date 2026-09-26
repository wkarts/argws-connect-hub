import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import test from 'node:test';
import { CANONICAL_FLOOR, validateRegistry, assertPublishable } from './canonical-releases.mjs';
const registry = () => ({ schema_version: 1, current: '1.1.8', releases: [{ ...CANONICAL_FLOOR }] });

test('1.1.8 cannot be removed, repinned, rebuilt or republished', () => {
  assert.doesNotThrow(() => validateRegistry(registry()));
  for (const field of Object.keys(CANONICAL_FLOOR)) {
    const policy = registry(); policy.releases[0][field] = 'changed';
    assert.throws(() => validateRegistry(policy));
  }
  assert.throws(() => validateRegistry({ ...registry(), releases: [] }));
  for (const version of ['1.1.8', 'v1.1.8']) assert.throws(() => assertPublishable(registry(), version));
  assert.doesNotThrow(() => assertPublishable(registry(), '1.1.9'));
});

test('future canonicals are additive; changing current cannot remove older releases', () => {
  const policy = registry();
  policy.releases.push({ ...CANONICAL_FLOOR, version: '2.0.0', git_tag: 'v2.0.0', release_id: 123 });
  policy.current = '2.0.0';
  assert.doesNotThrow(() => validateRegistry(policy, registry()));
  assert.throws(() => validateRegistry(registry(), policy));
  assert.throws(() => assertPublishable(policy, '2.0.0'));
});

const version = (id, tags, name = `sha256:${String(id).padStart(64, '0')}`) => ({ id, name, metadata: { container: { tags } } });
function cleanup(policy) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hub-canonical-test-'));
  try {
    for (const dir of ['scripts', 'config', 'bin']) fs.mkdirSync(path.join(root, dir));
    for (const file of ['cleanup-github-storage.sh', 'canonical-releases.mjs']) fs.copyFileSync(new URL(file, import.meta.url), path.join(root, 'scripts', file));
    fs.writeFileSync(path.join(root, 'config/canonical-releases.json'), JSON.stringify(policy));
    const data = [version(1, ['1.1.8']), version(2, ['1.0.0', '1.1.8']), version(3, ['sha-abcdef012345'], CANONICAL_FLOOR.image_digest),
      version(4, []), version(5, ['2.1.0']), version(6, ['2.0.0']), version(7, ['1.1.9']), version(8, ['develop']),
      version(9, ['develop-abcdef012345']), version(10, ['1.1.7', 'manual-keep']), version(11, ['v1.1.8']), version(12, ['1.1.1', 'latest'])];
    fs.writeFileSync(path.join(root, 'versions.json'), JSON.stringify(data));
    fs.writeFileSync(path.join(root, 'bin/gh'), '#!/usr/bin/env bash\nset -euo pipefail\nif [[ "$*" == *"--method DELETE"* ]]; then echo "${*: -1}" >> "$TEST_ROOT/deleted"; else cat "$TEST_ROOT/versions.json"; fi\n', { mode: 0o755 });
    const result = spawnSync('bash', ['scripts/cleanup-github-storage.sh', 'ghcr'], { cwd: root, encoding: 'utf8', env: { ...process.env, PATH: `${root}/bin:${process.env.PATH}`, GH_TOKEN: 'fixture', GITHUB_REPOSITORY: 'wkarts/argws-connect-hub', TEST_ROOT: root } });
    const deletions = fs.existsSync(path.join(root, 'deleted')) ? fs.readFileSync(path.join(root, 'deleted'), 'utf8').trim().split('\n') : [];
    return { ...result, deletions };
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
}

test('cleanup retains any canonical tag/digest, child manifests and active aliases while pruning old versions', () => {
  const result = cleanup(registry());
  assert.equal(result.status, 0, result.stderr + result.stdout);
  assert.deepEqual(result.deletions.map(url => Number(url.split('/').pop())).sort((a, b) => a - b), [7, 9]);
});

test('malformed or missing canonical policy fails closed before deleting any image', () => {
  const result = cleanup({ schema_version: 1, current: '2.0.0', releases: [] });
  assert.notEqual(result.status, 0);
  assert.deepEqual(result.deletions, []);
});
