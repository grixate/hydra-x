import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";

async function readStdin() {
  const chunks = [];

  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }

  return Buffer.concat(chunks).toString("utf8");
}

function respond(payload) {
  process.stdout.write(`${JSON.stringify(payload)}\n`);
}

function ok(result) {
  respond({ ok: true, result });
}

function fail(code, message) {
  respond({ ok: false, error: { code, message } });
}

function normalizeHistory(history) {
  if (!Array.isArray(history)) {
    return [];
  }

  return history.map((entry) => String(entry)).filter(Boolean).slice(-12);
}

function updateHistory(history, url) {
  if (!url) {
    return history;
  }

  const next = history[history.length - 1] === url ? history : [...history, url];
  return next.slice(-12);
}

function storageStateFromSession(session) {
  const browserState =
    session?.browser_state ||
    session?.browserState ||
    null;

  if (browserState && typeof browserState === "object") {
    return browserState.storage_state || browserState.storageState || null;
  }

  return null;
}

async function buildContext(browser, session) {
  const storageState = storageStateFromSession(session);

  if (storageState && typeof storageState === "object") {
    return browser.newContext({ storageState });
  }

  return browser.newContext();
}

async function gotoAndWait(page, url) {
  const response = await page.goto(url, {
    waitUntil: "domcontentloaded",
    timeout: 15_000
  });

  await page.waitForLoadState("networkidle", { timeout: 3_000 }).catch(() => null);
  return response;
}

async function captureDomState(page) {
  return page.evaluate(() => {
    const maxLinks = 12;
    const maxForms = 8;

    const attrMap = (node, keys) =>
      keys.reduce((acc, key) => {
        const value = node.getAttribute(key);

        if (value && value.trim() !== "") {
          acc[key] = value;
        }

        return acc;
      }, {});

    const links = Array.from(document.querySelectorAll("a[href]"))
      .slice(0, maxLinks)
      .map((node, index) => ({
        index,
        href: node.getAttribute("href") || "",
        text: (node.innerText || node.textContent || "").trim()
      }))
      .filter((link) => link.href && link.text);

    const forms = Array.from(document.forms)
      .slice(0, maxForms)
      .map((form, index) => ({
        index,
        id: form.id || null,
        classes: Array.from(form.classList || []),
        method: (form.method || "post").toLowerCase(),
        action: form.getAttribute("action") || null,
        fields: Array.from(form.elements || [])
          .filter((field) => field.name)
          .map((field) => ({
            name: field.name,
            type: field.type || field.tagName.toLowerCase(),
            value: field.value ?? null
          }))
      }));

    const headings = Array.from(document.querySelectorAll("h1, h2, h3, h4, h5, h6"))
      .slice(0, 16)
      .map((node, index) => ({
        index,
        level: Number(node.tagName.slice(1)),
        text: (node.innerText || node.textContent || "").trim()
      }))
      .filter((heading) => heading.text);

    const images = Array.from(document.images)
      .slice(0, 16)
      .map((image, index) => ({
        index,
        src: image.getAttribute("src"),
        alt: image.getAttribute("alt"),
        width: image.naturalWidth || image.width || null,
        height: image.naturalHeight || image.height || null
      }))
      .filter((image) => image.src);

    const metaTags = Array.from(document.querySelectorAll("meta"));
    const tagMap = metaTags.reduce((acc, tag) => {
      const key =
        tag.getAttribute("property") ||
        tag.getAttribute("name") ||
        tag.getAttribute("http-equiv");
      const value = tag.getAttribute("content");

      if (key && value) {
        acc[key] = value;
      }

      return acc;
    }, {});

    const canonical = document.querySelector('link[rel="canonical"]')?.getAttribute("href") || null;
    const openGraph = Object.fromEntries(Object.entries(tagMap).filter(([key]) => key.toLowerCase().startsWith("og:")));
    const twitter = Object.fromEntries(Object.entries(tagMap).filter(([key]) => key.toLowerCase().startsWith("twitter:")));

    const scripts = Array.from(document.scripts)
      .slice(0, 24)
      .map((script, index) => ({
        index,
        src: script.getAttribute("src"),
        type: script.getAttribute("type") || "text/javascript",
        inline: !script.getAttribute("src"),
        excerpt: (script.textContent || "").trim().slice(0, 180)
      }))
      .filter((script) => script.src || script.excerpt);

    const structuredData = Array.from(
      document.querySelectorAll('script[type="application/ld+json"]')
    )
      .slice(0, 12)
      .map((script, index) => {
        const raw = (script.textContent || "").trim();

        try {
          const data = JSON.parse(raw);
          const summary = Array.isArray(data)
            ? data[0]?.["@type"] || "structured data"
            : data?.["@type"] || "structured data";

          return {
            index,
            summary: String(summary),
            data
          };
        } catch (_error) {
          return {
            index,
            summary: "structured data",
            data: raw.slice(0, 240)
          };
        }
      });

    const tables = Array.from(document.querySelectorAll("table"))
      .slice(0, 8)
      .map((table, index) => {
        const rows = Array.from(table.querySelectorAll("tr")).map((row) =>
          Array.from(row.querySelectorAll("th, td"))
            .map((cell) => (cell.innerText || cell.textContent || "").trim())
            .filter(Boolean)
        ).filter((row) => row.length > 0);

        const [headers = [], ...dataRows] = rows;
        return { index, headers, rows: dataRows.slice(0, 12) };
      })
      .filter((table) => table.headers.length > 0 || table.rows.length > 0);

    const bodyText = (document.body?.innerText || document.body?.textContent || "").trim();

    return {
      title: document.title || null,
      html: document.documentElement.outerHTML,
      text: bodyText,
      links,
      forms,
      headings,
      images,
      meta: {
        description: tagMap.description || null,
        canonical_url: canonical,
        open_graph: openGraph,
        twitter,
        all: tagMap
      },
      scripts,
      structured_data: structuredData,
      tables
    };
  });
}

