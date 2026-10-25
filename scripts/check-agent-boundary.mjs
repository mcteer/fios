import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { join, relative } from "node:path";
const root = fileURLToPath(new URL("../", import.meta.url));
const failures = [];
async function walk(path) {
  for (const entry of await readdir(path, { withFileTypes: true })) {
    const full = join(path, entry.name),
      name = relative(root, full);
    if (entry.isDirectory()) {
      if (!["__pycache__"].includes(entry.name)) await walk(full);
      continue;
    }
    if (!/\.(js|jsx|py|mjs)$/.test(name)) continue;
    const text = await readFile(full, "utf8");
    const harness = name.startsWith("src/agent/fios_agent/");
    if (
      !harness &&
      /chat\/completions|\.chat\.completions\.|OpenAIChatModel|AsyncOpenAI|new OpenAI\b/.test(
        text,
      )
    )
      failures.push(name + ": inference outside harness");
    if (
      name.startsWith("src/") &&
      !name.startsWith("src/agent/") &&
      /(?:from\s*|import\s*\()["'][^"']*agent\//.test(text)
    )
      failures.push(name + ": browser imports agent");
    if (!harness && /html\.duckduckgo\.com|\bddgs\b|web_search\s*\(/.test(text))
      failures.push(name + ': search orchestration outside harness');
    if (harness && /\bTool\s*\(/.test(text) && name !== 'src/agent/fios_agent/web/tool.py')
      failures.push(name + ': unexpected tool registration');
    if (name === 'src/agent/fios_agent/web/tool.py' &&
        (!text.includes("Tool(web_search,name='web_search'") || !text.includes('max_retries=0') || !text.includes('sequential=True') || !text.includes('requires_approval=False')))
      failures.push(name + ': search tool policy changed');
    if (
      harness &&
      /@\w+\.tool\b|MCPServer|FallbackModel|instrument_all\(|logfire\.configure\(/.test(
        text,
      )
    )
      failures.push(name + ": tools/fallback/telemetry");
  }
}
await walk(join(root, "src"));
await walk(join(root, "server"));
const py = await readFile(join(root, "pyproject.toml"), "utf8");
if (!py.includes("pydantic-ai-slim[openai]==") || /"pydantic-ai["=\[]/.test(py))
  failures.push("pyproject.toml: unexpected distribution");
if (failures.length) {
  console.error(failures.join("\n"));
  process.exitCode = 1;
} else console.log("Agent inference boundary checks passed.");
