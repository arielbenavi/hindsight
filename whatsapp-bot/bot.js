// hindsight WhatsApp bot (experiment). A dedicated WhatsApp account that users
// add to their notes chats (a group with themselves, or a 1:1 chat with the
// bot). Every new message there is turned into hindsight posts and sent to the
// connector's /ingest endpoint, the same store Muse writes to.
//
// Runs as a linked device of OUR bot account via Baileys (the WhatsApp Web
// protocol). Users never log in or hand us their account. Unofficial client:
// the bot number can be banned, so chat export stays the fallback.
// See README.md.
//
// Env:
//   HINDSIGHT_INGEST_URL  connector ingest URL, e.g. http://127.0.0.1:8765/<token>/ingest (required)
//   BOT_PHONE             bot number in international format, digits only, to log in with a
//                         pairing code instead of a QR (e.g. 15551234567)
//   SILENT=1              don't post the one-time hello message in chats
//
// Which hindsight user a chat belongs to: the app's "Connect WhatsApp" button
// opens a chat with the bot prefilled with "connect code: <tenant>". The bot
// remembers that phone number → tenant (state/links.json) and files everything
// from that person (their DMs, and groups they own) under their tenant.
// Unlinked people go to the default store (fine for the beta).

import fs from 'node:fs';
import path from 'node:path';
import pino from 'pino';
import qrcode from 'qrcode-terminal';
import makeWASocket, {
  Browsers, DisconnectReason, downloadMediaMessage, extractMessageContent, fetchLatestBaileysVersion,
  jidNormalizedUser, useMultiFileAuthState,
} from 'baileys';
import { messageText, toPosts } from './convert.js';
import { chatNameFromFileName, chatTextFrom, exportToPosts } from './exportParser.js';

const INGEST_URL = process.env.HINDSIGHT_INGEST_URL;
if (!INGEST_URL) { console.error('Set HINDSIGHT_INGEST_URL (see README.md)'); process.exit(1); }

const STATE = path.resolve('state');
fs.mkdirSync(STATE, { recursive: true });
const GROUPS_FILE = path.join(STATE, 'groups.json');
const OUTBOX_FILE = path.join(STATE, 'outbox.jsonl');
const groups = fs.existsSync(GROUPS_FILE) ? JSON.parse(fs.readFileSync(GROUPS_FILE, 'utf8')) : {};
const saveGroups = () => fs.writeFileSync(GROUPS_FILE, JSON.stringify(groups, null, 1));
const LINKS_FILE = path.join(STATE, 'links.json');
const links = fs.existsSync(LINKS_FILE) ? JSON.parse(fs.readFileSync(LINKS_FILE, 'utf8')) : {};
const saveLinks = () => fs.writeFileSync(LINKS_FILE, JSON.stringify(links, null, 1));
const CONNECT_RE = /connect code:\s*([a-z0-9-]{3,40})/i;

// state/health.json: read by healthcheck.sh (is the bot linked, when did it last connect / see a message).
const HEALTH_FILE = path.join(STATE, 'health.json');
const health = fs.existsSync(HEALTH_FILE) ? JSON.parse(fs.readFileSync(HEALTH_FILE, 'utf8')) : {};
const noteHealth = (fields) => {
  Object.assign(health, fields, { updated: new Date().toISOString() });
  fs.writeFileSync(HEALTH_FILE, JSON.stringify(health, null, 1));
};

const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);
/** The phone/user part of a JID, so "123@s.whatsapp.net", "123:4@…" and "123@lid" compare by user. */
const userOf = (jid) => (jid ? jidNormalizedUser(String(jid)).split('@')[0] : '');

// ── delivery to hindsight (with an outbox for when the connector is down) ──

function post(posts, tenant, source) {
  return fetch(INGEST_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(tenant ? { 'x-hindsight-tenant': tenant } : {}) },
    body: JSON.stringify({ source, posts }),
  });
}

/** Sends posts to the user's hindsight store. Returns the server's counts, or null if queued. */
async function deliver(posts, tenant, source = 'whatsapp_bot') {
  if (!posts.length) return { accepted: 0, duplicates: 0 };
  try {
    const res = await post(posts, tenant, source);
    if (!res.ok) throw new Error(`ingest ${res.status}`);
    const counts = await res.json();
    log(`→ hindsight${tenant ? ` [${tenant}]` : ''}: ${posts.length} posts, accepted ${counts.accepted}, duplicates ${counts.duplicates}`);
    await flushOutbox();
    return counts;
  } catch (err) {
    log('ingest failed, queued:', err.message);
    fs.appendFileSync(OUTBOX_FILE, JSON.stringify({ tenant, source, posts }) + '\n');
    return null;
  }
}

let flushing = false;
async function flushOutbox() {
  if (flushing || !fs.existsSync(OUTBOX_FILE)) return;
  const lines = fs.readFileSync(OUTBOX_FILE, 'utf8').split('\n').filter(Boolean);
  if (!lines.length) return;
  flushing = true;
  try {
    for (const line of lines) {
      const { tenant, source, posts } = JSON.parse(line);
      const res = await post(posts, tenant, source);
      if (!res.ok) throw new Error(`ingest ${res.status}`);
    }
    fs.unlinkSync(OUTBOX_FILE); log(`outbox flushed (${lines.length})`);
  } catch { /* try again next time */ } finally { flushing = false; }
}

