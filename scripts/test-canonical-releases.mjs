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
function cleanup(policy, options = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hub-canonical-test-'));
  try {
    for (const dir of ['scripts', 'config', 'bin']) fs.mkdirSync(path.join(root, dir));
    for (const file of ['cleanup-github-storage.sh', 'canonical-releases.mjs']) fs.copyFileSync(new URL(file, import.meta.url), path.join(root, 'scripts', file));
    if (!options.missingPolicy) fs.writeFileSync(path.join(root, 'config/canonical-releases.json'), options.rawPolicy ?? JSON.stringify(policy));
    const data = [version(1, ['1.1.8']), version(2, ['1.0.0', '1.1.8']), version(3, ['sha-abcdef012345'], CANONICAL_FLOOR.image_digest),
      version(4, []), version(5, ['2.1.0']), version(6, ['2.0.0']), version(7, ['1.1.9']), version(8, ['develop']),
      version(9, ['develop-abcdef012345']), version(10, ['1.1.7', 'manual-keep']), version(11, ['v1.1.8']), version(12, ['1.1.1', 'latest'])];
    fs.writeFileSync(path.join(root, 'versions.json'), JSON.stringify(options.versions ?? data));
    fs.writeFileSync(path.join(root, 'bin/gh'), '#!/usr/bin/env bash\nset -euo pipefail\nif [[ "$*" == *"--method DELETE"* ]]; then echo "${*: -1}" >> "$TEST_ROOT/deleted"; else cat "$TEST_ROOT/versions.json"; fi\n', { mode: 0o755 });
    const result = spawnSync('bash', [path.join(root, 'scripts/cleanup-github-storage.sh'), 'ghcr'], { cwd: options.outsideRoot ? path.join(root, 'bin') : root, encoding: 'utf8', timeout: 10000, env: { ...process.env, PATH: `${root}/bin:${process.env.PATH}`, GH_TOKEN: 'fixture', GITHUB_REPOSITORY: 'wkarts/argws-connect-hub', GHCR_OWNER: 'wkarts', GHCR_PACKAGE: options.package ?? 'argws-connect-hub', TEST_ROOT: root } });
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


test('missing registry and malformed JSON both stop cleanup before any deletion', () => {
  for (const options of [{ missingPolicy: true }, { rawPolicy: '{broken' }]) {
    const result = cleanup(registry(), options);
    assert.notEqual(result.status, 0);
    assert.deepEqual(result.deletions, []);
  }
});

test('an additional older canonical stays protected after the current canonical changes', () => {
  const policy = registry();
  policy.releases.push({ ...CANONICAL_FLOOR, version: '1.1.9', git_tag: 'v1.1.9', release_id: 123 });
  policy.current = '1.1.9';
  const result = cleanup(policy);
  assert.equal(result.status, 0, result.stderr + result.stdout);
  assert.deepEqual(result.deletions.map(url => Number(url.split('/').pop())), [9]);
});

test('current, previous and active/manual tags protect the whole version regardless of tag order', () => {
  const result = cleanup(registry(), { versions: [
    version(1, ['1.0.0', '2.1.0']), version(2, ['1.0.0', '2.0.0']),
    version(3, ['1.0.0', 'stable']), version(4, ['1.0.0', 'canonical']),
    version(5, ['1.0.0', 'develop']), version(6, ['1.0.0', 'latest']),
    version(7, ['1.0.0', 'manual-keep']), version(8, ['1.1.0', 'sha-abcdef012345'])
  ] });
  assert.equal(result.status, 0, result.stderr + result.stdout);
  assert.deepEqual(result.deletions.map(url => Number(url.split('/').pop())), [8]);
});

test('the canonical registry is located relative to the script, not the working directory', () => {
  const result = cleanup(registry(), { outsideRoot: true });
  assert.equal(result.status, 0, result.stderr + result.stdout);
  assert.deepEqual(result.deletions.map(url => Number(url.split('/').pop())), [7, 9]);
});

test('unexpected GHCR API payloads fail closed instead of pruning a partial inventory', () => {
  for (const versions of [{ message: 'API error' }, [version(1, ['1.1.0']), { id: 2 }]]) {
    const result = cleanup(registry(), { versions });
    assert.notEqual(result.status, 0);
    assert.deepEqual(result.deletions, []);
  }
});

test('base packages and inventories without exact release tags remain protected', () => {
  const base = cleanup(registry(), { package: 'argws-connect-hub-runtime' });
  assert.notEqual(base.status, 0);
  assert.deepEqual(base.deletions, []);
  const noRelease = cleanup(registry(), { versions: [version(1, ['develop-abcdef012345'])] });
  assert.equal(noRelease.status, 0, noRelease.stderr + noRelease.stdout);
  assert.deepEqual(noRelease.deletions, []);
});