async function extractElements(page, selector) {
  if (!selector) {
    return [];
  }

  return page.evaluate((activeSelector) => {
    const attrMap = (node, keys) =>
      keys.reduce((acc, key) => {
        const value = node.getAttribute(key);

        if (value && value.trim() !== "") {
          acc[key] = value;
        }

        return acc;
      }, {});

    return Array.from(document.querySelectorAll(activeSelector))
      .slice(0, 24)
      .map((node, index) => ({
        index,
        tag: node.tagName.toLowerCase(),
        text: (node.innerText || node.textContent || "").trim(),
        attrs: attrMap(node, ["id", "class", "href", "src", "action", "name", "type", "role", "aria-label"])
      }));
  }, selector);
}

async function extractSnippets(page, selector, textContains) {
  const source = selector
    ? await page.evaluate((activeSelector) =>
        Array.from(document.querySelectorAll(activeSelector))
          .map((node) => (node.innerText || node.textContent || "").trim())
          .filter(Boolean)
          .join("\n"),
      selector)
    : await page.evaluate(() => (document.body?.innerText || document.body?.textContent || "").trim());

  const snippets = source
    .split(/\n+/)
    .map((line) => line.trim())
    .filter(Boolean);

  if (!textContains) {
    return snippets.slice(0, 6);
  }

  const needle = String(textContains).toLowerCase();
  return snippets.filter((snippet) => snippet.toLowerCase().includes(needle)).slice(0, 6);
}

async function resolveLink(page, payload) {
  return page.evaluate(({ selector, linkText, hrefContains, linkIndex }) => {
    const anchors = Array.from(document.querySelectorAll("a[href]"));

    if (selector) {
      const candidate = document.querySelector(selector);
      const anchor = candidate?.closest("a") || (candidate?.tagName?.toLowerCase() === "a" ? candidate : null);

      if (anchor?.getAttribute("href")) {
        return {
          index: anchors.indexOf(anchor),
          href: anchor.getAttribute("href"),
          text: (anchor.innerText || anchor.textContent || "").trim()
        };
      }
    }

    if (Number.isInteger(linkIndex)) {
      const anchor = anchors[linkIndex];

      if (anchor) {
        return {
          index: linkIndex,
          href: anchor.getAttribute("href"),
          text: (anchor.innerText || anchor.textContent || "").trim()
        };
      }
    }

    const normalizedText = typeof linkText === "string" ? linkText.toLowerCase() : null;
    const normalizedHref = typeof hrefContains === "string" ? hrefContains.toLowerCase() : null;

    const anchor = anchors.find((node) => {
      const text = (node.innerText || node.textContent || "").trim().toLowerCase();
      const href = (node.getAttribute("href") || "").toLowerCase();

      if (normalizedText) {
        return text.includes(normalizedText);
      }

      if (normalizedHref) {
        return href.includes(normalizedHref);
      }

      return false;
    });

    if (!anchor) {
      return null;
    }

    return {
      index: anchors.indexOf(anchor),
      href: anchor.getAttribute("href"),
      text: (anchor.innerText || anchor.textContent || "").trim()
    };
  }, payload);
}

