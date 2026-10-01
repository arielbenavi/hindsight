import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toPosts, linksIn, platformFor, kindFor, messageText } from './convert.js';

const base = { messageId: 'ABC123', timestamp: 1790800000, chatName: 'Notes 📝', senderName: 'Ariel' };

test('owner note becomes a note with a stable id and the chat as collection', () => {
  const [note] = toPosts({ ...base, text: 'call mom', fromOwner: true });
  assert.equal(note.id, 'whatsapp:ABC123');
  assert.equal(note.kind, 'note');
  assert.equal(note.platform, 'whatsapp');
  assert.equal(note.url, 'hindsight-note:whatsapp/ABC123');
  assert.deepEqual(note.collections, ['Notes 📝']);
  assert.equal(note.source, 'whatsapp_bot');
});

test('links become saves; surrounding owner text is the caption', () => {
  const posts = toPosts({ ...base, fromOwner: true,
    text: 'try this pasta https://www.instagram.com/reel/DdyvEu1OVoH/?igsh=x and https://example.com/a.' });
  assert.equal(posts.length, 2);
  assert.equal(posts[0].platform, 'instagram');
  assert.equal(posts[0].kind, 'reel');
  assert.equal(posts[0].caption, 'try this pasta and');
  assert.equal(posts[1].platform, 'web');
  assert.equal(posts[1].kind, 'link');
  assert.equal(posts[1].url, 'https://example.com/a');
});

test("other people's text is skipped but their links are kept", () => {
  assert.deepEqual(toPosts({ ...base, fromOwner: false, text: 'my private thoughts' }), []);
  const [link] = toPosts({ ...base, fromOwner: false, senderName: 'Reut', text: 'https://x.com/a/status/1 this!' });
  assert.equal(link.platform, 'x');
  assert.equal(link.caption, null);
  assert.equal(link.shared_by, 'Reut');
});

test('helpers', () => {
  assert.equal(platformFor('https://vm.tiktok.com/ZM1/'), 'tiktok');
  assert.equal(platformFor('https://m.facebook.com/x'), 'facebook');
  assert.equal(platformFor('not a url'), null);
  assert.equal(kindFor('https://www.tiktok.com/@a/video/1'), 'video');
  assert.deepEqual(linksIn('see (https://a.com/x).'), ['https://a.com/x']);
  assert.equal(messageText({ extendedTextMessage: { text: 'hi' } }), 'hi');
  assert.equal(messageText({ imageMessage: { caption: 'pic note' } }), 'pic note');
  assert.equal(messageText(null), '');
});
