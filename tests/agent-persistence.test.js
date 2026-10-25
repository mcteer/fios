import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { openStore } from "../server/store.js";
import { agentApp } from "./agent-support.js";
import { samplePdf } from "./pdf-fixture.js";

test("legacy SQLite records/blobs survive upgrade, real Agent continuation, restart and deletion", async () => {
  const fixture = JSON.parse(
    readFileSync(new URL("fixtures/legacy-chat.json", import.meta.url)),
  );
  const dir = mkdtempSync(join(tmpdir(), "fios-legacy-")),
    database = join(dir, "legacy.sqlite");
  const store = openStore(database);
  store.db
    .prepare("INSERT INTO chats VALUES(?,?,?,?)")
    .run(...["id", "title", "model", "updated"].map((k) => fixture.chat[k]));
  for (const m of fixture.messages)
    store.db
      .prepare("INSERT INTO messages VALUES(?,?,?,?,?,?,?)")
      .run(
        m.id,
        fixture.chat.id,
        m.role,
        m.content,
        m.status,
        m.created,
        m.model,
      );
  for (const a of fixture.attachments)
    store.db
      .prepare("INSERT INTO attachments VALUES(?,?,?,?,?,?,?,?)")
      .run(
        a.id,
        a.message_id,
        a.name,
        a.mime,
        a.size,
        a.kind,
        a.text,
        a.data_base64 ? Buffer.from(a.data_base64, "base64") : null,
      );
  const before = {
    messages: store.messages(fixture.chat.id),
    files: store.attachments(fixture.chat.id),
  };
  store.db.close();
  const app = await agentApp({ database, directory: dir });
  try {
    const detail = await (
      await app.request(`/api/chats/${fixture.chat.id}`)
    ).json();
    assert.deepEqual(
      detail.messages.map(({ attachments, web, ...m }) => m),
      before.messages.map((m) => ({ ...m })),
    );
    const stream = await (
      await app.send(fixture.chat.id, "Continue the old review.")
    ).text();
    assert.match(stream, /event: done/);
    const sent = app.mock.requests[0].messages;
    assert.equal(sent.filter((m) => m.role === "system").length, 1);
    assert.equal(
      sent.filter((m) => m.content === "Continue the old review.").length,
      1,
    );
    assert.match(sent[1].content, /const legacy = 42/);
    assert.match(sent[1].content, /Extracted legacy PDF text/);
    assert.equal(sent[3].content[1].type, "image_url");
    const image = sent[3].content[1].image_url.url;
    assert.equal(
      image,
      "data:image/png;base64," + fixture.attachments[2].data_base64,
    );
    await app.stop();
    const check = openStore(database);
    assert.deepEqual(
      check.messages(fixture.chat.id).slice(0, 4),
      before.messages,
    );
    assert.deepEqual(check.attachments(fixture.chat.id), before.files);
    check.add(
      fixture.chat.id,
      "assistant",
      "saved before restart",
      "streaming",
      "test/coding-model",
    );
    check.db.close();
    await app.start();
    const recovered = await (
      await app.request(`/api/chats/${fixture.chat.id}`)
    ).json();
    assert.equal(recovered.messages.at(-1).status, "interrupted");
    assert.equal(
      (await app.request(`/api/chats/${fixture.chat.id}`, { method: "DELETE" }))
        .status,
      204,
    );
    await app.stop();
    const removed = openStore(database);
    assert.equal(
      removed.db.prepare("SELECT count(*) AS n FROM attachments").get().n,
      0,
    );
    removed.db.close();
  } finally {
    await app.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("actual harness retains reasoning only transiently and supplies validated PDF/text/image context", async () => {
  const app = await agentApp();
  try {
    const c = await app.chat();
    const image = Buffer.from("89504e470d0a1a0a", "hex");
    const stream = await (
      await app.send(c.id, "REASONING_RESPONSE", "test/coding-model", [
        ["code.js", "const value = 7;"],
        ["context.pdf", samplePdf(), "application/pdf"],
        ["image.png", image, "image/png"],
      ])
    ).text();
    assert.match(stream, /event: reasoning/);
    const detail = await (await app.request(`/api/chats/${c.id}`)).json();
    assert.equal(detail.messages.at(-1).status, "complete");
    assert.doesNotMatch(detail.messages.at(-1).content, /private thought/);
    const content = app.mock.requests[0].messages.at(-1).content;
    assert.match(content[0].text, /const value = 7/);
    assert.equal(
      content[1].image_url.url,
      "data:image/png;base64," + image.toString("base64"),
    );
    assert.equal(
      (await app.send(c.id, "reject image history", "test/text-only")).status,
      400,
    );
    await (await app.send(c.id, "Next question")).text();
    assert.doesNotMatch(
      JSON.stringify(app.mock.requests[1]),
      /private thought/,
    );
  } finally {
    await app.close();
  }
});
