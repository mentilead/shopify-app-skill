# Add E2E Test

Scaffold a Playwright end-to-end test with FrameLocator for embedded Shopify app testing.

## Arguments

`$ARGUMENTS` = feature or page to test (e.g., "form editor page", "billing upgrade flow", "settings CRUD")

## Instructions

1. Parse the test target from `$ARGUMENTS`. If empty, ask the user what feature or page to test.
2. Read `.claude/skills/shopify-app/references/testing-patterns.md` for the three-tier strategy, FrameLocator pattern, and auth setup.
3. Determine which test tier is appropriate:
   - **Unit (Vitest)** — for service function logic, key builders, mappers
   - **Mock-bridge CI (Playwright + mock)** — for UI flows without Shopify auth
   - **E2E (Playwright)** — for full embedded app flows inside Shopify admin
4. Create the test file in the correct location:
   - Unit tests: `tests/unit/<feature>.test.ts`
   - E2E tests: `tests/e2e/<feature>.spec.ts`
5. For E2E tests, use the FrameLocator pattern:
   - Import helpers: `getAppFrame`, `navigateToApp`, `waitForPageTitle`
   - All selectors go through `frame.getByRole()`, `frame.getByText()`, etc.
   - Never use `page.locator()` directly — the app runs in an iframe
6. Structure the test with:
   - `test.describe` block for the feature
   - `test.beforeEach` for navigation and setup
   - Individual `test` blocks for each scenario (happy path, error cases, edge cases)
   - Assertions using `expect` with appropriate matchers
7. For tests that need authenticated state:
   - Use the auth setup from the test helpers (cookie-based or token-based)
   - Handle the Shopify admin login flow if testing full E2E
8. For tests that modify data:
   - Clean up created data in `test.afterEach` or use unique identifiers per run
   - Consider test isolation (each test should work independently)
9. Add the test to the appropriate CI config if it's a unit or mock-bridge test.
10. Remind the user to:
    - Run unit tests: `npm test` or `npx vitest`
    - Run E2E tests locally: `npx playwright test` (requires `shopify app dev` running)
    - E2E tests don't run in CI — they require a live Shopify dev store
