import { test } from 'node:test';
import assert from 'node:assert/strict';
import { zipSync, strToU8 } from 'fflate';
import { chatTextFrom, chatNameFromFileName, dateOrder, exportToPosts, messagesIn, mostFrequentSender, noteURL } from './exportParser.js';

const IOS = `[28/09/2026, 09:12:01] Ariel: ‎Messages and calls are end-to-end encrypted.
[28/09/2026, 09:13:10] Ariel: call mom
[28/09/2026, 09:14:00] Ariel: try this https://www.instagram.com/reel/DdyvEu1OVoH/?igsh=abc
[28/09/2026, 09:15:00] Ariel: groceries:
eggs
oat milk
[28/09/2026, 09:16:00] Ariel: ‎image omitted
[28/09/2026, 09:17:00] Reut: my secret
[28/09/2026, 09:18:00] Reut: https://x.com/a/status/42`;

test('iOS export: links, owner notes (multi-line), media and system lines skipped', () => {
  const r = exportToPosts(IOS, { chatName: 'Notes' });
  assert.equal(r.messages, 5);
  assert.equal(r.links, 2);
  assert.equal(r.notes, 2);
  assert.equal(r.othersSkipped, 1);
  const reel = r.posts.find((p) => p.platform === 'instagram');
  assert.equal(reel.url, 'https://www.instagram.com/reel/DdyvEu1OVoH/');
  assert.equal(reel.caption, 'try this');
  assert.deepEqual(reel.collections, ['Notes']);
  assert.ok(r.posts.some((p) => p.kind === 'note' && p.caption === 'groceries:\neggs\noat milk'));
  assert.ok(!r.posts.some((p) => p.caption === 'my secret'));
  assert.ok(r.posts.every((p) => p.source === 'whatsapp_export'));
});

test('Android + US formats and date order', () => {
  const android = messagesIn('9/30/26, 2:27 PM - Ariel: hi\n10/1/26, 9:05 AM - Ariel: yo');
  assert.equal(android.length, 2);
  assert.equal(android[0].date.getMonth(), 8);
  assert.equal(android[0].date.getDate(), 30);
  assert.equal(android[0].date.getHours(), 14);
  assert.equal(dateOrder(['13/02/2026']), 'dayFirst');
  assert.equal(dateOrder(['02/13/2026']), 'monthFirst');
  assert.equal(dateOrder(['2026-09-30']), 'yearFirst');
  assert.equal(dateOrder(['01/02/2026'], true), 'monthFirst');
});

test('note ids match the app (WhatsAppExportParser.noteURL) and re-imports are stable', () => {
  assert.equal(noteURL(null, 'call mom'), 'hindsight-note:whatsapp/0-3pkzly6frbqy8');
  assert.deepEqual(exportToPosts(IOS).posts.map((p) => p.url), exportToPosts(IOS).posts.map((p) => p.url));
});

test('owner tie → whoever wrote first', () => {
  const m = ['Ariel', 'Reut', 'Reut', 'Ariel'].map((sender) => ({ sender }));
  assert.equal(mostFrequentSender(m), 'Ariel');
});

test('reads _chat.txt from a zip, or plain text; rejects other files', () => {
  const zip = zipSync({ '_chat.txt': strToU8(IOS), 'IMG-1.jpg': new Uint8Array([1, 2]) });
  assert.equal(chatTextFrom(zip, 'WhatsApp Chat - Notes.zip'), IOS);
  assert.equal(chatTextFrom(strToU8(IOS), 'WhatsApp Chat with Notes.txt'), IOS);
  assert.equal(chatTextFrom(strToU8('%PDF'), 'cv.pdf'), null);
  assert.equal(exportToPosts('just some text').messages, 0);
});

test('chat name from the export file name', () => {
  assert.equal(chatNameFromFileName('WhatsApp Chat - Notes 📝.zip'), 'Notes 📝');
  assert.equal(chatNameFromFileName('WhatsApp Chat with Mom.txt'), 'Mom');
  assert.equal(chatNameFromFileName('photo.zip'), null);
});
