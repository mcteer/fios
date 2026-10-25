import { createServer } from "node:http";

export function mockMlx(port = 0) {
  const requests = [],
    connections = [];
  const catalog = [
    {
      id: "test/coding-model",
      loaded: true,
      capabilities: ["chat", "vision", "streaming"],
    },
    { id: "test/text-only", loaded: true, capabilities: ["chat"] },
    { id: "test/image-generator", capabilities: ["image"] },
  ];
  const server = createServer(async (req, res) => {
    if (req.url === "/v1/models")
      return res
        .setHeader("Content-Type", "application/json")
        .end(JSON.stringify({ data: catalog }));
    if (req.url !== "/v1/chat/completions" || req.method !== "POST") {
      res.writeHead(404);
      return res.end();
    }
    let body = "";
    for await (const chunk of req) body += chunk;
    const data = JSON.parse(body);
    requests.push(data);
    const connection = { started: Date.now(), closed: null, finished: false };
    connections.push(connection);
    res.on("close", () => {
      connection.closed = Date.now();
    });
    const last = data.messages.at(-1).content;
    const text =
      typeof last === "string"
        ? last
        : last
            .filter((p) => p.type === "text")
            .map((p) => p.text)
            .join("\n");
    if (text.includes("FAIL_UPSTREAM") || text.includes("RATE_LIMIT")) {
      res.writeHead(text.includes("RATE_LIMIT") ? 429 : 503);
      return res.end("Test upstream unavailable");
    }
    res.writeHead(200, { "Content-Type": "text/event-stream" });
    res.flushHeaders();
    if (text.includes("NO_FIRST_TOKEN")) return;
    const chunk = (delta, finish_reason = null) => ({
      id: "chatcmpl-mock",
      object: "chat.completion.chunk",
      created: 1,
      model: data.model,
      choices: [{ index: 0, delta, finish_reason }],
    });
    const emit = (value) =>
      res.write("data: " + JSON.stringify(value) + "\n\n");
    if (text.includes("OUTPUT_LIMIT")) {
      emit(chunk({ content: "x".repeat(500001) }));
      return res.end("data: [DONE]\n\n");
    }
    if (text.includes("EMPTY_STREAM")) return res.end();
    if (text.includes("MALFORMED_STREAM")) return res.end("data: {invalid\n\n");
    if (text.includes("TOOL_RESPONSE")) {
      emit(
        chunk(
          {
            tool_calls: [
              {
                index: 0,
                id: "tool-1",
                type: "function",
                function: { name: "not_allowed", arguments: "{}" },
              },
            ],
          },
          "tool_calls",
        ),
      );
      return res.end("data: [DONE]\n\n");
    }
    if (text.includes("REASONING_RESPONSE")) {
      emit(chunk({ reasoning_content: "A private thought. " }));
      emit(chunk({ reasoning_content: "Now the answer." }));
    }
    const pieces = [
      "Here is a small example.\n\n",
      "```javascript\n",
      'const greeting = "Hello, Fios";\n',
      "console.log(greeting);\n",
      "```\n\n",
      "**Ready to build.**",
    ];
    for (const content of pieces) {
      if (res.destroyed) return;
      emit(chunk({ content }));
      if (text.includes("PARTIAL_STREAM")) return res.end();
      await new Promise((r) =>
        setTimeout(r, text.includes("SLOW_RESPONSE") ? 700 : 50),
      );
    }
    if (res.destroyed) return;
    if (!text.includes("DONE_ONLY")) emit(chunk({}, "stop"));
    if (text.includes("USAGE_RESPONSE"))
      emit({
        id: "chatcmpl-mock",
        object: "chat.completion.chunk",
        created: 1,
        model: data.model,
        choices: [],
        usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
      });
    if (!text.includes("MISSING_SENTINEL")) res.write("data: [DONE]\n\n");
    connection.finished = true;
    res.end();
  });
  return new Promise((resolve) =>
    server.listen(port, process.env.MOCK_HOST || "127.0.0.1", () =>
      resolve({
        server,
        requests,
        connections,
        catalog,
        addPeer(id = "test/coding-model@studio-a") {
          catalog.push({
            id,
            loaded: true,
            capabilities: ["chat", "vision", "streaming"],
            lan_peer: "studio-a",
          });
          return id;
        },
        url: `http://127.0.0.1:${server.address().port}/v1`,
      }),
    ),
  );
}
if (process.argv[1]?.endsWith("mock-mlx.js"))
  await mockMlx(Number(process.env.MOCK_PORT || 3322));
