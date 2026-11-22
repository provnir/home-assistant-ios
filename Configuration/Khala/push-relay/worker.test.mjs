// node --test Configuration/Khala/push-relay/worker.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';
import worker, { createPayload } from './worker.js';

const reg = { app_id: 'il.example.khala.HomeAssistant', webhook_id: 'w1', os_version: '26.1' };
const token = 'ab'.repeat(32);

test('plain alert: title, body, default sound, mutable content, alert headers', () => {
  const { headers, payload } = createPayload({ message: 'Person at the gate', title: 'Front', registration_info: reg });
  assert.deepEqual(payload.aps.alert, { body: 'Person at the gate', title: 'Front' });
  assert.equal(payload.aps.sound, 'default');
  assert.equal(payload.aps['mutable-content'], 1);
  assert.equal(payload.webhook_id, 'w1');
  assert.equal(headers['apns-push-type'], 'alert');
  assert.equal(headers['apns-priority'], '10');
});

test('critical sound, interruption level, image, tag, group, actions', () => {
  const { headers, payload } = createPayload({
    message: 'Person', registration_info: reg,
    data: {
      push: { sound: { name: 'default', critical: '1', volume: '1.0' }, 'interruption-level': 'critical' },
      image: '/api/camera_proxy/camera.front', tag: 'front', group: 'cams', actions: [{ action: 'OPEN', title: 'Open' }],
    },
  });
  assert.deepEqual(payload.aps.sound, { name: 'default', critical: 1, volume: 1 });
  assert.equal(payload.aps['interruption-level'], 'critical');
  assert.deepEqual(payload.attachment, { 'content-type': 'jpeg', url: '/api/camera_proxy/camera.front' });
  assert.equal(payload.aps.category, 'DYNAMIC');
  assert.equal(payload.aps['thread-id'], 'cams');
  assert.equal(headers['apns-collapse-id'], 'front');
});

test('commands are silent background pushes', () => {
  const { headers, payload } = createPayload({ message: 'request_location_update', registration_info: reg });
  assert.deepEqual(payload.aps, { 'content-available': 1 });
  assert.deepEqual(payload.homeassistant, { command: 'request_location_update' });
  assert.equal(headers['apns-push-type'], 'background');
  assert.equal(headers['apns-priority'], '5');
  const clear = createPayload({ message: 'clear_notification', registration_info: reg, data: { tag: 't' } });
  assert.deepEqual(clear.payload.homeassistant, { command: 'clear_notification', tag: 't' });
});

test('sound none is silent; FCM camelCase keys become APNs keys', () => {
  const { payload } = createPayload({ message: 'x', registration_info: reg,
    data: { push: { sound: 'none', threadId: 'g', interruptionLevel: 'time-sensitive' } } });
  assert.equal(payload.aps.sound, undefined);
  assert.equal(payload.aps['thread-id'], 'g');
  assert.equal(payload.aps['interruption-level'], 'time-sensitive');
});

async function env() {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const der = Buffer.from(await crypto.subtle.exportKey('pkcs8', pair.privateKey)).toString('base64');
  return { pair, env: { APNS_KEY_P8: `-----BEGIN PRIVATE KEY-----\n${der}\n-----END PRIVATE KEY-----`,
    APNS_KEY_ID: 'KEY1234567', APNS_TEAM_ID: 'TEAM123456', BUNDLE_ID: reg.app_id, RELAY_SECRET: 's3cret' } };
}

const post = (path, body) => new Request(`https://relay.example${path}`, { method: 'POST', body: JSON.stringify(body) });

test('relays to APNs with a valid ES256 token and answers like Home Assistant expects', async () => {
  const { pair, env: e } = await env();
  let seen;
  globalThis.fetch = async (url, init) => { seen = { url, init }; return new Response('', { status: 200, headers: { 'apns-id': 'id-1' } }); };
  const res = await worker.fetch(post('/s3cret/sendPushNotification', { push_token: token, message: 'hi', registration_info: reg }), e);
  assert.equal(res.status, 201);
  const out = await res.json();
  assert.equal(out.messageId, 'id-1');
  assert.equal(out.rateLimits.maximum, 500);
  assert.equal(seen.url, `https://api.push.apple.com/3/device/${token}`);
  assert.equal(seen.init.headers['apns-topic'], reg.app_id);
  const [h, c, s] = seen.init.headers.authorization.replace('bearer ', '').split('.');
  assert.deepEqual(JSON.parse(Buffer.from(h, 'base64url')), { alg: 'ES256', kid: 'KEY1234567' });
  assert.equal(JSON.parse(Buffer.from(c, 'base64url')).iss, 'TEAM123456');
  const ok = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, pair.publicKey,
    Buffer.from(s, 'base64url'), new TextEncoder().encode(`${h}.${c}`));
  assert.ok(ok, 'JWT signature verifies');
});

test('refuses wrong secret, other apps, bad tokens; maps dead tokens to InvalidToken', async () => {
  const { env: e } = await env();
  assert.equal((await worker.fetch(post('/nope/sendPushNotification', { push_token: token, registration_info: reg }), e)).status, 404);
  assert.equal((await worker.fetch(post('/s3cret/sendPushNotification', { push_token: token, registration_info: { app_id: 'other' } }), e)).status, 403);
  assert.equal((await worker.fetch(post('/s3cret/sendPushNotification', { push_token: 'abc:def', registration_info: reg }), e)).status, 403);
  globalThis.fetch = async () => new Response(JSON.stringify({ reason: 'Unregistered' }), { status: 410 });
  const res = await worker.fetch(post('/s3cret/sendPushNotification', { push_token: token, message: 'x', registration_info: reg }), e);
  assert.equal(res.status, 500);
  assert.equal((await res.json()).errorType, 'InvalidToken');
  const limits = await worker.fetch(post('/s3cret/checkRateLimits', { push_token: token }), e);
  assert.equal(limits.status, 200);
});
