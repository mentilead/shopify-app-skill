# Testing Patterns

## Three-Tier Testing Strategy

| Tier | Tool | Runs | Scope |
|------|------|------|-------|
| Unit/Integration | Vitest | CI + local | Service functions, keys, mappers |
| Mock-bridge CI | Playwright + mock | CI | UI flows without Shopify auth |
| E2E | Playwright | Local only | Full embedded app inside Shopify admin |

---

## FrameLocator Pattern for Embedded Apps

Shopify renders embedded apps in an iframe. All selectors must go through `FrameLocator`:

```typescript
// tests/helpers/app-frame.ts
export function getAppFrame(page: Page): FrameLocator {
  return page.frameLocator('iframe[name="app-iframe"]');
}

export async function navigateToApp(page: Page, path: string) {
  const url = `${APP_PATH_PREFIX}${path}`;
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('iframe[name="app-iframe"]', { timeout: 30_000 });
}

export async function waitForPageTitle(frame: FrameLocator, title: string) {
  await expect(frame.getByRole('heading', { name: title }))
    .toBeVisible({ timeout: 30_000 });
}
```

### Usage in Tests

```typescript
test('can save settings', async ({ page }) => {
  await navigateToApp(page, '/settings');
  const frame = getAppFrame(page);
  await waitForPageTitle(frame, 'Settings');

  await frame.getByLabel('Brand color').fill('#FF0000');
  await frame.getByRole('button', { name: 'Save' }).click();

  // Verify toast
  await expect(page.getByText('Settings saved')).toBeVisible();
});
```

---

## Auth Setup with `--no-deps`

```bash
# First time: run auth setup (saves session to tests/.auth/shopify.json)
npx playwright test --project=auth-setup --headed

# Subsequent runs: skip auth setup, reuse saved session
npx playwright test --no-deps
```

Auth state file is gitignored. Reuse until session expires. Running with `--no-deps` skips the auth-setup project.

---

## Polaris-Specific Selectors

Polaris components render their own DOM structure. Use semantic selectors:

```typescript
// Text fields
frame.getByLabel('Company name');

// Buttons
frame.getByRole('button', { name: 'Save' });
frame.getByRole('button', { name: 'Review', exact: true });  // Avoid matching "Review 14 pending"

// Back navigation (backAction renders as button, not link)
frame.getByRole('button', { name: 'Forms' });  // Back to forms list

// Links
frame.getByRole('link', { name: 'View application' });

// Checkboxes
frame.getByRole('checkbox', { name: 'Enable notifications' });

// Select
frame.getByLabel('Country').selectOption('Denmark');
```

---

## Toast Notification Testing

Shopify toast notifications render outside the app iframe, in the parent page:

```typescript
// Toast appears in the parent page, NOT in the iframe
await expect(page.getByText('Settings saved')).toBeVisible({ timeout: 10_000 });
```

---

## Test Idempotency

Tests should be idempotent — read current state and use a different value:

```typescript
// WRONG — always sets the same value, isDirty never flips
await frame.getByLabel('Brand color').fill('#FF0000');

// CORRECT — read current, use something different
const currentColor = await frame.getByLabel('Brand color').inputValue();
const newColor = currentColor === '#FF0000' ? '#00FF00' : '#FF0000';
await frame.getByLabel('Brand color').fill(newColor);
```

---

## E2E Best Practices

- **Identify non-default rows by Delete button** (names accumulate "(Copy)" suffixes):
  ```typescript
  frame.getByRole('row').filter({ has: frame.getByRole('button', { name: 'Delete' }) });
  ```

- **Settings page Save buttons:** Use `nth()` — Branding=0, Tags=1, Notifications=2:
  ```typescript
  frame.getByRole('button', { name: 'Save' }).nth(0); // Branding section
  ```

- **Fresh fixtures:** Tests create fresh forms to avoid interference — no shared fixtures

- **Timeouts:** Embedded apps are slow. Use 30s timeouts for navigation, 10s for element visibility

- **Cleanup:** Delete test-created data in `afterEach` or use unique identifiers per test run
