// Khala push relay: a Cloudflare Worker that stands in for Home Assistant's own push relay
// (mobile-apps.home-assistant.io), which can only deliver to the official app's bundle id.
//
// Home Assistant's mobile_app integration POSTs each notification to the push_url the app
// registered, with the push_token the app registered. Khala registers this Worker's URL and its
// raw APNs device token, so this Worker turns Home Assistant's request into an APNs request,
// signed with the team's APNs auth key, and answers in the shape Home Assistant expects.
//
// The payload mapping is a port of home-assistant/mobile-apps-fcm-push functions/ios.js
// (Apache-2.0), minus the Firebase envelope: FCM's camelCase aps keys become APNs' own keys.
//
// Environment (wrangler secrets / vars):
//   APNS_KEY_P8     secret  the .p8 auth key (PEM)
//   APNS_KEY_ID     var     its key id
//   APNS_TEAM_ID    var     the Apple team id
//   BUNDLE_ID       var     the app's bundle id (apns-topic); requests for other apps are refused
//   RELAY_SECRET    secret  path segment Khala's push_url carries: /<RELAY_SECRET>/sendPushNotification
//   APNS_HOST       var     optional, default api.push.apple.com (TestFlight/App Store tokens)

const MAX_PER_DAY = 500; // reported to Home Assistant; nothing is stored, so nothing is enforced

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const [secret, action, ...rest] = url.pathname.split('/').filter(Boolean);
    if (request.method !== 'POST' || rest.length || !env.RELAY_SECRET || !timingSafeEqual(secret || '', env.RELAY_SECRET)) {
      return new Response('Not found', { status: 404 });
    }
    let body;
    try {
      body = await request.json();
    } catch {
      return json(400, { errorMessage: 'Body is not JSON' });
    }
    const token = body.push_token;
    if (typeof token !== 'string' || !/^[0-9a-f]{64,200}$/i.test(token)) {
      return json(403, { errorMessage: 'That is not a valid APNs device token' });
    }
    if (action === 'checkRateLimits') {
      return json(200, { target: token, rateLimits: rateLimits() });
    }
    if (action !== 'sendPushNotification') {
      return new Response('Not found', { status: 404 });
    }
    const appId = body.registration_info?.app_id;
    if (appId !== env.BUNDLE_ID) {
      return json(403, { errorMessage: 'This relay only serves its own app' });
    }

    const { headers, payload } = createPayload(body);
    const response = await sendToApns(env, token, headers, payload);
    if (response.ok) {
      return json(201, {
        messageId: response.headers.get('apns-id'),
        sentPayload: payload,
        target: token,
        rateLimits: rateLimits(),
      });
    }
    let reason = `HTTP ${response.status}`;
    try {
      reason = (await response.json()).reason || reason;
    } catch {}
    const invalid = ['BadDeviceToken', 'Unregistered', 'DeviceTokenNotForTopic'].includes(reason);
    return json(500, {
      errorType: invalid ? 'InvalidToken' : 'InternalError',
      errorCode: reason,
      errorStep: 'sendNotification',
      message: `APNs refused the notification: ${reason}`,
    });
  },
};

// --- Home Assistant request -> APNs request ------------------------------------------

