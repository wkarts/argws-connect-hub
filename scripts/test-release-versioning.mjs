import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

const script = '.github/scripts/compute-next-version.mjs';

function compute(latest, labels = '', title = '', force = 'auto') {
  const output = execFileSync(process.execPath, [script, latest, labels, title, force], {
    encoding: 'utf8',
  });
  return JSON.parse(output);
}

assert.deepEqual(compute('v1.1.3', '', 'Develop', 'auto'), {
  version: '1.1.4', bump: 'patch', previous: '1.1.3', mode: 'auto',
});
assert.equal(compute('v1.1.3', '', 'feat(calls): new feature', 'auto').version, '1.2.0');
assert.equal(compute('v1.1.3', 'version:major', 'Develop', 'auto').version, '2.0.0');
assert.equal(compute('v1.1.3', '', 'feat: ignored by force', 'patch').version, '1.1.4');
assert.equal(compute('v1.1.3', '', 'fix: ignored by force', 'minor').version, '1.2.0');
assert.equal(compute('v1.1.3', '', 'fix: ignored by force', 'major').version, '2.0.0');
assert.equal(compute('', '', '', 'auto').version, '1.0.0');
assert.throws(() => compute('v1.1.3', '', '', 'invalid'));

console.log('HUB semantic release versioning contract: OK');
