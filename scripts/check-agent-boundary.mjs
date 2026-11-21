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
    if (!/\.(js|jsx|py|mjs|swift)$/.test(name)) continue;
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
    if (!harness && /html\.duckduckgo\.com|http:\/\/searxng:8080\/search|\bddgs\b|web_search\s*\(/.test(text))
      failures.push(name + ': search orchestration outside harness');
    if (name.startsWith('src/agent/fios_agent/platform_') && /\b(?:subprocess|sqlite3)\b|\b(?:eval|exec)\s*\(|os\.(?:system|popen)\s*\(/.test(text))
      failures.push(name + ': host tools/database/code execution in private model worker');
    if (name === 'src/agent/fios_agent/platform_worker.py' &&
        (!text.includes("web_search='off'") || !text.includes('retries=0,trust_env=False') || !text.includes('await check_native_guard(self.command)')))
      failures.push(name + ': platform worker isolation/guard changed');
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
await walk(join(root, "platform/studio/Sources"));
await walk(join(root, "platform/studio/sandbox"));
const py = await readFile(join(root, "pyproject.toml"), "utf8");
if (!py.includes("pydantic-ai-slim[openai]==") || /"pydantic-ai["=\[]/.test(py))
  failures.push("pyproject.toml: unexpected distribution");
if (failures.length) {
  console.error(failures.join("\n"));
  process.exitCode = 1;
} else console.log("Agent inference boundary checks passed.");
