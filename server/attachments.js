import { Worker } from "node:worker_threads";
import { extname, basename } from "node:path";
function pdfText(buffer) {
  return new Promise((resolve, reject) => {
    const worker = new Worker(new URL("./pdf-worker.js", import.meta.url), {
      workerData: buffer,
      execArgv: [],
      resourceLimits: { maxOldGenerationSizeMb: 128 },
    });
    const timeout = setTimeout(() => {
      worker.terminate();
      reject(new Error("PDF processing timed out."));
    }, 15000);
    worker.once("message", (result) => {
      clearTimeout(timeout);
      worker.terminate();
      result.error ? reject(new Error(result.error)) : resolve(result.text);
    });
    worker.once("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
    worker.once("exit", () => {
      clearTimeout(timeout);
      reject(new Error("PDF worker exited before returning text."));
    });
  });
}
const textExtensions = new Set(
  "txt md mdx csv tsv json jsonl yaml yml toml xml html css scss js jsx ts tsx mjs cjs py rb go rs java c h cpp hpp cs swift kt sh bash zsh sql graphql gql vue svelte tex log ini conf env dockerfile makefile r lua pl php ipynb".split(
    " ",
  ),
);
function fail(message) {
  throw Object.assign(new Error(message), { status: 400 });
}
export async function parseAttachment(file) {
  const name = basename(file.originalname).slice(0, 180),
    data = file.buffer;
  const size = data.length;
  if (!size) fail(`${name} is empty.`);
  if (size > 10 * 1024 * 1024)
    fail("Each attachment must be 10 MiB or smaller.");
  const imageTypes = [
    [
      "image/png",
      data
        .subarray(0, 8)
        .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])),
    ],
    ["image/jpeg", data[0] === 255 && data[1] === 216 && data[2] === 255],
    [
      "image/webp",
      data.toString("ascii", 0, 4) === "RIFF" &&
        data.toString("ascii", 8, 12) === "WEBP",
    ],
    ["image/gif", /^GIF8[79]a/.test(data.toString("ascii", 0, 6))],
  ];
  const image = imageTypes.find(([, match]) => match);
  if (image) return { name, size, kind: "image", mime: image[0], data };
  let text;
  if (extname(name).toLowerCase() === ".pdf") {
    if (!data.toString("ascii", 0, 5).startsWith("%PDF-"))
      fail(`${name} is not a valid PDF.`);
    try {
      text = await pdfText(data);
    } catch (error) {
      fail(
        `Could not read ${name}: ${error.message}. Use an unencrypted, text-based PDF or a smaller excerpt.`,
      );
    }
    if (!text.trim())
      fail(`${name} has no extractable text. Scanned PDFs need OCR first.`);
  } else {
    const ext = extname(name).slice(1).toLowerCase();
    if (
      !textExtensions.has(ext) &&
      !textExtensions.has(name.toLowerCase()) &&
      !file.mimetype.startsWith("text/")
    )
      fail(`${name}: use a text/source file, PDF, PNG, JPEG, WebP or GIF.`);
    try {
      text = new TextDecoder("utf-8", { fatal: true }).decode(data);
    } catch {
      fail(`${name} must contain UTF-8 text.`);
    }
    if (text.includes("\0")) fail(`${name} appears to be a binary file.`);
  }
  if (text.length > 100000)
    fail(
      `${name} exceeds 100,000 extracted characters. Attach a smaller excerpt.`,
    );
  return { name, size, kind: "text", mime: "text/plain", text };
}
