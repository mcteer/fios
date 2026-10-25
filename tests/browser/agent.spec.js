import { test, expect } from "@playwright/test";
import { samplePdf } from "../pdf-fixture.js";

test("real harness accepts text/PDF/image inputs and shows reasoning only while generating", async ({
  page,
}) => {
  await page.goto("/");
  await page
    .getByLabel("Access password", { exact: true })
    .fill("browser-test-password");
  await page.getByRole("button", { name: "Enter workspace" }).click();
  await page.locator("input[type=file]").setInputFiles([
    {
      name: "notes.txt",
      mimeType: "text/plain",
      buffer: Buffer.from("context"),
    },
    { name: "doc.pdf", mimeType: "application/pdf", buffer: samplePdf() },
    {
      name: "pixel.png",
      mimeType: "image/png",
      buffer: Buffer.from(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j7N8AAAAASUVORK5CYII=",
        "base64",
      ),
    },
  ]);
  await page
    .getByRole("textbox", { name: "Message Fios" })
    .fill("REASONING_RESPONSE SLOW_RESPONSE");
  await page.getByRole("button", { name: "Send message", exact: true }).click();
  await expect(page.locator(".reasoning")).toBeVisible();
  await page.getByRole("button", { name: "Stop response" }).click();
  await expect(page.getByRole("button", { name: "Stop response" })).toHaveCount(
    0,
  );
  await expect(page.locator(".reasoning")).toHaveCount(0);
  await page.reload();
  await page
    .getByRole("button", {
      name: "REASONING_RESPONSE SLOW_RESPONSE",
      exact: true,
    })
    .click();
  await expect(page.getByText("doc.pdf")).toBeVisible();
  await expect(page.locator(".reasoning")).toHaveCount(0);
});

test("real harness reports provider failure, retains partial output, and accepts a subsequent message", async ({
  page,
}) => {
  await page.goto("/");
  await page
    .getByLabel("Access password", { exact: true })
    .fill("browser-test-password");
  await page.getByRole("button", { name: "Enter workspace" }).click();
  const box = page.getByRole("textbox", { name: "Message Fios" });
  await box.fill("PARTIAL_STREAM");
  await page.getByRole("button", { name: "Send message", exact: true }).click();
  await expect(page.getByRole("button", { name: "Stop response" })).toHaveCount(
    0,
  );
  await expect(
    page.getByText("Here is a small example.", { exact: true }),
  ).toBeVisible();
  await expect(
    page.getByText(/Agent generation failed|closed the stream/).first(),
  ).toBeVisible();
  await box.fill("normal after error");
  await page.getByRole("button", { name: "Send message", exact: true }).click();
  await expect(
    page.getByText("Ready to build.", { exact: true }),
  ).toBeVisible();
  await page.reload();
  await page
    .getByRole("button", { name: "PARTIAL_STREAM", exact: true })
    .click();
  await expect(
    page.getByText("Ready to build.", { exact: true }),
  ).toBeVisible();
});
