import test from "node:test";
import assert from "node:assert/strict";
import {
  equal,
  signSession,
  validSession,
  buildContext,
} from "../server/lib.js";
import { openStore } from "../server/store.js";
import { parseAttachment } from "../server/attachments.js";
import { sseEvents } from "../src/stream.js";
import { samplePdf } from "./pdf-fixture.js";

const encode = (x) => new TextEncoder().encode(x);
test("session signatures expire and reject tampering", () => {
  const token = signSession("a".repeat(64), 1000);
  assert.ok(validSession(token, "a".repeat(64), 1001));
  assert.ok(!validSession(token, "b".repeat(64), 1001));
  assert.ok(!validSession(token, "a".repeat(64), 8 * 86400000));
  assert.ok(!validSession(undefined, "a".repeat(64)));
  assert.ok(equal("secret", "secret"));
  assert.ok(!equal("secret", "secreT"));
});
test("browser SSE parser preserves split event frames", async () => {
  const data = encode(
    'event: delta\ndata: {"content":"hello"}\n\nevent: done\ndata: {"status":"complete"}\n\n',
  );
  const body = new ReadableStream({
    start(c) {
      for (let i = 0; i < data.length; i += 3) c.enqueue(data.slice(i, i + 3));
      c.close();
    },
  });
  const events = [];
  for await (const x of sseEvents(body)) events.push(x);
  assert.deepEqual(events, [
    { event: "delta", data: { content: "hello" } },
    { event: "done", data: { status: "complete" } },
  ]);
});
test("SQLite stores chats and cascades message and attachment deletion", () => {
  const store = openStore(":memory:");
  const chat = store.create("model");
  const m = store.add(chat.id, "user", "hello");
  store.file(m.id, {
    name: "file.txt",
    mime: "text/plain",
    size: 4,
    kind: "text",
    text: "test",
  });
  assert.equal(
    store.detail(chat.id).messages[0].attachments[0].name,
    "file.txt",
  );
  assert.equal(store.attachments(chat.id)[0].text, "test");
  store.remove(chat.id);
  assert.equal(
    store.db.prepare("SELECT count(*) AS n FROM attachments").get().n,
    0,
  );
  assert.equal(
    store.db.prepare("SELECT count(*) AS n FROM messages").get().n,
    0,
  );
  store.db.close();
});
test("context retains documents and image data across conversation turns", () => {
  const out = buildContext(
    [
      { id: "1", role: "user", content: "Review" },
      { id: "2", role: "assistant", content: "OK" },
    ],
    [
      { message_id: "1", name: "code.js", kind: "text", text: "const x=1" },
      {
        message_id: "1",
        kind: "image",
        mime: "image/png",
        data: Buffer.from("image"),
      },
    ],
  );
  assert.match(out[0].content[0].text, /const x=1/);
  assert.match(out[0].content[1].image_url.url, /^data:image\/png;base64,/);
  assert.equal(out[1].content, "OK");
});
test("context refuses oversized aggregate input", () => {
  assert.throws(
    () =>
      buildContext(
        [{ id: "1", role: "user", content: "a".repeat(400001) }],
        [],
      ),
    /too large/,
  );
});
test("text/source upload preserves source and rejects binary/unsupported files", async () => {
  const file = (name, content, mimetype = "application/octet-stream") => ({
    originalname: name,
    buffer: Buffer.from(content),
    mimetype,
  });
  assert.equal(
    (await parseAttachment(file("test.ts", "const x = 1"))).text,
    "const x = 1",
  );
  await assert.rejects(parseAttachment(file("bad.txt", "a\0b")), /binary/);
  await assert.rejects(parseAttachment(file("bad.zip", "zip")), /use a text/);
  await assert.rejects(parseAttachment(file("empty.md", "")), /empty/);
});
test("PDF text is extracted in an isolated worker", async () => {
  const result = await parseAttachment({
    originalname: "context.pdf",
    buffer: samplePdf(),
    mimetype: "application/pdf",
  });
  assert.match(result.text, /Fios PDF attachment context/);
  assert.equal(result.kind, "text");
});
test("image type is derived from file signature, not untrusted MIME", async () => {
  const file = {
    originalname: "image.bin",
    buffer: Buffer.from([137, 80, 78, 71, 13, 10, 26, 10, 0]),
    mimetype: "text/plain",
  };
  assert.equal((await parseAttachment(file)).mime, "image/png");
});
test("attachment extraction rejects excessive text and invalid PDFs", async () => {
  await assert.rejects(
    parseAttachment({
      originalname: "big.txt",
      buffer: Buffer.from("x".repeat(100001)),
      mimetype: "text/plain",
    }),
    /100,000/,
  );
  await assert.rejects(
    parseAttachment({
      originalname: "bad.pdf",
      buffer: Buffer.from("notpdf"),
      mimetype: "application/pdf",
    }),
    /valid PDF/,
  );
});