// ── chats: who owns each one, what it's called ──

async function chatInfo(sock, chatId) {
  if (!chatId.endsWith('@g.us')) return { name: null, owner: chatId, humans: 1 };
  let info = groups[chatId];
  if (!info?.name || info.humans == null || !info.owner) {
    try {
      const meta = await sock.groupMetadata(chatId);
      const me = userOf(sock.user?.id);
      const humans = meta.participants.filter((p) => userOf(p.id) !== me && userOf(p.phoneNumber) !== me);
      info = { ...info, name: meta.subject, humans: humans.length };
      // Owner: whoever added the bot (set by group-participants.update), else the
      // group's creator (the bot was added when the group was made), else the
      // only other person in it.
      if (!info.owner) {
        info.owner = meta.owner || (humans.length === 1 ? humans[0].id : undefined);
        info.ownerAlt = meta.ownerPn || (humans.length === 1 ? humans[0].phoneNumber : undefined);
      }
      groups[chatId] = info; saveGroups();
    } catch (err) { log('groupMetadata failed', err.message); info = info || {}; }
  }
  return info;
}

/** The hindsight user (tenant) a message belongs to: the DM sender's, or the group owner's. */
function tenantFor(chatId, info) {
  const ids = chatId.endsWith('@g.us') ? [info.owner, info.ownerAlt] : [chatId, info.chatAlt];
  for (const id of ids.filter(Boolean)) if (userOf(id) in links) return links[userOf(id)];
  return null;
}

async function hello(sock, chatId, humans) {
  if (process.env.SILENT === '1' || groups[chatId]?.announced) return;
  const text = humans > 1
    ? '👋 hindsight is in this group for its owner. Links shared here, and the owner\'s own notes, are saved to their hindsight app. Other people\'s messages aren\'t stored. Remove me anytime.'
    : '✅ Connected to hindsight. Anything you send here (links, notes, reminders) shows up in your app.';
  await sock.sendMessage(chatId, { text });
  groups[chatId] = { ...groups[chatId], announced: true }; saveGroups();
}

// ── the connection ──