async function resolveForm(page, payload) {
  return page.evaluate(({ selector, formIndex, formActionContains, fields }) => {
    const forms = Array.from(document.forms);
    let form = null;
    let index = null;

    if (selector) {
      const candidate = document.querySelector(selector);
      form = candidate?.closest("form") || (candidate?.tagName?.toLowerCase() === "form" ? candidate : null);
      index = form ? forms.indexOf(form) : null;
    } else if (Number.isInteger(formIndex) && forms[formIndex]) {
      form = forms[formIndex];
      index = formIndex;
    } else if (typeof formActionContains === "string" && formActionContains.trim() !== "") {
      const needle = formActionContains.toLowerCase();
      form = forms.find((candidate) => (candidate.getAttribute("action") || "").toLowerCase().includes(needle)) || null;
      index = form ? forms.indexOf(form) : null;
    } else {
      form = forms[0] || null;
      index = form ? 0 : null;
    }

    if (!form) {
      return null;
    }

    const mergedFields = Array.from(form.elements || []).reduce((acc, field) => {
      if (field.name) {
        acc[field.name] = field.value ?? "";
      }

      return acc;
    }, {});

    Object.entries(fields || {}).forEach(([key, value]) => {
      mergedFields[key] = value ?? "";
    });

    return {
      index,
      action: form.getAttribute("action") || null,
      method: (form.getAttribute("method") || form.method || "post").toLowerCase(),
      fields: mergedFields
    };
  }, payload);
}

async function fillAndSubmitForm(page, formInfo) {
  return page.evaluate(({ index, fields }) => {
    const form = Array.from(document.forms)[index];

    if (!form) {
      return false;
    }

    Object.entries(fields || {}).forEach(([name, value]) => {
      const field = form.elements.namedItem(name);

      if (!field) {
        return;
      }

      if (field instanceof RadioNodeList) {
        Array.from(field).forEach((entry) => {
          if ("checked" in entry) {
            entry.checked = entry.value === value;
          }
        });
        return;
      }

      if ("checked" in field && ["checkbox", "radio"].includes(field.type)) {
        field.checked = Boolean(value) && value !== "false" && value !== "0";
      } else {
        field.value = value ?? "";
      }

      field.dispatchEvent(new Event("input", { bubbles: true }));
      field.dispatchEvent(new Event("change", { bubbles: true }));
    });

    if (typeof form.requestSubmit === "function") {
      form.requestSubmit();
    } else {
      form.submit();
    }

    return true;
  }, formInfo);
}

async function writeScreenshot(page) {
  const dir = path.join(os.tmpdir(), "hydra-x-browser-snapshots");
  await fs.mkdir(dir, { recursive: true });
  const filePath = path.join(dir, `browser-${crypto.randomUUID()}.png`);
  await page.screenshot({ path: filePath, fullPage: true });
  return filePath;
}

async function actionResult(page, response, extra = {}) {
  const domState = await captureDomState(page);

  return {
    url: page.url(),
    status: response?.status?.() || 200,
    title: domState.title,
    html: domState.html,
    text: domState.text,
    excerpt: domState.text.slice(0, 2500),
    content_type: "text/html",
    links: domState.links,
    forms: domState.forms,
    headings: domState.headings,
    images: domState.images,
    meta: domState.meta,
    scripts: domState.scripts,
    structured_data: domState.structured_data,
    tables: domState.tables,
    ...extra
  };
}

