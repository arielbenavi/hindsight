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

import fs from 'node:fs';
import path from 'node:path';
import pino from 'pino';
import qrcode from 'qrcode-terminal';
import makeWASocket, {
  Browsers, DisconnectReason, extractMessageContent, fetchLatestBaileysVersion,
  jidNormalizedUser, useMultiFileAuthState,
} from 'baileys';
import { messageText, toPosts } from './convert.js';

const INGEST_URL = process.env.HINDSIGHT_INGEST_URL;
if (!INGEST_URL) { console.error('Set HINDSIGHT_INGEST_URL (see README.md)'); process.exit(1); }

const STATE = path.resolve('state');
fs.mkdirSync(STATE, { recursive: true });
const GROUPS_FILE = path.join(STATE, 'groups.json');
const OUTBOX_FILE = path.join(STATE, 'outbox.jsonl');
const groups = fs.existsSync(GROUPS_FILE) ? JSON.parse(fs.readFileSync(GROUPS_FILE, 'utf8')) : {};
const saveGroups = () => fs.writeFileSync(GROUPS_FILE, JSON.stringify(groups, null, 1));

const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);
/** The phone/user part of a JID, so "123@s.whatsapp.net", "123:4@…" and "123@lid" compare by user. */
const userOf = (jid) => (jid ? jidNormalizedUser(String(jid)).split('@')[0] : '');

// ── delivery to hindsight (with an outbox for when the connector is down) ──

async function deliver(posts) {
  if (!posts.length) return;
  try {
    const res = await fetch(INGEST_URL, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ source: 'whatsapp_bot', posts }),
    });
    if (!res.ok) throw new Error(`ingest ${res.status}`);
    const counts = await res.json();
    log(`→ hindsight: ${posts.length} posts, accepted ${counts.accepted}, duplicates ${counts.duplicates}`);
    await flushOutbox();
  } catch (err) {
    log('ingest failed, queued:', err.message);
    fs.appendFileSync(OUTBOX_FILE, posts.map((p) => JSON.stringify(p)).join('\n') + '\n');
  }
}

let flushing = false;
async function flushOutbox() {
  if (flushing || !fs.existsSync(OUTBOX_FILE)) return;
  const lines = fs.readFileSync(OUTBOX_FILE, 'utf8').split('\n').filter(Boolean);
  if (!lines.length) return;
  flushing = true;
  try {
    const res = await fetch(INGEST_URL, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ source: 'whatsapp_bot', posts: lines.map((l) => JSON.parse(l)) }),
    });
    if (res.ok) { fs.unlinkSync(OUTBOX_FILE); log(`outbox flushed (${lines.length})`); }
  } catch { /* try again next time */ } finally { flushing = false; }
}

// ── chats: who owns each one, what it's called ──

async function chatInfo(sock, chatId) {
  if (!chatId.endsWith('@g.us')) return { name: null, owner: chatId, humans: 1 };
  let info = groups[chatId];
  if (!info?.name || info.humans == null) {
    try {
      const meta = await sock.groupMetadata(chatId);
      const me = userOf(sock.user?.id);
      const humans = meta.participants.filter((p) => userOf(p.id) !== me && userOf(p.phoneNumber) !== me);
      info = { ...info, name: meta.subject, humans: humans.length };
      // A group with one person besides the bot is that person's notes group.
      if (!info.owner && humans.length === 1) info.owner = humans[0].phoneNumber || humans[0].id;
      groups[chatId] = info; saveGroups();
    } catch (err) { log('groupMetadata failed', err.message); info = info || {}; }
  }
  return info;
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
    version, auth: state, browser: Browsers.macOS('hindsight'),
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
    if (connection === 'open') { log(`connected as ${sock.user?.id}`); flushOutbox(); }
    if (connection === 'close') {
      const code = lastDisconnect?.error?.output?.statusCode;
      if (code === DisconnectReason.loggedOut) {
        log('Logged out (or banned). Delete auth/ and link again.'); process.exit(2);
      }
      log(`connection closed (${code}), reconnecting…`); setTimeout(start, 3000);
    }
  });

  // Added to a group: remember who added us (the owner) and say hello once.
  sock.ev.on('group-participants.update', async ({ id, author, participants, action }) => {
    const me = userOf(sock.user?.id);
    const ids = participants.map((p) => (typeof p === 'string' ? p : p.id || p.phoneNumber));
    if (action !== 'add' || !ids.some((p) => userOf(p) === me)) return;
    groups[id] = { ...groups[id], owner: author || groups[id]?.owner, humans: undefined };
    saveGroups();
    const info = await chatInfo(sock, id);
    log(`added to "${info.name}" by ${author} (${info.humans} people)`);
    await hello(sock, id, info.humans);
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
      const text = messageText(extractMessageContent(msg.message));
      if (!text) continue;
      const info = await chatInfo(sock, chatId);
      const sender = msg.key.participant || chatId;
      const senderAlt = msg.key.participantAlt || msg.key.participantPn;
      const fromOwner = info.humans <= 1 || [sender, senderAlt].some((j) => j && userOf(j) === userOf(info.owner));
      const posts = toPosts({
        text, messageId: msg.key.id, timestamp: Number(msg.messageTimestamp) || Date.now() / 1000,
        fromOwner, chatName: info.name, senderName: msg.pushName || null,
      });
      log(`${info.name ?? 'DM'}: ${posts.length} posts from ${fromOwner ? 'owner' : 'someone else'}`);
      if (!chatId.endsWith('@g.us') && !groups[chatId]?.announced) {
        groups[chatId] = { announced: false }; await hello(sock, chatId, 1);
      }
      await deliver(posts);
    }
  }
}

start();
