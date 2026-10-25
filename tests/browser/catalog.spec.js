import { test, expect } from "@playwright/test";

async function login(page) {
  await page.clock.install();
  await page.goto("/");
  await page
    .getByLabel("Access password", { exact: true })
    .fill("browser-test-password");
  await page.getByRole("button", { name: "Enter workspace" }).click();
  await expect(
    page.getByRole("button", { name: "Choose model" }),
  ).toContainText("coding-model");
  await page.getByRole("button", { name: "Choose model" }).click();
  await expect(page.locator(".model-menu")).toBeVisible();
  await page.waitForLoadState("networkidle");
  await page.clock.runFor(100);
}
const coding = {
  id: "test/coding-model",
  loaded: true,
  capabilities: ["chat", "vision"],
};
const other = { id: "test/new-model", loaded: false, capabilities: ["chat"] };
async function poll(page) {
  // Let network responses settle before advancing across the 12s request deadline.
  await page.clock.runFor(100);
  await page.clock.fastForward(30_000);
  await page.clock.runFor(100);
}

test("catalog automatically adds/removes models, clears stale selection and recovers from outage", async ({
  page,
}) => {
  await login(page);
  let catalog = [coding, other],
    failure = false,
    requests = 0;
  await page.route("**/api/models", async (route) => {
    requests++;
    await route.fulfill({
      status: failure ? 502 : 200,
      json: failure ? { error: "Test gateway offline" } : { models: catalog },
    });
  });
  // Filling closes the popup; reopen once, then await the new catalog's render.
  await page
    .getByRole("textbox", { name: "Message Fios" })
    .fill("Preserve this unsent draft");
  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: "Choose model" }).click();
  await expect(
    page.locator(".model-option").filter({ hasText: "new-model" }),
  ).toBeVisible();
  catalog = [
    coding,
    other,
    { id: "test/added-by-poll", capabilities: ["chat"] },
  ];
  await poll(page);
  await expect(
    page.locator(".model-option").filter({ hasText: "added-by-poll" }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Choose model" }),
  ).toContainText("coding-model");

  catalog = [other];
  await poll(page);
  await expect(
    page.locator(".model-option").filter({ hasText: "coding-model" }),
  ).toHaveCount(0);
  await expect(
    page.getByRole("button", { name: "Choose model" }),
  ).toContainText("Choose a model");
  await expect(
    page.getByRole("button", { name: "Send message", exact: true }),
  ).toBeDisabled();
  await expect
    .poll(() => page.evaluate(() => localStorage.getItem("fios-model")))
    .toBeNull();
  await page.locator(".model-option").filter({ hasText: "new-model" }).click();
  await expect(
    page.getByRole("button", { name: "Choose model" }),
  ).toContainText("new-model");

  failure = true;
  await poll(page);
  await expect(
    page.getByRole("button", { name: "Choose model" }),
  ).toContainText("Models unavailable");
  await expect(page.getByRole("alert")).toContainText("Retrying automatically");
  await expect(
    page.getByRole("button", { name: "Send message", exact: true }),
  ).toBeDisabled();
  failure = false;
  await poll(page);
  await expect(
    page.getByRole("button", { name: "Choose model" }),
  ).toContainText("new-model");
  await expect(page.getByRole("alert")).toHaveCount(0);
  await expect(
    page.getByRole("button", { name: "Send message", exact: true }),
  ).toBeEnabled();

  catalog = [];
  await poll(page);
  await expect(
    page.getByRole("button", { name: "Choose model" }),
  ).toContainText("Choose a model");
  await page.getByRole("button", { name: "Choose model" }).click();
  await expect(page.getByText("No chat models available.")).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Send message", exact: true }),
  ).toBeDisabled();
  await expect(page.getByRole("textbox", { name: "Message Fios" })).toHaveValue(
    "Preserve this unsent draft",
  );
  expect(requests).toBeGreaterThanOrEqual(5);
});

test("refreshes on picker open, focus, visibility and reconnect, without polling hidden tabs", async ({
  page,
}) => {
  await login(page);
  let requests = 0;
  await page.route("**/api/models", async (route) => {
    const revision = ++requests;
    await route.fulfill({
      json: {
        models: [
          coding,
          { id: `test/refresh-${revision}`, capabilities: ["chat"] },
        ],
      },
    });
  });
  async function expectRefresh(trigger) {
    await page.clock.runFor(100);
    const before = requests;
    await trigger();
    await expect.poll(() => requests).toBeGreaterThan(before);
    await expect(
      page.locator(".model-option").filter({ hasText: `refresh-${requests}` }),
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Choose model" }),
    ).toContainText("coding-model");
  }
  await expectRefresh(() =>
    page.evaluate(() => window.dispatchEvent(new Event("focus"))),
  );
  await expectRefresh(() =>
    page.evaluate(() => window.dispatchEvent(new Event("online"))),
  );
  await page.clock.runFor(100);
  await page.evaluate(() => {
    Object.defineProperty(document, "visibilityState", {
      configurable: true,
      value: "hidden",
    });
    document.dispatchEvent(new Event("visibilitychange"));
  });
  const beforeHidden = requests;
  await page.clock.fastForward(60_000);
  expect(requests).toBe(beforeHidden);
  await expectRefresh(() =>
    page.evaluate(() => {
      Object.defineProperty(document, "visibilityState", {
        configurable: true,
        value: "visible",
      });
      document.dispatchEvent(new Event("visibilitychange"));
    }),
  );
  await page.keyboard.press("Escape");
  await expectRefresh(() =>
    page.getByRole("button", { name: "Choose model" }).click(),
  );
});