async function runAction(page, payload) {
  switch (payload.action) {
    case "fetch_page": {
      const response = await gotoAndWait(page, payload.url);
      return actionResult(page, response);
    }

    case "extract_links":
    case "inspect_forms":
    case "inspect_headings":
    case "inspect_images":
    case "inspect_meta":
    case "inspect_scripts":
    case "inspect_structured_data":
    case "extract_tables": {
      const response = await gotoAndWait(page, payload.url);
      return actionResult(page, response);
    }

    case "extract_elements": {
      const response = await gotoAndWait(page, payload.url);
      return actionResult(page, response, {
        elements: await extractElements(page, payload.selector)
      });
    }

    case "extract_text": {
      const response = await gotoAndWait(page, payload.url);
      return actionResult(page, response, {
        snippets: await extractSnippets(page, payload.selector, payload.text_contains)
      });
    }

    case "click_link": {
      await gotoAndWait(page, payload.url);
      const link = await resolveLink(page, payload);

      if (!link?.href) {
        const error = new Error("Link not found");
        error.code = "link_not_found";
        throw error;
      }

      const locator = page.locator("a[href]").nth(link.index >= 0 ? link.index : 0);
      const navigation = page.waitForNavigation({ waitUntil: "domcontentloaded", timeout: 10_000 }).catch(() => null);

      await locator.click({ timeout: 5_000 }).catch(async () => {
        await page.goto(new URL(link.href, page.url()).toString(), {
          waitUntil: "domcontentloaded",
          timeout: 15_000
        });
      });

      const response = await navigation;
      await page.waitForLoadState("networkidle", { timeout: 3_000 }).catch(() => null);

      return actionResult(page, response, {
        from_url: payload.url,
        followed_href: link.href
      });
    }

    case "preview_form_submission": {
      await gotoAndWait(page, payload.url);
      const form = await resolveForm(page, payload);

      if (!form) {
        const error = new Error("Form not found");
        error.code = "form_not_found";
        throw error;
      }

      return {
        url: new URL(form.action || page.url(), page.url()).toString(),
        method: form.method.toUpperCase(),
        form_index: form.index,
        form_action: form.action,
        fields: form.fields
      };
    }

    case "submit_form": {
      await gotoAndWait(page, payload.url);
      const form = await resolveForm(page, payload);

      if (!form) {
        const error = new Error("Form not found");
        error.code = "form_not_found";
        throw error;
      }

      const navigation = page.waitForNavigation({ waitUntil: "domcontentloaded", timeout: 10_000 }).catch(() => null);
      const submitted = await fillAndSubmitForm(page, form);

      if (!submitted) {
        const error = new Error("Form not found");
        error.code = "form_not_found";
        throw error;
      }

      const response = await navigation;
      await page.waitForLoadState("networkidle", { timeout: 3_000 }).catch(() => null);

      return actionResult(page, response, {
        method: form.method.toUpperCase(),
        form_index: form.index,
        form_action: form.action
      });
    }

    case "capture_snapshot":
    case "capture_screenshot": {
      const response = await gotoAndWait(page, payload.url);
      const screenshotPath = await writeScreenshot(page);

      return actionResult(page, response, {
        screenshot_path: screenshotPath,
        content_type: "image/png"
      });
    }

    default: {
      const error = new Error(`Unsupported action: ${payload.action}`);
      error.code = "unsupported_action";
      throw error;
    }
  }
}

async function main() {
  const payloadFile = process.argv[2];
  const rawInput = payloadFile ? await fs.readFile(payloadFile, "utf8") : await readStdin();
  const payload = JSON.parse(rawInput || "{}");

  let chromium;

  try {
    ({ chromium } = await import("playwright"));
  } catch (error) {
    fail("browser_unavailable", error?.message || "Playwright is not installed");
    return;
  }

  const browser = await chromium.launch({ headless: true }).catch((error) => {
    fail("browser_unavailable", error?.message || "Unable to start Chromium");
    return null;
  });

  if (!browser) {
    return;
  }

  const history = normalizeHistory(payload.session?.history);
  const context = await buildContext(browser, payload.session);
  const page = await context.newPage();

  try {
    const result = await runAction(page, payload);
    const storageState = await context.storageState();

    ok({
      ...result,
      session: {
        cookies: Object.fromEntries(storageState.cookies.map((cookie) => [cookie.name, cookie.value])),
        history: updateHistory(history, result.url || page.url()),
        browser_state: {
          backend: "playwright",
          current_url: result.url || page.url(),
          storage_state: storageState
        }
      }
    });
  } catch (error) {
    fail(error.code || "browser_runtime_failed", error?.message || "Browser runtime failed");
  } finally {
    await context.close().catch(() => null);
    await browser.close().catch(() => null);
  }
}

main().catch((error) => {
  fail(error.code || "browser_runtime_failed", error?.message || "Browser runtime failed");
});
