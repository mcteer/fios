import { createServer } from "node:http";
export function mockMlx(port = 0) {
  const requests = [];
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
      return res.setHeader("Content-Type", "application/json").end(
        JSON.stringify({
          data: catalog,
        }),
      );
    if (req.url !== "/v1/chat/completions") {
      res.writeHead(404);
      return res.end();
    }
    let body = "";
    for await (const chunk of req) body += chunk;
    const data = JSON.parse(body);
    requests.push(data);
    const last = data.messages.at(-1).content;
    if (typeof last === "string" && last.includes("FAIL_UPSTREAM")) {
      res.writeHead(503);
      return res.end("Test upstream unavailable");
    }
    res.writeHead(200, { "Content-Type": "text/event-stream" });
    const slow = typeof last === "string" && last.includes("SLOW_RESPONSE");
    const pieces = [
      "Here is a small example.\n\n",
      "```javascript\n",
      'const greeting = "Hello, Fios";\n',
      "console.log(greeting);\n",
      "```\n\n",
      "**Ready to build.**",
    ];
    for (const content of pieces) {
      if (res.destroyed) break;
      res.write(
        "data: " +
          JSON.stringify({ choices: [{ delta: { content } }] }) +
          "\n\n",
      );
      await new Promise((r) => setTimeout(r, slow ? 700 : 50));
    }
    if (!res.destroyed) res.end("data: [DONE]\n\n");
  });
  return new Promise((resolve) =>
    server.listen(port, "127.0.0.1", () =>
      resolve({
        server,
        requests,
        catalog,
        url: `http://127.0.0.1:${server.address().port}/v1`,
      }),
    ),
  );
}
if (process.argv[1]?.endsWith("mock-mlx.js"))
  await mockMlx(Number(process.env.MOCK_PORT || 3322));
