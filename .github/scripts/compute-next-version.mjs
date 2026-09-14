const [latestTag = '', labelsArg = '', titleArg = '', forceArg = 'auto'] = process.argv.slice(2);

const latest = String(latestTag || '').replace(/^v/, '');
const labels = String(labelsArg || '')
  .split(',')
  .map(value => value.trim().toLowerCase())
  .filter(Boolean);
const title = String(titleArg || '').trim();
const force = String(forceArg || 'auto').trim().toLowerCase() || 'auto';
const allowed = new Set(['auto', 'patch', 'minor', 'major']);

if (!allowed.has(force)) {
  throw new Error(`Invalid bump mode: ${force}. Expected auto, patch, minor or major.`);
}

let bump = 'patch';
if (!latest) {
  bump = 'initial';
} else if (force !== 'auto') {
  bump = force;
} else if (labels.includes('version:major') || /breaking change|!:/i.test(title)) {
  bump = 'major';
} else if (labels.includes('version:minor') || /^feat(\(.+\))?:/i.test(title)) {
  bump = 'minor';
} else if (labels.includes('version:patch')) {
  bump = 'patch';
}

let version = '1.0.0';
if (latest) {
  const parts = latest.split('.').map(Number);
  if (parts.length !== 3 || parts.some(Number.isNaN)) {
    throw new Error(`Invalid semver tag: ${latestTag}`);
  }

  let [major, minor, patch] = parts;
  if (bump === 'major') [major, minor, patch] = [major + 1, 0, 0];
  else if (bump === 'minor') [minor, patch] = [minor + 1, 0];
  else patch += 1;
  version = `${major}.${minor}.${patch}`;
}

process.stdout.write(JSON.stringify({ version, bump, previous: latest || null, mode: force }));
