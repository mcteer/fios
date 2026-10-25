import { test, expect } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.goto("/");
  await page
    .getByLabel("Access password", { exact: true })
    .fill("browser-test-password");
  await page.getByRole("button", { name: "Enter workspace" }).click();
  await expect(
    page.getByRole("heading", { name: "How can I help you today?" }),
  ).toBeVisible();
});
test("professional desktop shell, attachments, streaming code copy, history and delete", async ({
  page,
}) => {
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.setViewportSize({ width: 1190, height: 806 });
  await expect(
    page.getByRole("button", { name: "Choose model" }),
  ).toContainText("coding-model");
  await expect(page.locator(".composer .model-picker")).toBeVisible();
  await page.screenshot({
    path: "test-results/fios-desktop.png",
    fullPage: true,
  });
  await page.locator("input[type=file]").setInputFiles({
    name: "example.js",
    mimeType: "text/javascript",
    buffer: Buffer.from("const x = 42;"),
  });
  await expect(page.getByText("example.js")).toBeVisible();
  await page
    .getByRole("textbox", { name: "Message Fios" })
    .fill("Please review this function");
  await page.getByRole("button", { name: "Send message", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Stop response" }),
  ).toBeVisible();
  await expect(
    page.getByText("Ready to build.", { exact: true }),
  ).toBeVisible();
  await expect(page.getByRole("button", { name: "Stop response" })).toHaveCount(
    0,
  );
  await expect(page.locator(".code-block .hljs-keyword").first()).toBeVisible();
  await page.getByRole("button", { name: "Copy code", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Copied", exact: true }),
  ).toBeVisible();
  const clipboard = await page.evaluate(() => navigator.clipboard.readText());
  expect(clipboard).toContain("const greeting");
  await page.screenshot({
    path: "test-results/fios-conversation.png",
    fullPage: true,
  });
  await page.reload();
  await page
    .getByRole("button", { name: "Please review this function", exact: true })
    .click();
  await expect(
    page.getByText("Ready to build.", { exact: true }),
  ).toBeVisible();
  await expect(page.getByText("example.js")).toBeVisible();
  await page
    .getByRole("button", {
      name: "Delete Please review this function",
      exact: true,
    })
    .click();
  await page
    .getByRole("button", { name: "Delete conversation", exact: true })
    .click();
  await expect(
    page.getByRole("heading", { name: "How can I help you today?" }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", {
      name: "Please review this function",
      exact: true,
    }),
  ).toHaveCount(0);
  expect(errors).toEqual([]);
});
test("composer model picker changes models without submitting the draft", async ({
  page,
}) => {
  await page
    .getByRole("textbox", { name: "Message Fios" })
    .fill("Keep this draft unsent");
  await expect(
    page
      .locator(".sidebar")
      .getByRole("button", { name: "Models", exact: true }),
  ).toHaveCount(0);
  await expect(page.locator(".composer")).toHaveCSS("min-height", "96px");
  await page.getByRole("button", { name: "Choose model" }).click();
  await expect(page.locator(".model-menu")).toBeVisible();
  await page.locator(".model-option").filter({ hasText: "text-only" }).click();
  await expect(
    page.getByRole("button", { name: "Choose model" }),
  ).toContainText("text-only");
  await expect(page.getByRole("textbox", { name: "Message Fios" })).toHaveValue(
    "Keep this draft unsent",
  );
  await expect(page.locator(".message")).toHaveCount(0);
  await page.getByRole("button", { name: "Choose model" }).click();
  await expect(page.locator(".model-menu")).toBeInViewport();
});
test("mobile navigation, upload removal and streaming stop", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(page.locator(".sidebar")).not.toBeInViewport();
  await expect(page.locator(".composer")).toHaveCSS("min-height", "96px");
  await page.screenshot({
    path: "test-results/fios-mobile.png",
    fullPage: true,
  });
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth),
  ).toBeLessThanOrEqual(390);
  await page.getByRole("button", { name: "Open navigation" }).click();
  await expect(page.locator(".sidebar")).toHaveClass(/is-open/);
  await page
    .locator(".sidebar")
    .getByRole("button", { name: "Close navigation", exact: true })
    .click();
  await page.locator("input[type=file]").setInputFiles({
    name: "notes.md",
    mimeType: "text/markdown",
    buffer: Buffer.from("context"),
  });
  await page.getByRole("button", { name: "Remove notes.md" }).click();
  await expect(page.getByText("notes.md")).toHaveCount(0);
  await page
    .getByRole("textbox", { name: "Message Fios" })
    .fill("SLOW_RESPONSE");
  await page.getByRole("button", { name: "Send message", exact: true }).click();
  await expect(
    page.getByText("Here is a small example.", { exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Stop response" }).click();
  await expect(
    page.getByText("Response stopped · partial output saved"),
  ).toBeVisible();
  await expect(page.getByRole("button", { name: "Stop response" })).toHaveCount(
    0,
  );
});
