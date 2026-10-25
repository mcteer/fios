import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { mockMlx } from "./mock-mlx.js";

test("synthetic legacy fixture has stable IDs and verified text/image hashes", () => {
  const fixture = JSON.parse(
    readFileSync(new URL("fixtures/legacy-chat.json", import.meta.url)),
  );
  assert.equal(fixture.messages.length, 4);
  assert.equal(new Set(fixture.messages.map((m) => m.id)).size, 4);
  assert.equal(fixture.messages.at(-1).status, "interrupted");
  for (const attachment of fixture.attachments) {
    const bytes =
      attachment.kind === "image"
        ? Buffer.from(attachment.data_base64, "base64")
        : Buffer.from(attachment.text);
    assert.equal(
      createHash("sha256").update(bytes).digest("hex"),
      attachment.sha256,
    );
    assert.equal(bytes.length, attachment.size);
    assert.ok(fixture.messages.some((m) => m.id === attachment.message_id));
  }
});

test("mock supports peer models, SDK chunks, usage/reasoning and corruption without real inference", async () => {
  const mock = await mockMlx();
  try {
    const model = mock.addPeer();
    assert.ok(
      (await (await fetch(mock.url + "/models")).json()).data.some(
        (m) => m.id === model,
      ),
    );
    for (const marker of [
      "normal",
      "DONE_ONLY",
      "USAGE_RESPONSE",
      "REASONING_RESPONSE",
      "MISSING_SENTINEL",
      "PARTIAL_STREAM",
      "MALFORMED_STREAM",
      "EMPTY_STREAM",
      "TOOL_RESPONSE",
      "FAIL_UPSTREAM",
      "RATE_LIMIT",
    ]) {
      const response = await fetch(mock.url + "/chat/completions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          model,
          messages: [{ role: "user", content: marker }],
          stream: true,
        }),
      });
      const body = await response.text();
      if (marker === "FAIL_UPSTREAM") assert.equal(response.status, 503);
      else if (marker === "RATE_LIMIT") assert.equal(response.status, 429);
      else {
        assert.equal(response.status, 200);
        if (marker === "EMPTY_STREAM") assert.equal(body, "");
        else if (marker === "MALFORMED_STREAM") assert.match(body, /invalid/);
        else {
          assert.equal(
            body.includes("[DONE]"),
            !["MISSING_SENTINEL", "PARTIAL_STREAM"].includes(marker),
          );
          const chunk = JSON.parse(body.split("\n")[0].slice(6));
          assert.equal(chunk.model, model);
          assert.equal(chunk.choices[0].index, 0);
        }
        if (marker === "USAGE_RESPONSE")
          assert.match(body, /"choices":\[\],"usage"/);
        if (marker === "REASONING_RESPONSE")
          assert.match(body, /reasoning_content/);
      }
    }
    assert.equal(mock.requests.length, 11);
    assert.equal(mock.connections.length, 11);
    assert.ok(mock.requests.every((r) => r.model === model));
  } finally {
    mock.server.closeAllConnections();
    await new Promise((r) => mock.server.close(r));
  }
});
