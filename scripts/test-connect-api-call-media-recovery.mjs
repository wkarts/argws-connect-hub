import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(
  'app/javascript/dashboard/components/widgets/conversation/ConnectApiCallPanel.vue',
  'utf8'
);

assert.match(source, /mediaAutoRecoveryCallId:\s*''/);
assert.match(source, /mediaAttachingCallId:\s*''/);
assert.match(source, /shouldRecoverMedia\(call\)/);
assert.match(source, /if \(this\.canAccept\(call\)\) return false;/);
assert.match(source, /this\.isConnected\(call\)[\s\S]*call\.direction[\s\S]*outgoing/);
assert.match(source, /async recoverActiveMedia\(\)/);
assert.match(source, /this\.recoverActiveMedia\(\);/);
assert.match(source, /async reconnectMedia\(\)/);
assert.match(source, /attachMedia\(callId, \{ recovered: true \}\)/);
assert.match(source, /navigator|microfone/i);
assert.match(source, /Reconectar áudio/);
assert.match(source, /Áudio e microfone recuperados para a chamada em andamento\./);
assert.match(source, /this\.voiceSession\.setMicMuted\(Boolean\(current\.muted\)\)/);

console.log('Connect API call media recovery contract: OK');