async function start() {
  const { state, saveCreds } = await useMultiFileAuthState('auth');
  const { version } = await fetchLatestBaileysVersion();
  const sock = makeWASocket({
    version, auth: state, browser: Browsers.macOS('Chrome'),
    logger: pino({ level: 'warn' }), markOnlineOnConnect: false, syncFullHistory: false,
  });
  sock.ev.on('creds.update', saveCreds);

  if (!state.creds.registered && process.env.BOT_PHONE) {
    setTimeout(async () => {
      const code = await sock.requestPairingCode(process.env.BOT_PHONE.replace(/\D/g, ''));
      log(`Pairing code: ${code}  (on the bot phone: WhatsApp → Linked devices → Link with phone number)`);
    }, 3000);
  }

  sock.ev.on('connection.update', ({ connection, lastDisconnect, qr }) => {
    if (qr && !process.env.BOT_PHONE) {
      log('Scan with the bot phone: WhatsApp → Linked devices → Link a device');
      qrcode.generate(qr, { small: true });
    }
    if (connection === 'open') {
      log(`connected as ${sock.user?.id}`);
      noteHealth({ status: 'connected', lastConnected: new Date().toISOString() });
      flushOutbox();
    }
    if (connection === 'close') {
      const code = lastDisconnect?.error?.output?.statusCode;
      if (code === DisconnectReason.loggedOut) {
        log('Logged out (or banned). Delete auth/ and link again.');
        noteHealth({ status: 'logged_out', loggedOutAt: new Date().toISOString() });
        process.exit(0); // clean exit: launchd's KeepAlive only restarts crashes
      }
      noteHealth({ status: 'reconnecting', lastDisconnect: code ?? null });
      log(`connection closed (${code}), reconnecting…`); setTimeout(start, 3000);
    }
  });

  // Added to a group: remember who added us (the owner) and say hello once.
  sock.ev.on('group-participants.update', async ({ id, author, authorPn, participants, action }) => {
    const me = userOf(sock.user?.id);
    const ids = participants.map((p) => (typeof p === 'string' ? p : p.id || p.phoneNumber));
    if (action !== 'add' || !ids.some((p) => userOf(p) === me)) return;
    groups[id] = { ...groups[id], owner: author || groups[id]?.owner, ownerAlt: authorPn || groups[id]?.ownerAlt, humans: undefined };
    saveGroups();
    const info = await chatInfo(sock, id);
    log(`added to "${info.name}" by ${author} (${info.humans} people)`);
    await hello(sock, id, info.humans);
  });

  // Added while the group was being created: no participants.update, only a new group.
  sock.ev.on('groups.upsert', async (metas) => {
    for (const meta of metas) {
      const info = await chatInfo(sock, meta.id);
      log(`new group "${info.name}" (${info.humans} people, owner ${info.owner})`);
      await hello(sock, meta.id, info.humans);
    }
  });

  // Shared history: when a member adds the bot and picks "share recent messages"
  // (up to 100 / 14 days, WhatsApp 2026), those arrive as a history sync.
  // Unverified with Baileys; handled the same way as new messages.
  sock.ev.on('messaging-history.set', async ({ messages }) => {
    const groupMessages = (messages || []).filter((m) => m.key?.remoteJid?.endsWith('@g.us'));
    if (groupMessages.length) log(`history: ${groupMessages.length} shared group messages`);
    await handle(groupMessages);
  });

  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    if (type !== 'notify' && type !== 'append') return;
    await handle(messages);
  });

  async function handle(messages) {
    for (const msg of messages) {
      const chatId = msg.key.remoteJid;
      if (!msg.message || msg.key.fromMe || !chatId || chatId === 'status@broadcast') continue;
      noteHealth({ lastMessage: new Date().toISOString() });
      const content = extractMessageContent(msg.message);
      const text = messageText(content);
      const info = { ...(await chatInfo(sock, chatId)), chatAlt: msg.key.remoteJidAlt };

      // "connect code: <tenant>" from the app's Connect button: link this number to that hindsight user.
      const code = !chatId.endsWith('@g.us') && text.match(CONNECT_RE)?.[1];
      if (code) {
        const tenant = code.toLowerCase() === 'main' ? null : code.toLowerCase();
        for (const id of [chatId, msg.key.remoteJidAlt].filter(Boolean)) links[userOf(id)] = tenant;
        saveLinks();
        log(`linked ${userOf(msg.key.remoteJidAlt || chatId)} → ${tenant ?? 'main'}`);
        groups[chatId] = { ...groups[chatId], announced: true }; saveGroups();
        await sock.sendMessage(chatId, { text: '✅ Connected to hindsight.\n\n• Send notes and links here, they show up in your app.\n• Or add me to a group where you keep notes.\n• Old notes: in that chat tap its name → Export chat → Without media → send the file here.' });
        continue;
      }

      const sender0 = msg.key.participant || chatId;
      const senderAlt0 = msg.key.participantAlt || msg.key.participantPn;
      const ownerIds0 = [info.owner, info.ownerAlt].filter(Boolean).map(userOf);
      const fromOwner0 = info.humans <= 1 || [sender0, senderAlt0].some((j) => j && ownerIds0.includes(userOf(j)));

      // A chat export sent as a file (zip or txt): import its history.
      if (content?.documentMessage && fromOwner0) {
        await importExport(msg, content.documentMessage, chatId, tenantFor(chatId, info));
        continue;
      }
      if (!text) continue;
      const [sender, senderAlt, fromOwner] = [sender0, senderAlt0, fromOwner0];
      const posts = toPosts({
        text, messageId: msg.key.id, timestamp: Number(msg.messageTimestamp) || Date.now() / 1000,
        fromOwner, chatName: info.name, senderName: msg.pushName || null,
      });
      log(`${info.name ?? 'DM'}: ${posts.length} posts from ${fromOwner ? 'owner' : 'someone else'} (${userOf(senderAlt || sender)})`);
      if (!groups[chatId]?.announced) {
        if (!chatId.endsWith('@g.us')) groups[chatId] = { announced: false };
        await hello(sock, chatId, info.humans ?? 1);
      }
      await deliver(posts, tenantFor(chatId, info));
    }
  }

  async function importExport(msg, doc, chatId, tenant) {
    const fileName = doc.fileName || '';
    if (!/\.(zip|txt)$/i.test(fileName) && !/zip|text\/plain/.test(doc.mimetype || '')) return;
    try {
      const bytes = await downloadMediaMessage(msg, 'buffer', {}, { reuploadRequest: sock.updateMediaMessage });
      const text = chatTextFrom(new Uint8Array(bytes), fileName);
      const result = text ? exportToPosts(text, { chatName: chatNameFromFileName(fileName) }) : null;
      if (!result?.messages) {
        await sock.sendMessage(chatId, { text: "That file isn't a WhatsApp chat export. In the chat: tap its name → Export chat → Without media, then send the file here." });
        return;
      }
      log(`export "${fileName}": ${result.messages} messages → ${result.links} links, ${result.notes} notes`);
      const counts = await deliver(result.posts, tenant, 'whatsapp_export');
      const added = counts ? counts.accepted : null;
      await sock.sendMessage(chatId, { text: added === null
        ? `📥 Got it: ${result.links} links and ${result.notes} notes. They'll show up in hindsight shortly.`
        : `✅ Imported ${result.links} links and ${result.notes} notes${added < result.posts.length ? ` (${added} new)` : ''}. Open hindsight to see them.` });
    } catch (err) {
      log('export import failed', err.message);
      await sock.sendMessage(chatId, { text: "Couldn't read that file. Try exporting again (Without media)." });
    }
  }
}

start();
