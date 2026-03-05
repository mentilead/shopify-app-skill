# Add API Route

Scaffold a new React Router route with loader/action, authentication, validation, and tenant scoping.

## Arguments

`$ARGUMENTS` = route description (e.g., "app.settings for shop settings CRUD", "api.export for CSV export endpoint")

## Instructions

1. Parse the route name and purpose from `$ARGUMENTS`. If empty, ask the user what route to create and whether it's an `app.` (authenticated admin), `api.` (headless), `proxy.` (public), or `webhooks.` route.
2. Read `.claude/skills/shopify-app/references/react-router-patterns.md` for file naming, loader/action patterns, and revalidation.
3. Read `.claude/skills/shopify-app/references/security-patterns.md` for tenant scoping and input validation.
4. Determine the filename from the route prefix:
   - `app.settings` → `app/routes/app.settings.tsx` (authenticated, has UI)
   - `api.export` → `app/routes/api.export.tsx` (headless, action only)
   - `proxy.apply` → `app/routes/proxy.apply.tsx` (public, HMAC verified)
5. Create the route file with the correct authentication pattern:
   - `app.*` routes: `authenticate.admin(request)` in loader and action
   - `api.*` routes: appropriate auth for the use case
   - `proxy.*` routes: HMAC verification via `verifyProxySignature()`
   - `webhooks.*` routes: `authenticate.webhook(request)`
6. For routes with UI (`app.*` prefix):
   - Export `loader` for data fetching (scope queries by `session.shop`)
   - Export `action` for mutations (validate input, scope by `session.shop`)
   - Export `default` component with Polaris UI
   - Add `shouldRevalidate` if the route has POST actions
   - Read `.claude/skills/shopify-app/references/polaris-ui-patterns.md` for component patterns
7. For headless routes (`api.*` prefix):
   - Export `action` only (or `loader` for GET endpoints)
   - Return JSON responses with proper status codes
   - Validate all input parameters
8. Wire up to existing service functions in `app/services/*.server.ts`, or create new ones if needed (always with `shopDomain` as first parameter).
9. If the route needs navigation, update the `<s-app-nav>` in `app/routes/app.tsx`.
