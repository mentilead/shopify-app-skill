---
name: shopify-app
description: Production patterns for embedded Shopify apps with React Router v7,
  DynamoDB single-table design, Lambda, SQS, CDK. Covers Polaris UI, Shopify GraphQL
  API, App Proxy, billing, webhooks, and CDK infrastructure.
---

## CRITICAL GOTCHAS (Top 10)

### 1. Never Use Polaris `url` Prop for Internal Navigation

```tsx
// WRONG — breaks out of iframe
<Button url="/app/pricing">Upgrade</Button>

// CORRECT — stays in iframe
const navigate = useNavigate();
<Button onClick={() => navigate('/app/pricing')}>Upgrade</Button>
```

**Rule:** `url` prop is only safe for external URLs. Use `useNavigate()` for internal routes.

### 2. Never Use `NODE_ENV` for Billing `isTest` Flag

```typescript
// WRONG — always false on Lambda (staging included)
isTest: process.env.NODE_ENV !== 'production'

// CORRECT — detect via Shopify API
isTest: await isDevelopmentStore(admin)
```

### 3. `useFetcher` Data Goes to `fetcher.data`, Not `useActionData()`

```tsx
// WRONG — always undefined when using fetcher
const actionData = useActionData<typeof action>();

// CORRECT — read from fetcher
const fetcher = useFetcher();
const fetcherData = fetcher.data as { ok?: boolean; error?: string } | undefined;
```

### 4. `useState` Doesn't Sync with Loader After Save

```tsx
// WRONG — state diverges from loader after save
const [brandColor, setBrandColor] = useState(settings.brandColor);

// CORRECT — sync from loader when data changes
const lastSyncRef = useRef(settings.updatedAt);
useEffect(() => {
  if (settings.updatedAt !== lastSyncRef.current) {
    setBrandColor(settings.brandColor);
    lastSyncRef.current = settings.updatedAt;
  }
}, [settings.updatedAt, settings.brandColor]);
```

### 5. Parent + Child Loaders Run in Parallel (Billing Race Condition)

```typescript
// CORRECT — redirect after billing sync to force clean second load
const url = new URL(request.url);
if (url.searchParams.has('charge_id')) {
  url.searchParams.delete('charge_id');
  throw redirect(url.pathname + url.search);
}
```

### 6. App Proxy: GET Only, No External CSS/JS

| Constraint | Detail |
|-----------|--------|
| GET only | Proxy only forwards GET. POST must go directly to the app URL. |
| No external CSS/JS | `<link>` and `<script src>` resolve against storefront domain and 404. |
| No Tailwind `?inline` | Tailwind 4's Vite plugin doesn't process `@tailwind` for `?inline` imports. |
| No client-side hydration | React Router JS bundles don't load through the proxy. |

### 7. Plus Dev Stores Can't Approve Test Charges

Create a non-Plus (Basic) dev store for billing testing. Plus dev stores show "This feature isn't currently available."

### 8. Custom Apps Cannot Use Billing API

App must be **Public** or **Unlisted** distribution — not Custom.

### 9. CloudFront Strips Host Header — CSRF Failure

```typescript
// CDK fix: add x-forwarded-host custom origin header
const apiOrigin = new origins.HttpOrigin(apiDomain, {
  customHeaders: { 'x-forwarded-host': config.domainName },
});
```

### 10. `shopify app dev --store` Flag Ignored with Cached Association

```bash
# WRONG — --store flag is ignored
shopify app dev --store different-store.myshopify.com

# CORRECT — reset cached association first
shopify app dev --reset
```

---

## Quick Reference

### `shopifyApp()` Config Skeleton

```typescript
const shopify = shopifyApp({
  apiKey: process.env.SHOPIFY_API_KEY,
  apiSecretKey: process.env.SHOPIFY_API_SECRET || '',
  apiVersion: ApiVersion.October25,
  scopes: process.env.SCOPES?.split(','),
  appUrl: process.env.SHOPIFY_APP_URL || '',
  authPathPrefix: '/auth',
  sessionStorage: new DynamoDBSessionStorage(),
  distribution: AppDistribution.AppStore,
  billing: { /* plan definitions */ },
  future: { expiringOfflineAccessTokens: true },
});
```

### Route Naming Conventions

| Pattern | Purpose | URL |
|---------|---------|-----|
| `app.tsx` | Layout (nav, Polaris, billing) | — |
| `app._index.tsx` | Dashboard | `/app` |
| `app.forms.$id.tsx` | Form editor | `/app/forms/:id` |
| `proxy.tsx` | Public proxy layout | — |
| `api.submit-application.tsx` | POST endpoint | `/api/submit-application` |
| `webhooks.app.uninstalled.tsx` | Webhook handler | — |

**Prefixes:** `app.` = authenticated admin, `proxy.` = public HMAC-verified, `api.` = headless, `webhooks.` = Shopify webhooks.

### Layout Route (`app.tsx`) Pattern

