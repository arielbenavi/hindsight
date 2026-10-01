// Turns one WhatsApp message into hindsight posts (data contract posts[] shape).
// Pure functions: no WhatsApp connection needed, so they're unit-tested.
//
// Rules (same as the app's WhatsAppExportParser):
// - every link anyone shares becomes a save (platform from the URL, else "web");
// - plain text becomes a note, but only from the chat's owner (the person who
//   added the bot, or the user in a 1:1 chat). Other people's messages are
//   their personal data, so their text is skipped; their links are kept.
// - the chat's name goes in `collections`, so the app can group by chat.

const PLATFORM_HOSTS = {
  instagram: ['instagram.com'],
  facebook: ['facebook.com', 'fb.watch'],
  x: ['x.com', 'twitter.com'],
  tiktok: ['tiktok.com', 'tiktokv.com'],
};

export function platformFor(url) {
  let host;
  try { host = new URL(url).hostname.toLowerCase(); } catch { return null; }
  for (const [platform, suffixes] of Object.entries(PLATFORM_HOSTS)) {
    if (suffixes.some((s) => host === s || host.endsWith('.' + s))) return platform;
  }
  return null;
}

export function kindFor(url) {
  const platform = platformFor(url);
  const path = (() => { try { return new URL(url).pathname.toLowerCase(); } catch { return ''; } })();
  switch (platform) {
    case 'instagram': return path.includes('/reel') ? 'reel' : path.includes('/tv/') ? 'video' : 'post';
    case 'x': return 'tweet';
    case 'tiktok': return 'video';
    case 'facebook': return path.includes('/reel') ? 'reel' : path.includes('video') ? 'video' : 'post';
    default: return 'link';
  }
}

export function linksIn(text) {
  return (text.match(/https?:\/\/[^\s<>"]+/g) || [])
    .map((u) => u.replace(/[.,;:!?)\]}'"]+$/, ''))
    .filter((u) => { try { return Boolean(new URL(u).host); } catch { return false; } });
}

/** Text of a Baileys message (`extractMessageContent(msg.message)` result). */
export function messageText(content) {
  if (!content) return '';
  return content.conversation
    || content.extendedTextMessage?.text
    || content.imageMessage?.caption
    || content.videoMessage?.caption
    || content.documentMessage?.caption
    || '';
}

/**
 * @param {object} m
 * @param {string} m.text
 * @param {string} m.messageId   WhatsApp message id (stable; used for note ids)
 * @param {number} m.timestamp   seconds since epoch
 * @param {boolean} m.fromOwner  sent by the chat's owner
 * @param {string|null} m.chatName  group subject, or null for a 1:1 chat
 * @param {string|null} m.senderName
 */
export function toPosts({ text, messageId, timestamp, fromOwner, chatName, senderName }) {
  const savedAt = new Date(timestamp * 1000).toISOString();
  const collections = chatName ? [chatName] : [];
  const links = linksIn(text);
  // Remove the raw link tokens (with any trailing punctuation), then tidy spaces.
  const note = text.replace(/https?:\/\/[^\s<>"]+/g, '').replace(/\s+/g, ' ').trim();

  const posts = links.map((url) => ({
    platform: platformFor(url) ?? 'web',
    url,
    kind: kindFor(url),
    author: null,
    caption: fromOwner && note ? note : null,
    collections,
    saved_at: savedAt,
    shared_by: senderName ?? null,
    source: 'whatsapp_bot',
  }));

  if (!links.length && note && fromOwner) {
    posts.push({
      id: `whatsapp:${messageId}`,
      platform: 'whatsapp',
      url: `hindsight-note:whatsapp/${messageId}`,
      kind: 'note',
      author: senderName ?? null,
      caption: note,
      collections,
      saved_at: savedAt,
      source: 'whatsapp_bot',
    });
  }
  return posts;
}
