import { createHmac, timingSafeEqual } from "node:crypto";

export function equal(a, b) {
  const aa = Buffer.from(String(a)),
    bb = Buffer.from(String(b));
  return aa.length === bb.length && timingSafeEqual(aa, bb);
}
export function signSession(secret, now = Date.now()) {
  const payload = String(now + 7 * 86400000);
  return (
    payload + "." + createHmac("sha256", secret).update(payload).digest("hex")
  );
}
export function validSession(token, secret, now = Date.now()) {
  if (!token) return false;
  const [expiry, signature] = token.split(".");
  return (
    Number(expiry) > now &&
    equal(
      signature,
      createHmac("sha256", secret)
        .update(expiry || "")
        .digest("hex"),
    )
  );
}

// Handles arbitrary network chunk boundaries, CRLF and multi-line SSE data.
export async function* sseData(body) {
  const decoder = new TextDecoder();
  let buffer = "",
    data = [];
  for await (const chunk of body) {
    buffer += decoder.decode(chunk, { stream: true });
    let pos;
    while ((pos = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, pos).replace(/\r$/, "");
      buffer = buffer.slice(pos + 1);
      if (!line) {
        if (data.length) yield data.join("\n");
        data = [];
      } else if (line.startsWith("data:"))
        data.push(line.slice(5).replace(/^ /, ""));
    }
  }
  buffer += decoder.decode();
  if (buffer.startsWith("data:")) data.push(buffer.slice(5).trim());
  if (data.length) yield data.join("\n");
}

export function buildContext(messages, attachments) {
  let count = 0,
    imageBytes = 0;
  return messages
    .filter((m) => m.role === "user" || (m.role === "assistant" && m.content))
    .map((m) => {
      const files = attachments.filter((a) => a.message_id === m.id);
      let text = m.content;
      for (const a of files.filter((a) => a.kind === "text")) {
        text += `\n\n<attached-document name=${JSON.stringify(a.name)}>\n${a.text}\n</attached-document>`;
      }
      count += text.length;
      if (count > 400000)
        throw Object.assign(
          new Error(
            "This conversation is too large for a single request. Start a new chat.",
          ),
          { status: 413 },
        );
      const images = files.filter((a) => a.kind === "image");
      imageBytes += images.reduce((sum, a) => sum + a.data.length, 0);
      if (imageBytes > 20 * 1024 * 1024)
        throw Object.assign(
          new Error(
            "Image context exceeds 20 MiB across this conversation. Start a new chat.",
          ),
          { status: 413 },
        );
      return {
        role: m.role,
        content: images.length
          ? [
              { type: "text", text },
              ...images.map((a) => ({
                type: "image_url",
                image_url: {
                  url: `data:${a.mime};base64,${Buffer.from(a.data).toString("base64")}`,
                },
              })),
            ]
          : text,
      };
    });
}
