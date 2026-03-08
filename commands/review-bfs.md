# Review Built for Shopify

Audit a Shopify app codebase against Built for Shopify (BfS) certification requirements.

## Arguments

`$ARGUMENTS` = optional focus area (e.g., "polaris only", "security and performance"). If empty, run all categories.

## Instructions

1. Read the project's `CLAUDE.md` to discover file paths, conventions, app structure, and any project-specific overrides. Use what you learn to locate admin routes, server files, TOML configs, and billing-related code.

2. Parse `$ARGUMENTS`. If a specific category is mentioned, run only that category. Otherwise run all 6 categories below.

3. **Run all applicable category checks in parallel** using Grep and Glob tools (not shell commands). For each violation found, record the file path, line number, what's wrong, and how to fix it.

4. Output the structured report described in the Output Format section.

---

### Category 1: Polaris Compliance

Scan admin route files (typically `app/routes/app.*.tsx`) for:

- **Raw HTML elements** that should be Polaris components: `<button`, `<input`, `<table`, `<select`, `<textarea`, `<form` (case-insensitive). Ignore test files.
- **Inline styles** on layout elements: `style=` attributes or `style={{` JSX expressions in admin routes. CSS-in-JS or Tailwind in admin UI violates Polaris guidelines.
- **Missing HydrateFallback** — every admin route with a `loader` should export a `HydrateFallback` component for Remix streaming. Grep for files that export a `loader` but do not export `HydrateFallback`.

### Category 2: Performance

Scan server-side files (`*.server.ts`, `*.server.tsx`, route loaders/actions) for:

- **Sequential awaits** that could be parallelized: two or more `await` statements on independent calls in the same function that could use `Promise.all()` or `Promise.allSettled()`.
- **Unretried GraphQL mutations** — `admin.graphql()` mutation calls not wrapped in a retry utility (e.g., `withGraphQLRetry`). Shopify recommends retry logic for rate-limited mutations.
- **Sequential array processing** — `for...of` or `for` loops containing `await` that could use `Promise.all()` with `.map()`.

### Category 3: Security

- **GDPR webhooks** — check TOML config files (`shopify.app*.toml`) for required GDPR webhook entries: `customers/data_request`, `customers/redact`, `shop/redact`. Flag if any are missing.
- **Console statements in server code** — Grep server files for `console.log`, `console.warn`, `console.error`. Production apps should use a structured logger.
- **PII in logging** — Grep for logger calls that pass variables named `email`, `phone`, `address`, `password`, `token`, `secret`, or `accessToken`.

### Category 4: Billing

- **Billing implementation** — check for `appSubscriptionCreate` GraphQL mutation or a billing service file. BfS apps that charge must use the Shopify Billing API.
- **Free tier availability** — if billing config or plan definitions exist, check that a free or starter tier is available. BfS apps should offer baseline functionality without payment.

### Category 5: Technical Requirements

- **REST API usage** — Grep for `/admin/api/` URL patterns or `rest.` client calls. BfS apps should prefer GraphQL over REST.
- **Webhook API version consistency** — read all TOML config files and check that `api_version` values are consistent across webhook subscriptions.
- **App uninstall handler** — verify an `app/uninstalled` webhook handler exists (in TOML config and as a route/handler). This is required for cleanup on uninstall.

### Category 6: App Listing (Manual Checklist)

This category cannot be automated. Output a reminder checklist:

- [ ] App icon is 1200x1200px PNG with no transparency
- [ ] At least 3 screenshots showing real app functionality
- [ ] Detailed app description (min 100 words)
- [ ] Privacy policy URL is set and accessible
- [ ] Support contact (email or URL) is provided
- [ ] App is tested on mobile admin (responsive Polaris)

---

## Output Format

```
# Built for Shopify Audit Report

## 1. Polaris Compliance: PASS | FAIL (N violations)

- [ file:line ] Raw `<button>` element — replace with Polaris `<Button>`
- [ file:line ] Inline `style={{}}` — use Polaris component props or tokens

## 2. Performance: PASS | FAIL (N violations)

- [ file:line ] Sequential awaits on independent calls — use `Promise.all()`

## 3. Security: PASS | FAIL (N violations)

- [ shopify.app.toml ] Missing GDPR webhook: `customers/data_request`
- [ file:line ] `console.log` in server code — use structured logger

## 4. Billing: PASS | INFO

- Billing API integration found / not found
- Free tier: found / not found

## 5. Technical: PASS | FAIL (N violations)

- [ file:line ] REST API call — migrate to GraphQL
- [ shopify.app.toml ] Webhook API version mismatch: 2024-01 vs 2024-04

## 6. App Listing: MANUAL CHECK REQUIRED

(checklist items)

---

## Summary

- Categories passed: N/6
- Total violations: N
- Manual checks remaining: N
```
