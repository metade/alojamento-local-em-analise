#!/usr/bin/env node
import { chromium } from "playwright-core";
import { existsSync } from "node:fs";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const root = resolve(import.meta.dirname, "..");
const site = join(root, "_site");
const output = join(root, "tmp", "screenshots");
const preview = join(site, ".screenshot-preview.html");

if (!existsSync(join(site, "assets", "story.css"))) {
  throw new Error("CSS gerado em falta. Execute bundle exec rake site:build primeiro.");
}

// The published site uses a root-relative CSS URL. A temporary copy lets
// file:// screenshots load that same stylesheet without starting a server.
const pagePath = process.argv[2] || "index.html";
const screenshotName = pagePath === "index.html" ? "homepage" : pagePath.split("/").filter(part => part !== "index.html").join("-");
const html = await readFile(join(site, pagePath), "utf8");
await writeFile(preview, html.replace('href="/assets/story.css"', 'href="assets/story.css"'));
await mkdir(output, { recursive: true });

let browser;
try {
  browser = await chromium.launch({
    headless: true,
    ...(process.env.CHROME_BIN
      ? { executablePath: process.env.CHROME_BIN }
      : { channel: "chrome" })
  });

  for (const width of [1440, 768, 390]) {
    const context = await browser.newContext({
      viewport: { width, height: 900 },
      deviceScaleFactor: 1,
      isMobile: width === 390
    });
    try {
      const page = await context.newPage();
      await page.goto(pathToFileURL(preview).href, { waitUntil: "load" });
      await page.evaluate(() => document.fonts.ready);
      const metrics = await page.evaluate(() => ({
        inner: window.innerWidth,
        scroll: document.documentElement.scrollWidth,
        css: [...document.styleSheets].some(sheet => sheet.href?.endsWith("/assets/story.css"))
      }));
      if (!metrics.css) throw new Error(`O CSS não carregou a ${width}px.`);
      if (metrics.inner !== width) throw new Error(`Viewport inesperado: ${metrics.inner}px em vez de ${width}px.`);
      if (metrics.scroll > width) throw new Error(`Overflow horizontal a ${width}px: ${metrics.scroll}px.`);

      const path = join(output, `${screenshotName}-${width}.png`);
      await page.screenshot({ path, fullPage: true, animations: "disabled" });
      console.log(`${width}px: ${path}`);
    } finally {
      await context.close();
    }
  }
} finally {
  await browser?.close();
  await rm(preview, { force: true });
}
