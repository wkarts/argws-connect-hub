import fs from 'node:fs';
import { pathToFileURL } from 'node:url';

// Permanent floor: removing an entry from the registry cannot unprotect 1.1.8.
export const CANONICAL_FLOOR = Object.freeze({
  "version": "1.1.8",
  "git_tag": "v1.1.8",
  "git_tag_object": "115e0f5d985fa05851ea6915d7e98ceb398ce6ce",
  "git_commit": "580e870343960f9702c2e681ead1c76b9715deee",
  "image": "ghcr.io/wkarts/argws-connect-hub",
  "image_digest": "sha256:dd0aa7fe967b9e6ff9ad9aeb33b092932cd10f2287fde9b7e798f6863bf61dac",
  "release_id": 388604100
});
export function validateRegistry(registry, previous = null) {
  if (registry?.schema_version !== 1 || !Array.isArray(registry.releases) || registry.releases.length === 0) throw new Error('Invalid canonical registry');
  const seen = new Set();
  for (const item of registry.releases) {
    if (!/^\d+\.\d+\.\d+$/.test(item.version) || seen.has(item.version) || item.git_tag !== `v${item.version}` ||
        !/^[a-f0-9]{40}$/.test(item.git_tag_object) || !/^[a-f0-9]{40}$/.test(item.git_commit) ||
        item.image !== CANONICAL_FLOOR.image || !/^sha256:[a-f0-9]{64}$/.test(item.image_digest) || !Number.isSafeInteger(item.release_id) || item.release_id < 1) throw new Error('Invalid canonical release');
    seen.add(item.version);
  }
  const floor = registry.releases.find(item => item.version === CANONICAL_FLOOR.version);
  for (const [key, value] of Object.entries(CANONICAL_FLOOR)) if (floor?.[key] !== value) throw new Error('Canonical 1.1.8 must remain unchanged');
  if (!seen.has(registry.current)) throw new Error('Current canonical must be a retained release');
  for (const item of previous?.releases || []) {
    const next = registry.releases.find(candidate => candidate.version === item.version);
    if (!next || Object.keys(item).some(key => next[key] !== item[key])) throw new Error(`Canonical release ${item.version} cannot be removed or replaced`);
  }
  return registry;
}
export function assertPublishable(registry, version) {
  validateRegistry(registry);
  if (registry.releases.some(item => item.version === String(version).replace(/^v/, ''))) throw new Error(`Canonical ${version} cannot be rebuilt, retagged or republished`);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const registry = JSON.parse(fs.readFileSync(new URL('../config/canonical-releases.json', import.meta.url), 'utf8'));
    const [mode = 'validate', value] = process.argv.slice(2);
    if (mode === 'publish') assertPublishable(registry, value);
    else if (mode === 'validate') validateRegistry(registry, value ? JSON.parse(fs.readFileSync(value, 'utf8')) : null);
    else throw new Error('Expected validate [previous.json] or publish VERSION');
    console.log('Canonical release guard: OK');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
