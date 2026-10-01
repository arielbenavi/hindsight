// Reads a WhatsApp "Export chat" file (the `_chat.txt`, or the .zip holding it)
// that a user sent to the bot. Same rules as the app's WhatsAppExportParser.swift:
// links → saves, the owner's plain text → notes, other people's text skipped.
// Note ids use the same FNV-1a hash as the app, so importing the same export in
// the app and via the bot doesn't create duplicates (when both run in the same
// time zone, since export times have no zone).
//
// Export formats differ by phone and locale, e.g.
//   iOS:     `[30/09/2026, 14:27:03] Ariel: text`   `[9/30/26, 2:27:03 PM] Ariel: text`
//   Android: `30/09/2026, 14:27 - Ariel: text`       `2026-09-30, 14:27 - Ariel: text`

import { unzipSync, strFromU8 } from 'fflate';
import { linksIn, platformFor, kindFor } from './convert.js';

const HEADERS = [
  /^\[(\d{1,4}[/.-]\d{1,2}[/.-]\d{1,4}),?\s+(\d{1,2}:\d{2}(?::\d{2})?(?:\s?[AaPp]\.?\s?[Mm]\.?)?)\]\s?/,
  /^(\d{1,4}[/.-]\d{1,2}[/.-]\d{1,4}),?\s+(\d{1,2}:\d{2}(?::\d{2})?(?:\s?[AaPp]\.?\s?[Mm]\.?)?)\s?[-–]\s/,
];

/** The chat text from an export file's bytes (zip or plain text), or null. */
export function chatTextFrom(bytes, fileName = '') {
  const isZip = bytes[0] === 0x50 && bytes[1] === 0x4b; // "PK"
  if (!isZip) return /\.txt$/i.test(fileName) || !fileName ? strFromU8(bytes) : null;
  const files = unzipSync(bytes, { filter: (f) => /\.txt$/i.test(f.name) });
  const name = Object.keys(files).find((n) => n.split('/').pop() === '_chat.txt') ?? Object.keys(files)[0];
  return name ? strFromU8(files[name]) : null;
}

export function messagesIn(text) {
  const lines = text.replace(/[‎‏]/g, '').split(/\r?\n/);
  const header = HEADERS.find((h) => lines.slice(0, 50).some((l) => h.test(l)));
  if (!header) return [];
  const raw = [];
  for (const line of lines) {
    const m = line.match(header);
    if (m) raw.push({ date: m[1], time: m[2], rest: line.slice(m[0].length) });
    else if (raw.length) raw[raw.length - 1].rest += '\n' + line;
  }
  const order = dateOrder(raw.map((r) => r.date), raw.some((r) => /m/i.test(r.time)));
  return raw.flatMap(({ date, time, rest }) => {
    const colon = rest.indexOf(': ');
    if (colon < 0) return []; // system message
    const text = rest.slice(colon + 2);
    if (isSystemOrMedia(text)) return [];
    return [{ date: toDate(date, time, order), sender: rest.slice(0, colon).trim(), text }];
  });
}

function isSystemOrMedia(text) {
  const t = text.toLowerCase().trim();
  return !t || t.startsWith('<attached:') || t.includes('<media omitted>')
    || /^(image|video|audio|sticker|document|gif) omitted/.test(t)
    || t === 'this message was deleted' || t === 'you deleted this message'
    || t.includes('messages and calls are end-to-end encrypted');
}

/** Whoever wrote the most; on a tie, whoever wrote first. */
export function mostFrequentSender(messages) {
  const counts = new Map();
  for (const { sender } of messages) if (sender) counts.set(sender, (counts.get(sender) ?? 0) + 1);
  let best = null;
  for (const [sender, n] of counts) if (best === null || n > counts.get(best)) best = sender; // Map keeps first-seen order
  return best;
}

export function dateOrder(dates, usesAMPM = false) {
  let dayFirst = false, monthFirst = false;
  for (const d of dates) {
    const p = d.split(/[/.-]/).map(Number);
    if (p.length !== 3 || p.some(Number.isNaN)) continue;
    if (p[0] > 31) return 'yearFirst';
    if (p[0] > 12) dayFirst = true;
    if (p[1] > 12) monthFirst = true;
  }
  if (dayFirst !== monthFirst) return dayFirst ? 'dayFirst' : 'monthFirst';
  return usesAMPM ? 'monthFirst' : 'dayFirst';
}

function toDate(date, time, order) {
  const p = date.split(/[/.-]/).map(Number);
  if (p.length !== 3) return null;
  let [day, month, year] = order === 'dayFirst' ? [p[0], p[1], p[2]]
    : order === 'monthFirst' ? [p[1], p[0], p[2]] : [p[2], p[1], p[0]];
  if (year < 100) year += 2000;
  const t = time.toLowerCase().replace(/\./g, '');
  const clock = t.replace(/[^\d:]/g, '').split(':').map(Number);
  if (clock.length < 2) return null;
  let hour = clock[0];
  if (t.includes('pm') && hour < 12) hour += 12;
  if (t.includes('am') && hour === 12) hour = 0;
  if ((month < 1 || month > 12) && day >= 1 && day <= 12) [day, month] = [month, day];
  return new Date(year, month - 1, day, hour, clock[1], clock[2] ?? 0);
}

/** Same as WhatsAppExportParser.noteURL: a stable made-up permalink for a note. */
export function noteURL(date, text) {
  const stamp = date ? String(Math.floor(date.getTime() / 1000)) : '0';
  let hash = 1469598103934665603n;
  for (const byte of new TextEncoder().encode(`${stamp}|${text}`)) {
    hash = ((hash ^ BigInt(byte)) * 1099511628211n) & 0xffffffffffffffffn;
  }
  return `hindsight-note:whatsapp/${stamp}-${hash.toString(36)}`;
}

/** Contract posts from an export's text. `chatName` becomes the collection. */
export function exportToPosts(text, { chatName = null } = {}) {
  const messages = messagesIn(text);
  const owner = mostFrequentSender(messages);
  const collections = chatName ? [chatName] : [];
  const posts = [];
  let links = 0, notes = 0, othersSkipped = 0;
  for (const m of messages) {
    const savedAt = m.date ? m.date.toISOString() : null;
    const urls = linksIn(m.text);
    for (const url of urls) {
      posts.push({ platform: platformFor(url) ?? 'web', url, kind: kindFor(url), author: null, caption: null,
        collections, saved_at: savedAt, source: 'whatsapp_export' });
      links += 1;
    }
    const note = m.text.replace(/https?:\/\/[^\s<>"]+/g, '').trim();
    if (!note) continue;
    if (owner && m.sender !== owner) { othersSkipped += 1; continue; }
    if (!urls.length) {
      const url = noteURL(m.date, note);
      posts.push({ platform: 'whatsapp', url, kind: 'note', author: m.sender,
        caption: note, collections, saved_at: savedAt, source: 'whatsapp_export' });
      notes += 1;
    } else {
      posts[posts.length - 1].caption = note.replace(/\s+/g, ' ');
    }
  }
  return { posts, messages: messages.length, links, notes, othersSkipped };
}

/** "WhatsApp Chat - Notes.zip" / "WhatsApp Chat with Notes.txt" → "Notes". */
export function chatNameFromFileName(fileName = '') {
  const m = fileName.match(/^WhatsApp Chat (?:-|with)\s*(.+?)(?:\.(?:zip|txt))?$/i);
  return m ? m[1].trim() : null;
}