- Loads Polaris styles, runs `authenticate.admin()`, syncs billing to DynamoDB
- Provides `<AppProvider>`, `<s-app-nav>`, `<ClientOnly>` wrapping `<PolarisProvider>`
- Includes `ErrorBoundary` and `headers` from `boundary`
- Uses `shouldRevalidate` to skip revalidation on POST (prevents flicker)

### `shouldRevalidate` Pattern

```typescript
export const shouldRevalidate = ({ formMethod, defaultShouldRevalidate }) => {
  if (formMethod === 'POST') return false;
  return defaultShouldRevalidate;
};
```

### ClientOnly Component

```tsx
export function ClientOnly({ children, fallback = null }: Props) {
  const [mounted, setMounted] = useState(false);
  useEffect(() => { setMounted(true); }, []);
  return mounted ? <>{children}</> : <>{fallback}</>;
}
```

### SSR Hydration Rule

**NEVER use inline event handlers** — they cause hydration mismatches in SSR apps. Always use `onClick`, `onChange`, etc. via React state and handlers.

---

## Project Structure

```
your-app/
  app/
    routes/              # File-based routes (app.*, proxy.*, api.*, webhooks.*)
    components/          # React components (ClientOnly, etc.)
    services/            # Business logic (*.server.ts)
      dynamodb/          # keys.ts, mappers.ts
    lib/                 # Core infra (dynamodb.server.ts, config.server.ts)
    lambda-workers/      # SQS handlers (email, export)
    shopify.server.ts    # shopifyApp() config
    lambda.server.ts     # Lambda entry point
  infra/                 # CDK stacks
  tests/                 # Playwright E2E
  extensions/            # Shopify app extensions
```

### Service Conventions

- All DB access through `app/services/*.server.ts`
- First param is always `shopDomain` (multi-tenant scoping)
- Keys via `app/services/dynamodb/keys.ts`
- `.server.ts` suffix = tree-shaken from client bundles

### Key Environment Variables

| Variable | Source | Description |
|----------|--------|-------------|
| `SHOPIFY_API_KEY` | Secrets Manager | App API key |
| `SHOPIFY_API_SECRET` | Secrets Manager | App API secret |
| `SHOPIFY_APP_URL` | SSM | App URL |
| `DYNAMODB_TABLE` | SSM | Table name |
| `DYNAMODB_ENDPOINT` | .env (local) | DynamoDB Local endpoint |
| `AWS_S3_BUCKET` | SSM | Documents bucket |
| `EMAIL_QUEUE_URL` | SSM | SQS email queue URL |

---

## Scope

**In scope:** Embedded Shopify apps, React Router v7, DynamoDB single-table, Lambda, SQS, CDK, Polaris, App Proxy, Billing API, Webhooks, GDPR compliance.

**Out of scope:** Liquid theme development, Hydrogen/headless, Checkout UI Extensions, Shopify Functions, POS extensions, Prisma/PostgreSQL.

---

## Companion Tools

Use the official **Shopify Dev MCP server** alongside this skill for documentation search, GraphQL schema exploration, and Liquid validation. See [shopify.dev/docs/apps/build/devmcp](https://shopify.dev/docs/apps/build/devmcp).

**MCP config** (add to your `.claude/settings.json` or Claude Desktop config):

```json
{
  "mcpServers": {
    "shopify-dev-mcp": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/shopify-dev-mcp"]
    }
  }
}
```

---

## Orchestrator Pattern

When building a new feature, decompose into layers and build each before moving to the next:

1. **Database** — keys, entity design, queries (`references/dynamodb-patterns.md`)
2. **API** — service functions, route loader/action (`references/react-router-patterns.md`)
3. **UI** — Polaris components, state management (`references/polaris-ui-patterns.md`)

Build and test each layer independently. This prevents coupling bugs and makes code review easier.

---

## When to Consult References

| Task | Reference |
|------|-----------|
| Routing, loaders, actions, fetchers | `references/react-router-patterns.md` |
| DynamoDB keys, queries, transactions | `references/dynamodb-patterns.md` |
| GraphQL API, customers, metafields | `references/shopify-api-patterns.md` |
| Billing flow, plans, trials | `references/billing-patterns.md` |
| App Proxy pages, HMAC, forms | `references/app-proxy-patterns.md` |
| Webhook handlers, GDPR, uninstall | `references/webhook-patterns.md` |
| Lambda cold start, SQS workers | `references/lambda-architecture.md` |
| CDK stacks, CloudFront, monitoring | `references/cdk-infrastructure.md` |
| Polaris UI, design tokens, composition | `references/polaris-ui-patterns.md` |
| Email queuing, suppression, Resend | `references/email-patterns.md` |
| Multi-tenancy, CORS, S3 presigned URLs | `references/security-patterns.md` |
| Playwright, FrameLocator, selectors | `references/testing-patterns.md` |
| Docker, DynamoDB Local, startup | `references/local-dev-patterns.md` |
| Zero-to-production deployment, AWS setup, DNS, CI/CD | `references/production-deployment.md` |
