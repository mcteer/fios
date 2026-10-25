import { parentPort, workerData } from "node:worker_threads";
import { getDocument } from "pdfjs-dist/legacy/build/pdf.mjs";
let task;
try {
  task = getDocument({
    data: new Uint8Array(workerData),
    isEvalSupported: false,
    disableFontFace: true,
    useSystemFonts: false,
    verbosity: 0,
  });
  const doc = await task.promise;
  if (doc.numPages > 100)
    throw new Error("PDF exceeds 100 pages. Attach a smaller excerpt.");
  let text = "";
  for (let i = 1; i <= doc.numPages; i++) {
    const page = await doc.getPage(i);
    const content = await page.getTextContent();
    text +=
      content.items
        .map((item) => item.str + (item.hasEOL ? "\n" : " "))
        .join("") + "\n";
    page.cleanup();
    if (text.length > 100000)
      throw new Error(
        "PDF exceeds 100,000 extracted characters. Attach a smaller excerpt.",
      );
  }
  parentPort.postMessage({ text });
} catch (error) {
  parentPort.postMessage({ error: error.message });
} finally {
  if (task) await task.destroy();
}
