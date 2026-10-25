import { defineConfig } from "@playwright/test";
import { rmSync } from "node:fs";
import { resolve } from "node:path";
for (const suffix of ["", "-shm", "-wal"])
  rmSync("./data/browser-test.sqlite" + suffix, { force: true });
export default defineConfig({
  testDir: "./tests/browser",
  fullyParallel: false,
  workers: 1,
  use: {
    baseURL: "http://127.0.0.1:3311",
    viewport: { width: 1440, height: 1000 },
    trace: "retain-on-failure",
    permissions: ["clipboard-read", "clipboard-write"],
  },
  webServer: [
    {
      command: "node tests/mock-mlx.js",
      url: "http://127.0.0.1:3322/v1/models",
      reuseExistingServer: false,
    },
    {
      command: "node server/index.js",
      url: "http://127.0.0.1:3311/health",
      reuseExistingServer: false,
      env: {
        FIOS_AGENT_PYTHON:
          resolve('tests/fixtures/web-python'),
        PORT: "3311",
        HOST: "127.0.0.1",
        DB_PATH: "./data/browser-test.sqlite",
        MLX_BASE_URL: "http://127.0.0.1:3322/v1",
        FIOS_PASSWORD: "browser-test-password",
        SESSION_SECRET: "browser-test-signing-secret-which-is-long-enough",
      },
    },
  ],
});
