const [latestTag = '', labelsArg = '', titleArg = ''] = process.argv.slice(2);
const latest = latestTag.replace(/^v/, '');
const labels = labelsArg.split(',').map(v => v.trim().toLowerCase()).filter(Boolean);
const title = String(titleArg || '').trim();

let bump = 'patch';
if (!latest) bump = 'initial';
else if (labels.includes('version:major') || /breaking change|!:/i.test(title)) bump = 'major';
else if (labels.includes('version:minor') || /^feat(\(.+\))?:/i.test(title)) bump = 'minor';
else if (labels.includes('version:patch')) bump = 'patch';

let version = '1.0.0';
if (latest) {
  const parts = latest.split('.').map(Number);
  if (parts.length !== 3 || parts.some(Number.isNaN)) throw new Error(`Invalid semver tag: ${latestTag}`);
  let [major, minor, patch] = parts;
  if (bump === 'major') [major, minor, patch] = [major + 1, 0, 0];
  else if (bump === 'minor') [minor, patch] = [minor + 1, 0];
  else patch += 1;
  version = `${major}.${minor}.${patch}`;
}

process.stdout.write(JSON.stringify({ version, bump, previous: latest || null }));
