import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const python =
  process.env.FIOS_AGENT_PYTHON ||
  fileURLToPath(new URL("../.venv/bin/python", import.meta.url));
const child = spawn(
  python,
  [
    "-I",
    "-B",
    "tests/fixtures/run-agent-tests.py",
  ],
  {
    cwd: root,
    stdio: "inherit",
    shell: false,
    timeout: 120_000,
    killSignal: "SIGTERM",
    // No platform grant/native guard, provider credential or service endpoint
    // is inherited. Private platform entry tests use installed mocks only.
    env: { PATH: process.env.PATH || "", HOME: process.env.HOME || "" },
  },
);
child.on("error", () => {
  console.error(
    "Agent tests could not start. Install Python 3.11 and run uv sync --locked --no-editable, or configure FIOS_AGENT_PYTHON.",
  );
  process.exitCode = 1;
});
child.on("exit", (code) => {
  process.exitCode = code ?? 1;
});