export function createPayload(body) {
  const data = body.data || {};
  const headers = {};
  let payload = { aps: { alert: { body: body.message }, sound: 'default' } };
  if (body.title) payload.aps.alert.title = body.title;

  // A raw APNs payload/headers given by the automation win, as on Home Assistant's relay.
  if (data.apns?.payload) payload = data.apns.payload;
  if (data.apns?.headers) Object.assign(headers, data.apns.headers);
  if (data.apns_headers) Object.assign(headers, data.apns_headers);
  if (!payload.aps) payload.aps = {};

  if (body.registration_info?.webhook_id) payload.webhook_id = body.registration_info.webhook_id;

  const command = (name) => {
    payload.aps = { 'content-available': 1 };
    payload.homeassistant = { command: name };
    if (data.push?.badge) payload.aps.badge = Number(data.push.badge);
  };

  const message = body.message;
  if (message === 'request_location_update' || message === 'request_location_updates') {
    command('request_location_update');
  } else if (message === 'clear_badge') {
    payload.aps = { badge: 0 };
  } else if (message === 'clear_notification') {
    command('clear_notification');
    if (data.tag) payload.homeassistant.tag = data.tag;
    if (headers['apns-collapse-id']) payload.homeassistant.collapseId = headers['apns-collapse-id'];
    delete headers['apns-collapse-id'];
  } else if (message === 'update_complications' || message === 'update_widgets') {
    command(message);
  } else {
    let needsCategory = false;
    if (data.subtitle) payload.aps.alert = { ...payload.aps.alert, subtitle: data.subtitle };
    if (data.push) payload.aps = { ...payload.aps, ...data.push };
    if (data.actions) {
      payload.actions = data.actions;
      needsCategory = true;
    }
    if (data.sound) payload.aps.sound = data.sound;
    if (data.entity_id) {
      payload.entity_id = data.entity_id;
      needsCategory = true;
    }
    for (const key of ['level', 'volume', 'mode']) {
      if (data[key] !== undefined) payload[key] = data[key];
    }
    if (data.action_data) {
      payload.homeassistant = data.action_data;
      needsCategory = true;
    }
    if (data.attachment) {
      payload.attachment = data.attachment;
      needsCategory = true;
    }
    const addAttachment = (url, contentType) => {
      if (!url) return;
      payload.attachment = payload.attachment || {};
      payload.attachment['content-type'] = payload.attachment['content-type'] || contentType;
      payload.attachment.url = payload.attachment.url || url;
      needsCategory = true;
    };
    addAttachment(data.video, 'mpeg4');
    addAttachment(data.image, 'jpeg');
    addAttachment(data.audio, 'waveformaudio');
    for (const key of ['url', 'shortcut', 'presentation_options', 'notification_icon', 'icon_url',
      'notification_icon_color', 'color']) {
      if (data[key] !== undefined) payload[key] = data[key];
    }
    if (typeof data.tag === 'string') headers['apns-collapse-id'] = data.tag;
    if (typeof data.group === 'string') payload.aps['thread-id'] = data.group;

    // FCM spellings an automation may still use.
    renameKey(payload.aps, 'contentAvailable', 'content-available');
    renameKey(payload.aps, 'mutableContent', 'mutable-content');
    renameKey(payload.aps, 'threadId', 'thread-id');
    renameKey(payload.aps, 'interruptionLevel', 'interruption-level');

    if (needsCategory && !payload.aps.category) {
      payload.aps.category = 'DYNAMIC';
    } else if (typeof payload.aps.category === 'string') {
      payload.aps.category = payload.aps.category.toUpperCase();
    }
    if (!payload.aps['content-available']) payload.aps['mutable-content'] = 1;

    if (message === 'delete_alert') {
      if (payload.aps.alert && typeof payload.aps.alert === 'object') {
        delete payload.aps.alert.title;
        delete payload.aps.alert.subtitle;
        delete payload.aps.alert.body;
      }
      delete payload.aps.sound;
    }
    if (message === 'test_push_source') {
      payload.aps.alert = { ...payload.aps.alert, title: message, body: 'khala-relay' };
    }
  }

  const sound = payload.aps.sound;
  if (typeof sound === 'string' && sound.toLowerCase() === 'none') {
    delete payload.aps.sound;
  } else if (sound && typeof sound === 'object') {
    if (sound.volume !== undefined) sound.volume = parseFloat(sound.volume);
    if (sound.critical !== undefined) sound.critical = parseInt(sound.critical, 10);
  }
  if (payload.aps.badge !== undefined) payload.aps.badge = Number(payload.aps.badge);
  if (payload.aps['content-available']) payload.aps['content-available'] = 1;

  const background = Boolean(payload.aps['content-available']) && !payload.aps.alert;
  headers['apns-push-type'] = headers['apns-push-type'] || (background ? 'background' : 'alert');
  headers['apns-priority'] = headers['apns-priority'] || (background ? '5' : '10');
  return { headers, payload };
}

function renameKey(object, from, to) {
  if (object && object[from] !== undefined) {
    if (object[to] === undefined) object[to] = object[from] === true ? 1 : object[from];
    delete object[from];
  }
}

// --- APNs ------------------------------------------------------------------------------

let cachedJwt = null; // { token, issuedAt, keyId }

async function providerToken(env) {
  const now = Math.floor(Date.now() / 1000);
  // Apple refuses tokens older than an hour and throttles refreshing more often than every 20 minutes.
  if (cachedJwt && cachedJwt.keyId === env.APNS_KEY_ID && now - cachedJwt.issuedAt < 45 * 60) {
    return cachedJwt.token;
  }
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: env.APNS_KEY_ID }));
  const claims = base64url(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: now }));
  const der = Uint8Array.from(atob(env.APNS_KEY_P8.replace(/-----[A-Z ]+-----|\s/g, '')), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key,
    new TextEncoder().encode(`${header}.${claims}`));
  const token = `${header}.${claims}.${base64url(new Uint8Array(signature))}`;
  cachedJwt = { token, issuedAt: now, keyId: env.APNS_KEY_ID };
  return token;
}

async function sendToApns(env, deviceToken, headers, payload) {
  const host = env.APNS_HOST || 'api.push.apple.com';
  return fetch(`https://${host}/3/device/${deviceToken}`, {
    method: 'POST',
    headers: {
      ...headers,
      authorization: `bearer ${await providerToken(env)}`,
      'apns-topic': env.BUNDLE_ID,
      'content-type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
}

// --- helpers ---------------------------------------------------------------------------

function rateLimits() {
  const reset = new Date();
  reset.setUTCHours(24, 0, 0, 0);
  return { attempts: 0, successful: 0, errors: 0, total: 0, maximum: MAX_PER_DAY, remaining: MAX_PER_DAY,
    resetsAt: reset.toISOString() };
}

function json(status, value) {
  return new Response(JSON.stringify(value), { status, headers: { 'content-type': 'application/json' } });
}

function base64url(input) {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
