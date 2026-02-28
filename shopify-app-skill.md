# Shopify App Development Skill

## Activation & Scope

This skill applies when building **embedded Shopify apps** using:
- React Router v7 (Shopify Remix template / `@shopify/shopify-app-react-router`)
- Shopify Polaris UI components
- Shopify GraphQL Admin API
- DynamoDB (single-table design)
- AWS Lambda + API Gateway v2 + CloudFront
- AWS CDK for infrastructure

Use this as an actionable reference for architecture decisions, code patterns, and gotchas. Every pattern here is production-tested.

---

## CRITICAL GOTCHAS (Top 10)

Read this section first. These are the highest-value lessons — each one cost hours to debug.

### 1. Never Use Polaris `url` Prop for Internal Navigation

Polaris `<Link url="...">` and `<Button url="...">` render plain `<a>` tags. Inside Shopify's embedded app iframe, these navigate to the raw app URL (CloudFront/tunnel domain), breaking out of the admin iframe.

```tsx
// WRONG — breaks out of iframe
<Button url="/app/pricing">Upgrade</Button>
<Link url="/app/settings">Settings</Link>

// CORRECT — stays in iframe
const navigate = useNavigate();
<Button onClick={() => navigate('/app/pricing')}>Upgrade</Button>

// OK — external URLs are fine with url prop
<Button url="https://admin.shopify.com/store/foo/settings/billing">
  Manage in Shopify
</Button>
```

**Rule:** `url` prop is only safe for external URLs. For internal app navigation, always use `useNavigate()` from React Router.

### 2. Never Use `NODE_ENV` for Billing `isTest` Flag

`NODE_ENV` is `"production"` on deployed Lambdas (staging included). Using `isTest: NODE_ENV !== 'production'` sends real charges on staging, which silently fails on dev stores.

```typescript
// WRONG — always false on Lambda
isTest: process.env.NODE_ENV !== 'production'

// CORRECT — detect store type via Shopify API
async function isDevelopmentStore(admin: AdminApiContext): Promise<boolean> {
  const response = await admin.graphql(
    `{ shop { plan { partnerDevelopment } } }`
  );
  const { data } = await response.json();
  return data?.shop?.plan?.partnerDevelopment === true;
}

// In billing action:
isTest: await isDevelopmentStore(admin)
```

### 3. `useFetcher` Data Goes to `fetcher.data`, Not `useActionData()`

When submitting via `fetcher.submit()`, responses go to `fetcher.data`, NOT `useActionData()`. This is the most common bug when error/success banners don't show after fetcher actions.

```tsx
// WRONG — always undefined when using fetcher
const actionData = useActionData<typeof action>();
if (actionData?.error) showBanner(actionData.error);

// CORRECT — read from fetcher
const fetcher = useFetcher();
const fetcherData = fetcher.data as {
  ok?: boolean;
  error?: string;
  message?: string;
} | undefined;
if (fetcherData?.error) showBanner(fetcherData.error);
```

### 4. `useState` Doesn't Sync with Loader After Save

After a fetcher action updates the database, the loader returns fresh data — but `useState` still holds the old value. The component shows stale data until a full page reload.

```tsx
// WRONG — state diverges from loader after save
const { settings } = useLoaderData<typeof loader>();
const [brandColor, setBrandColor] = useState(settings.brandColor);
// After save: loader returns new color, but useState still has old one

// CORRECT — sync from loader when data changes
const { settings } = useLoaderData<typeof loader>();
const [brandColor, setBrandColor] = useState(settings.brandColor);
const lastSyncRef = useRef(settings.updatedAt);

useEffect(() => {
  if (settings.updatedAt !== lastSyncRef.current) {
    setBrandColor(settings.brandColor);
    lastSyncRef.current = settings.updatedAt;
  }
}, [settings.updatedAt, settings.brandColor]);
```

### 5. Parent + Child Loaders Run in Parallel (Billing Race Condition)

React Router v7 runs parent (`app.tsx`) and child loaders in parallel. If the parent writes billing data to DynamoDB, child loaders may read stale data.

```typescript
// WRONG — child loader reads stale DynamoDB data after billing approval
// (parent hasn't finished writing yet)

// CORRECT — redirect after billing sync to force a clean second load
// In app.tsx loader, after billing sync completes:
const url = new URL(request.url);
if (url.searchParams.has('charge_id')) {
  url.searchParams.delete('charge_id');
  throw redirect(url.pathname + url.search);
}
```

This forces all loaders to re-run with the updated DynamoDB data.

### 6. App Proxy Constraints

Shopify App Proxy has severe limitations:

| Constraint | Detail |
|-----------|--------|
| **GET only** | Proxy only forwards GET requests. POST must go directly to the app URL. |
| **No external CSS/JS** | `<link>` and `<script src>` resolve against the storefront domain and 404. |
| **No Tailwind `?inline`** | Tailwind 4's Vite plugin doesn't process `@tailwind` for `?inline` imports. |
| **No client-side hydration** | React Router JS bundles don't load through the proxy. |

```tsx
// CSS must be inlined via Vite's ?inline suffix
import proxyStyles from '../styles/proxy.css?inline';

// Render inline in the layout
<style dangerouslySetInnerHTML={{ __html: proxyStyles }} />

// Forms must POST directly to the app URL, then redirect back
<form method="POST" action={`${appUrl}/api/submit-application`}>
  {/* hidden fields for shop, form data */}
</form>
// After processing, redirect: ?submitted=true or ?error=validation&stateId=xxx
```

**Proxy CSS:** Write hand-crafted utility classes in a dedicated `proxy.css` file. Don't rely on Tailwind processing.

### 7. Plus Dev Stores Can't Approve Test Charges

Plus development stores show "This feature isn't currently available" when redirected to the billing confirmation page. This is a known Shopify bug.

**Workaround:** Create a non-Plus (Basic) dev store for billing testing:

| Store | Plan | Use for |
|-------|------|---------|
| your-app-dev | Plus | B2B company features, app proxy, integration testing |
| your-app-billing-test | Basic | Billing flow testing |

### 8. Custom Apps Cannot Use Billing API

Apps with "Custom" distribution cannot use the Billing API at all. The app must be set to **Public** (or Unlisted) distribution in the Shopify Partners Dashboard.

```typescript
// shopify.server.ts — must be AppStore or SingleMerchant, not ShopifyAdmin
const shopify = shopifyApp({
  distribution: AppDistribution.AppStore,
  // ...
});
```

### 9. CloudFront Strips Host Header — CSRF Failure

CloudFront's "AllViewerExceptHostHeader" policy replaces `Host` with the API Gateway domain. React Router POST actions compare `Origin` vs `host`/`x-forwarded-host` — mismatch causes 400 "Bad Request".

```typescript
// CDK fix: add x-forwarded-host custom origin header in CloudFront
const apiOrigin = new origins.HttpOrigin(apiDomain, {
  customHeaders: {
    'x-forwarded-host': config.domainName,  // e.g. 'staging.onboard.example.com'
  },
});
```

Without this, every POST action through CloudFront fails silently.

### 10. `shopify app dev --store` Flag Ignored with Cached Association

The `--store` flag is ignored when there's a cached store association. The CLI silently uses the previously configured store.

```bash
# WRONG — --store flag is ignored
shopify app dev --store different-store.myshopify.com

# CORRECT — reset the cached association first
shopify app dev --reset
# Then select the new store interactively
```

---

## App Setup

### `shopifyApp()` Configuration

```typescript
// app/shopify.server.ts
import '@shopify/shopify-app-react-router/adapters/node';
import {
  ApiVersion,
  AppDistribution,
  BillingInterval,
  BillingReplacementBehavior,
  shopifyApp,
} from '@shopify/shopify-app-react-router/server';
import { DynamoDBSessionStorage } from './lib/dynamodb-session-storage';

const shopify = shopifyApp({
  apiKey: process.env.SHOPIFY_API_KEY,
  apiSecretKey: process.env.SHOPIFY_API_SECRET || '',
  apiVersion: ApiVersion.October25,
  scopes: process.env.SCOPES?.split(','),
  appUrl: process.env.SHOPIFY_APP_URL || '',
  authPathPrefix: '/auth',
  sessionStorage: new DynamoDBSessionStorage(),
  distribution: AppDistribution.AppStore,
  billing: {
    'Starter Monthly': {
      replacementBehavior: BillingReplacementBehavior.ApplyImmediately,
      lineItems: [{
        amount: 19,
        currencyCode: 'USD',
        interval: BillingInterval.Every30Days,
      }],
    },
    // ... more plans
  },
  future: {
    expiringOfflineAccessTokens: true,
  },
  // Custom domain support (for Shopify Plus stores)
  ...(process.env.SHOP_CUSTOM_DOMAIN
    ? { customShopDomains: [process.env.SHOP_CUSTOM_DOMAIN] }
    : {}),
});

export default shopify;
export const apiVersion = ApiVersion.October25;
export const addDocumentResponseHeaders = shopify.addDocumentResponseHeaders;
export const authenticate = shopify.authenticate;
export const unauthenticated = shopify.unauthenticated;
export const login = shopify.login;
export const registerWebhooks = shopify.registerWebhooks;
export const sessionStorage = shopify.sessionStorage;
```

### Layout Route Pattern (`app.tsx`)

The layout route provides Polaris chrome, navigation, billing sync, and error boundary:

```tsx
// app/routes/app.tsx
import { boundary } from '@shopify/shopify-app-react-router/server';
import { AppProvider } from '@shopify/shopify-app-react-router/react';
import { AppProvider as PolarisProvider } from '@shopify/polaris';
import en from '@shopify/polaris/locales/en.json';
import polarisStyles from '@shopify/polaris/build/esm/styles.css?url';
import { ClientOnly } from '../components/ClientOnly';

export const links: LinksFunction = () => [
  { rel: 'stylesheet', href: polarisStyles },
];

export const loader = async ({ request }: LoaderFunctionArgs) => {
  const { session, admin, billing } = await authenticate.admin(request);

  // Billing sync: check Shopify → update DynamoDB
  // ... (see Billing API section)

  // Redirect after billing approval to avoid parallel loader race condition
  const url = new URL(request.url);
  if (url.searchParams.has('charge_id')) {
    url.searchParams.delete('charge_id');
    throw redirect(url.pathname + url.search);
  }

  return { apiKey: process.env.SHOPIFY_API_KEY || '', plan: currentPlan };
};

export default function App() {
  const { apiKey } = useLoaderData<typeof loader>();
  return (
    <AppProvider embedded apiKey={apiKey}>
      <s-app-nav>
        <s-link href="/app">Dashboard</s-link>
        <s-link href="/app/forms">Forms</s-link>
        <s-link href="/app/applications">Applications</s-link>
        <s-link href="/app/settings">Settings</s-link>
        <s-link href="/app/pricing">Pricing</s-link>
      </s-app-nav>
      <ClientOnly>
        <PolarisProvider i18n={en}>
          <Outlet />
        </PolarisProvider>
      </ClientOnly>
    </AppProvider>
  );
}

// Shopify needs React Router to catch thrown responses for header propagation
export function ErrorBoundary() {
  return boundary.error(useRouteError());
}

export const headers: HeadersFunction = (headersArgs) => {
  return boundary.headers(headersArgs);
};
```

### `shouldRevalidate` for Heavy Layout Loaders

The layout loader runs `authenticate.admin()` + `billing.check()` on every revalidation. This is expensive and causes page flicker on fetcher actions.

```typescript
// Skip revalidation when child routes submit fetcher actions
export const shouldRevalidate = ({
  formMethod,
  defaultShouldRevalidate,
}: ShouldRevalidateFunctionArgs) => {
  if (formMethod === 'POST') return false;
  return defaultShouldRevalidate;
};
```

### ClientOnly Wrapper

Polaris components access browser APIs that don't exist during SSR. Wrap them to prevent hydration mismatches:

```tsx
// app/components/ClientOnly.tsx
import { useState, useEffect, type ReactNode } from 'react';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

export function ClientOnly({ children, fallback = null }: Props) {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  return mounted ? <>{children}</> : <>{fallback}</>;
}
```

---

## File-Based Routing

React Router v7 uses `@react-router/fs-routes`. The `app.` prefix nests under the app layout (`app.tsx`) which provides Polaris chrome + nav.

### Route Naming Conventions

```
app.tsx                         → Layout (nav, Polaris, billing sync)
  app._index.tsx                → Dashboard (/app)
  app.forms._index.tsx          → Forms list (/app/forms)
  app.forms.new.tsx             → Create form (/app/forms/new)
  app.forms.$id.tsx             → Form editor (/app/forms/:id)
  app.applications._index.tsx   → Applications list (/app/applications)
  app.applications.$id.tsx      → Application detail (/app/applications/:id)
  app.settings._index.tsx       → Settings (/app/settings)
  app.pricing.tsx               → Pricing page (/app/pricing)

proxy.tsx                       → Public proxy layout (branding, no auth)
  proxy._index.tsx              → Default form
  proxy.$formId.tsx             → Specific form by ID

api.submit-application.tsx      → POST endpoint (form submissions)
api.webhooks.resend.tsx         → Resend webhook handler

webhooks.app.uninstalled.tsx    → Shopify webhook: app uninstalled
webhooks.app.customers-data-request.tsx  → GDPR: data request
webhooks.app.customers-redact.tsx        → GDPR: customer redact
webhooks.app.shop-redact.tsx             → GDPR: shop redact
```

### Key Conventions

- `app.` prefix = authenticated admin routes (inside Shopify iframe)
- `proxy.` prefix = public routes served through Shopify App Proxy (no auth, HMAC verification)
- `api.` prefix = headless API endpoints (no UI)
- `webhooks.` prefix = Shopify webhook handlers
- `_index` = index route for a parent segment
- `$param` = dynamic route parameter

---

## Shopify GraphQL API

### Always Check Both `errors` and `userErrors`

GraphQL responses can fail in two ways:

```typescript
const response = await admin.graphql(MUTATION, { variables: { input } });
const { data, errors } = await response.json();

// 1. Top-level errors (syntax, auth, rate limit)
if (errors?.length) {
  console.error('GraphQL errors:', errors);
  return { success: false, error: errors.map((e) => e.message).join(', ') };
}

// 2. User errors (validation, business logic)
const userErrors = data?.mutationName?.userErrors;
if (userErrors?.length) {
  console.error('User errors:', userErrors);
  return { success: false, error: userErrors.map((e) => e.message).join(', ') };
}
```

### GID Extraction

Shopify returns GraphQL IDs as URIs. Extract the numeric ID:

```typescript
// 'gid://shopify/Customer/12345' → '12345'
const numericId = gid.split('/').pop();
```

### Phone E.164 Normalization

Shopify `customerCreate` rejects improperly formatted phone numbers (especially US 555-xxx-xxxx test numbers).

```typescript
function normalizePhone(phone: string | undefined): string | undefined {
  if (!phone) return undefined;
  const cleaned = phone.startsWith('+')
    ? '+' + phone.slice(1).replace(/\D/g, '')
    : phone.replace(/\D/g, '');
  return cleaned || undefined;
}
```

Always normalize before sending to Shopify. Use real-looking numbers for testing (e.g., `+4531587642` for Danish).

### Metafield Definitions (Handle `TAKEN` Error)

When creating metafield definitions, the definition may already exist. Filter out the `TAKEN` error code:

```typescript
const { data } = await admin.graphql(CREATE_METAFIELD_DEFINITION, {
  variables: { definition },
});

const userErrors = data?.metafieldDefinitionCreate?.userErrors ?? [];
const realErrors = userErrors.filter((e) => e.code !== 'TAKEN');

if (realErrors.length) {
  console.error('Metafield definition error:', realErrors);
}
```

### Customer Create Pattern

```typescript
// 1. Check if customer exists first
const existingResponse = await admin.graphql(
  `{ customers(first: 1, query: "email:${email}") { edges { node { id } } } }`
);

// 2. If exists, add tags via update mutation
// 3. If new, create with all fields
const createResponse = await admin.graphql(CUSTOMER_CREATE_MUTATION, {
  variables: {
    input: {
      email,
      firstName,
      lastName,
      phone: normalizePhone(phone),
      tags: ['B2B', 'Wholesale'],
      metafields: [
        { namespace: 'custom', key: 'company_name', value: companyName, type: 'single_line_text_field' },
        { namespace: 'b2b_onboard', key: 'application_id', value: applicationId, type: 'single_line_text_field' },
      ],
    },
  },
});
```

Use dual metafield namespaces: `custom` (merchant-visible in admin) and your app namespace (app-specific).

---

## Webhooks

### Webhook Handler Pattern

```typescript
// app/routes/webhooks.app.uninstalled.tsx
import type { ActionFunctionArgs } from 'react-router';
import { authenticate } from '../shopify.server';

export const action = async ({ request }: ActionFunctionArgs) => {
  const { shop, session, topic } = await authenticate.webhook(request);
  console.log(`Received ${topic} for ${shop}`);

  // Business logic: clean up all shop data
  await deleteAllShopData(shop);

  return new Response(null, { status: 200 });
};
```

### Mandatory GDPR Webhooks

Every Shopify app must implement these three:

1. **`customers/data_request`** — Return customer data (log the request, fulfill within 30 days)
2. **`customers/redact`** — Delete customer PII (uploaded files from S3 + DynamoDB records)
3. **`shop/redact`** — Delete all shop data (S3 prefixes + DynamoDB items)

```typescript
// GDPR S3 deletion pattern
// customers/redact → delete each application's uploaded documents from S3
// shop/redact → delete shops/{domain}/ and exports/{safeDomain}/ S3 prefixes
```

### Uninstall Cleanup with Batch Delete

DynamoDB doesn't have cascading deletes. The uninstall webhook must query and delete all items:

```typescript
// Query all items for the shop
const items = await dynamodb.send(new QueryCommand({
  TableName: TABLE_NAME,
  KeyConditionExpression: 'PK = :pk',
  ExpressionAttributeValues: { ':pk': `SHOP#${shop}` },
}));

// Batch delete (max 25 per request)
const chunks = chunkArray(items.Items, 25);
for (const chunk of chunks) {
  await dynamodb.send(new BatchWriteCommand({
    RequestItems: {
      [TABLE_NAME]: chunk.map((item) => ({
        DeleteRequest: { Key: { PK: item.PK, SK: item.SK } },
      })),
    },
  }));
}
```

### Reinstall Detection

When a shop reinstalls, clear uninstall markers and log the event:

```typescript
if (existingShop.uninstalledAt) {
  await dynamodb.send(new UpdateCommand({
    TableName: TABLE_NAME,
    Key: keys.shop(shopDomain),
    UpdateExpression: 'REMOVE uninstalledAt, retentionExpiresAt SET updatedAt = :now',
    ExpressionAttributeValues: { ':now': new Date().toISOString() },
  }));

  logAuditEvent({
    shopDomain,
    action: 'shop.reinstalled',
    changes: { previousUninstalledAt: existingShop.uninstalledAt },
  });
}
```

---

## Billing API

### Full Billing Flow

```
User clicks "Start free trial"
  → action: billing.request({ plan, isTest, trialDays })
  → Shopify creates subscription, throws redirect Response
  → User sees Shopify confirmation page
  → User clicks "Approve"
  → Shopify redirects to /app?charge_id=XXX
  → app.tsx loader: billing.check() finds active subscription
  → Syncs to DynamoDB (plan, status, subscriptionId, trialEndsAt)
  → Detects charge_id, redirects to /app (clean URL)
  → All loaders re-run with fresh DynamoDB data
  → Dashboard shows correct plan
```

### `billing.request()` Throws on Success

This is unintuitive — `billing.request()` throws a redirect `Response` when the subscription is successfully created. Catch it by letting it propagate:

```typescript
// In a route action:
export const action = async ({ request }: ActionFunctionArgs) => {
  const { billing, admin } = await authenticate.admin(request);
  const formData = await request.formData();
  const planName = formData.get('plan') as string;

  const isTest = await isDevelopmentStore(admin);

  // This THROWS a redirect Response — don't try/catch it
  await billing.request({
    plan: planName,
    isTest,
    trialDays: 14,
  });

  // This line never executes on success
  return { error: 'Billing request failed' };
};
```

### `isDevelopmentStore()` Detection

```typescript
async function isDevelopmentStore(
  admin: AdminApiContext
): Promise<boolean> {
  const response = await admin.graphql(
    `{ shop { plan { partnerDevelopment } } }`
  );
  const { data } = await response.json();
  return data?.shop?.plan?.partnerDevelopment === true;
}
```

### Trial Info from `billing.check()`

```typescript
const { appSubscriptions } = await billing.check();
const active = appSubscriptions.find((s) => s.status === 'ACTIVE');

if (active?.trialDays && active?.createdAt) {
  const trialEnd = new Date(active.createdAt);
  trialEnd.setDate(trialEnd.getDate() + active.trialDays);
  if (trialEnd.getTime() > Date.now()) {
    trialEndsAt = trialEnd.toISOString();
  }
}
```

**Trial expiry emails:** Shopify handles these automatically. Don't build your own.

### Plan-Gating Pattern

Store the billing plan in DynamoDB and check limits in service functions:

```typescript
// lib/plan-config.ts
const PLAN_LIMITS = {
  free: { maxForms: 1, maxApplications: 50, customBranding: false },
  starter: { maxForms: 3, maxApplications: 500, customBranding: true },
  growth: { maxForms: 10, maxApplications: 2000, customBranding: true },
  pro: { maxForms: 999, maxApplications: 999999, customBranding: true },
};

export function getPlanLimits(planName: string | null | undefined) {
  const tier = planNameToTier(planName);
  return PLAN_LIMITS[tier] ?? PLAN_LIMITS.free;
}
```

---

## App Proxy

### HMAC Verification with `timingSafeEqual`

```typescript
// app/utils/proxy-auth.ts
import crypto from 'crypto';

export function verifyProxySignature(
  searchParams: URLSearchParams
): { valid: boolean; shop: string | null } {
  const signature = searchParams.get('signature');
  if (!signature) return { valid: false, shop: null };

  const secret = process.env.SHOPIFY_API_SECRET;
  if (!secret) return { valid: false, shop: null };

  // Build message: sort all params except signature, concatenate as key=value
  const params: string[] = [];
  for (const [key, value] of searchParams.entries()) {
    if (key !== 'signature') {
      params.push(`${key}=${value}`);
    }
  }
  params.sort();
  const message = params.join('');

  const computed = crypto
    .createHmac('sha256', secret)
    .update(message)
    .digest('hex');

  try {
    const valid = crypto.timingSafeEqual(
      Buffer.from(computed, 'hex'),
      Buffer.from(signature, 'hex'),
    );
    return { valid, shop: valid ? searchParams.get('shop') : null };
  } catch {
    return { valid: false, shop: null };
  }
}
```

### CSS `?inline` Embedding

```tsx
// Proxy layout — inline CSS since external stylesheets fail through proxy
import proxyStyles from '../styles/proxy.css?inline';

export default function ProxyLayout() {
  return (
    <>
      <style dangerouslySetInnerHTML={{ __html: proxyStyles }} />
      <div className="min-h-screen bg-slate-50">
        <Outlet />
      </div>
    </>
  );
}
```

### Form POST → Redirect Pattern

Since App Proxy only forwards GET, form submissions POST directly to the app URL:

```html
<!-- In the proxy-rendered form -->
<form method="POST" action="https://your-app.com/api/submit-application">
  <input type="hidden" name="shop" value="{{ shop }}" />
  <!-- form fields -->
  <button type="submit">Submit</button>
</form>
```

The API endpoint processes the form, then redirects back to the proxy URL:
- Success: `?submitted=true`
- Validation error: `?error=validation&stateId=<id>` (state stored in DynamoDB for retrieval)

---

## DynamoDB Single-Table Design

### Key Structure

| Entity | PK | SK | GSI1PK | GSI1SK |
|--------|----|----|--------|--------|
| Session | `SESSION#<id>` | `SESSION` | `SHOP_SESSION#<shop>` | `SESSION#<id>` |
| Shop | `SHOP#<domain>` | `SHOP#METADATA` | — | — |
| Form | `SHOP#<domain>` | `FORM#<formId>` | `FORM#<formId>` | `FORM#<formId>` |
| Application | `SHOP#<domain>` | `APPLICATION#<appId>` | `FORM#<formId>` | `APPLICATION#<ts>#<id>` |
| Event | `APPLICATION#<appId>` | `EVENT#<ts>#<eventId>` | — | — |
| EmailTemplate | `SHOP#<domain>` | `EMAIL_TEMPLATE#<type>` | — | — |
| ExportJob | `SHOP#<domain>` | `EXPORT#<exportId>` | — | — |
| Audit | `SHOP#<domain>` | `AUDIT#<ts>#<auditId>` | — | — |

### Keys Module Pattern

Centralize all key generation in a single module:

```typescript
// app/services/dynamodb/keys.ts
export const keys = {
  shop: (domain: string) => ({
    PK: `SHOP#${domain}`,
    SK: 'SHOP#METADATA',
  }),

  form: (domain: string, formId: string) => ({
    PK: `SHOP#${domain}`,
    SK: `FORM#${formId}`,
    GSI1PK: `FORM#${formId}`,
    GSI1SK: `FORM#${formId}`,
  }),

  formByShop: (domain: string) => ({
    PK: `SHOP#${domain}`,
    SKPrefix: 'FORM#',
  }),

  application: (domain: string, appId: string, formId: string, timestamp: Date) => ({
    PK: `SHOP#${domain}`,
    SK: `APPLICATION#${appId}`,
    GSI1PK: `FORM#${formId}`,
    GSI1SK: `APPLICATION#${timestamp.toISOString()}#${appId}`,
  }),

  applicationByShop: (domain: string) => ({
    PK: `SHOP#${domain}`,
    SKPrefix: 'APPLICATION#',
  }),

  applicationByForm: (formId: string) => ({
    GSI1PK: `FORM#${formId}`,
    GSI1SKPrefix: 'APPLICATION#',
  }),
};
```

### `begins_with` Entity Queries

Query all entities of a type within a partition:

```typescript
// Get all forms for a shop
const result = await dynamodb.send(new QueryCommand({
  TableName: TABLE_NAME,
  KeyConditionExpression: 'PK = :pk AND begins_with(SK, :prefix)',
  ExpressionAttributeValues: {
    ':pk': `SHOP#${shopDomain}`,
    ':prefix': 'FORM#',
  },
}));
```

### Atomic Transactions (Find-or-Create Pattern)

```typescript
try {
  await dynamodb.send(new TransactWriteCommand({
    TransactItems: [
      {
        Put: {
          TableName: TABLE_NAME,
          Item: shopItem,
          ConditionExpression: 'attribute_not_exists(PK)',
        },
      },
      // ... additional items (default form, email templates)
    ],
  }));
} catch (error) {
  if (error instanceof ConditionalCheckFailedException) {
    // Race condition: item already exists, fetch and return
    const existing = await dynamodb.send(new GetCommand({ ... }));
    return existing.Item;
  }
  throw error;
}
```

### Batch Deletion (Max 25 Items)

```typescript
async function batchDelete(items: Array<{ PK: string; SK: string }>) {
  const chunks = [];
  for (let i = 0; i < items.length; i += 25) {
    chunks.push(items.slice(i, i + 25));
  }

  for (const chunk of chunks) {
    await dynamodb.send(new BatchWriteCommand({
      RequestItems: {
        [TABLE_NAME]: chunk.map((item) => ({
          DeleteRequest: { Key: { PK: item.PK, SK: item.SK } },
        })),
      },
    }));
  }
}
```

### TTL Conventions

DynamoDB TTL is configured on the `ttl` attribute (numeric epoch seconds):

| Entity | TTL |
|--------|-----|
| Sessions | Session expiry + 24h buffer, or 30 days default |
| Export jobs | 7 days (matches `expiresAt`) |
| Audit logs | 7 years (regulatory compliance) |
| Form state | 1 hour (validation error state) |

```typescript
// TTL calculation pattern
const SEVEN_YEARS_SECONDS = 7 * 365 * 24 * 60 * 60;
const ttl = Math.floor(Date.now() / 1000) + SEVEN_YEARS_SECONDS;
```

### DynamoDB Client Setup

```typescript
// app/lib/dynamodb.server.ts
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';

const client = new DynamoDBClient({
  region: process.env.AWS_REGION ?? 'us-east-1',
  ...(process.env.DYNAMODB_ENDPOINT && {
    endpoint: process.env.DYNAMODB_ENDPOINT,
    credentials: { accessKeyId: 'local', secretAccessKey: 'local' },
  }),
});

export const dynamodb = DynamoDBDocumentClient.from(client, {
  marshallOptions: { removeUndefinedValues: true },
});

export const TABLE_NAME = process.env.DYNAMODB_TABLE ?? 'B2BOnboard';
```

### Session Storage Implementation

Implement the `SessionStorage` interface from `@shopify/shopify-app-session-storage`:

```typescript
export class DynamoDBSessionStorage implements SessionStorage {
  async storeSession(session: Session): Promise<boolean> {
    const item = sessionToItem(session);
    await dynamodb.send(new PutCommand({ TableName: TABLE_NAME, Item: item }));
    return true;
  }

  async loadSession(id: string): Promise<Session | undefined> {
    const result = await dynamodb.send(new GetCommand({
      TableName: TABLE_NAME,
      Key: { PK: `SESSION#${id}`, SK: 'SESSION' },
    }));
    return result.Item ? itemToSession(result.Item) : undefined;
  }

  async deleteSession(id: string): Promise<boolean> {
    await dynamodb.send(new DeleteCommand({
      TableName: TABLE_NAME,
      Key: { PK: `SESSION#${id}`, SK: 'SESSION' },
    }));
    return true;
  }

  async findSessionsByShop(shop: string): Promise<Session[]> {
    const result = await dynamodb.send(new QueryCommand({
      TableName: TABLE_NAME,
      IndexName: 'GSI1',
      KeyConditionExpression: 'GSI1PK = :pk',
      ExpressionAttributeValues: { ':pk': `SHOP_SESSION#${shop}` },
    }));
    return (result.Items ?? []).map((item) => itemToSession(item));
  }
}
```

---

## Lambda Architecture

### Cold Start Lazy-Init Pattern

```typescript
// app/lambda.server.ts
import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2, Context } from 'aws-lambda';
import { initConfig } from './lib/config.server';

let cachedHandler: HandlerFn;

async function ensureHandler(): Promise<HandlerFn> {
  if (cachedHandler) return cachedHandler;

  // Initialize config on cold start (fetches Secrets Manager + SSM)
  await initConfig();

  // Lazy-import the React Router AWS adapter after config is loaded
  const { createAPIGatewayV2RequestHandler } = await import(
    '@geostrategists/react-router-aws'
  );
  const build = await import('./server/index.js' as string);

  cachedHandler = createAPIGatewayV2RequestHandler({ build }) as HandlerFn;
  return cachedHandler;
}

export async function handler(
  event: APIGatewayProxyEventV2,
  context: Context,
): Promise<APIGatewayProxyResultV2> {
  const h = await ensureHandler();
  const result = await h(event, context, () => {});
  return result ?? { statusCode: 500, body: 'No response' };
}
```

### `initConfig()` for Secrets/SSM

```typescript
// app/lib/config.server.ts
let initialized = false;

export async function initConfig(): Promise<void> {
  if (initialized) return;

  // Local dev — .env already loaded, no AWS calls needed
  if (process.env.DYNAMODB_ENDPOINT) {
    initialized = true;
    return;
  }

  const tasks: Promise<void>[] = [];

  // Fetch SSM parameters (DynamoDB table name, S3 bucket, queue URLs, etc.)
  if (process.env.SSM_PREFIX) {
    tasks.push(fetchSsmParams(ssmClient, process.env.SSM_PREFIX));
  }

  // Fetch secrets (Shopify API keys, reCAPTCHA, etc.)
  if (process.env.SHOPIFY_SECRET_ARN) {
    tasks.push(fetchSecret(secretsClient, process.env.SHOPIFY_SECRET_ARN, {
      SHOPIFY_API_KEY: 'SHOPIFY_API_KEY',
      SHOPIFY_API_SECRET: 'SHOPIFY_API_SECRET',
    }));
  }

  // Optional secrets (non-fatal if missing)
  if (process.env.GA4_SECRET_ARN) {
    tasks.push(fetchSecret(secretsClient, process.env.GA4_SECRET_ARN, {
      GA4_MEASUREMENT_ID: 'GA4_MEASUREMENT_ID',
      GA4_API_SECRET: 'GA4_API_SECRET',
    }, true));  // optional = true
  }

  await Promise.all(tasks);
  initialized = true;
}
```

### SQS Workers with Partial Batch Failure

```typescript
// app/lambda-workers/email-handler.ts
import type { SQSEvent, SQSBatchResponse } from 'aws-lambda';
import { initConfig } from '../lib/config.server';

export async function handler(event: SQSEvent): Promise<SQSBatchResponse> {
  await initConfig();

  const batchItemFailures: SQSBatchResponse['batchItemFailures'] = [];

  for (const record of event.Records) {
    try {
      const payload = JSON.parse(record.body);
      await processEmailMessage(payload);
    } catch (err) {
      console.error(`Failed to process message ${record.messageId}:`, err);
      batchItemFailures.push({ itemIdentifier: record.messageId });
    }
  }

  return { batchItemFailures };
}
```

Return `batchItemFailures` so only failed messages return to the queue. Configure with `ReportBatchItemFailures` in CDK.

---

## Email (Queue-Based)

### Always Queue via SQS

Never send email inline in a request handler. Queue the message and let a worker process it:

```typescript
// In a route action:
await sqsClient.send(new SendMessageCommand({
  QueueUrl: process.env.EMAIL_QUEUE_URL,
  MessageBody: JSON.stringify({
    templateType: 'application_approved',
    recipientEmail: applicant.email,
    shopDomain,
    variables: {
      applicantName: applicant.name,
      shopName: shop.name,
    },
  }),
}));
```

### Email Suppression List

Track bounces and complaints to avoid sending to bad addresses:

```typescript
// Check before sending
const suppressed = await dynamodb.send(new GetCommand({
  TableName: TABLE_NAME,
  Key: keys.suppression(recipientEmail),
}));

if (suppressed.Item) {
  console.log(`Skipping email to suppressed address: ${recipientEmail}`);
  return;
}
```

### Resend Webhook for Bounces/Complaints

```typescript
// Verify webhook signature with Svix
import { Webhook } from 'svix';

const wh = new Webhook(webhookSecret);
const payload = wh.verify(body, headers);

switch (payload.type) {
  case 'email.bounced':
    await addSuppression({ email, type: 'BOUNCE', reason: payload.data.bounce_type });
    break;
  case 'email.complained':
    await addSuppression({ email, type: 'COMPLAINT' });
    break;
}
```

---

## Audit Logging

### Fire-and-Forget Pattern

Audit logging must never block business logic. Use `.catch()` to swallow failures:

```typescript
// app/services/audit.server.ts
export function logAuditEvent(params: AuditEventParams): void {
  const now = new Date();
  const auditId = crypto.randomUUID();

  const item = {
    ...keys.audit(params.shopDomain, now.toISOString(), auditId),
    actorType: params.actorType,    // 'merchant' | 'system' | 'webhook'
    actorId: params.actorId,
    action: params.action,
    resourceType: params.resourceType,
    resourceId: params.resourceId,
    changes: params.changes,
    createdAt: now.toISOString(),
    ttl: Math.floor(now.getTime() / 1000) + SEVEN_YEARS_SECONDS,
  };

  dynamodb
    .send(new PutCommand({ TableName: TABLE_NAME, Item: item }))
    .catch((err) => {
      console.error('Audit log write failed:', err);
    });
}
```

### Usage

```typescript
// Call after any write operation — fire-and-forget
logAuditEvent({
  shopDomain: session.shop,
  actorType: 'merchant',
  actorId: session.id,
  action: 'application.approved',
  resourceType: 'Application',
  resourceId: applicationId,
  changes: { status: { from: 'pending', to: 'approved' } },
});
```

---

## Security

### Multi-Tenancy Scoping

Every database query MUST be scoped to the authenticated shop:

```typescript
// WRONG — no tenant scoping
const forms = await queryAllForms();

// CORRECT — always scope by shop domain
const forms = await queryFormsByShop(session.shop);

// In the service function:
async function queryFormsByShop(shopDomain: string) {
  return dynamodb.send(new QueryCommand({
    TableName: TABLE_NAME,
    KeyConditionExpression: 'PK = :pk AND begins_with(SK, :prefix)',
    ExpressionAttributeValues: {
      ':pk': `SHOP#${shopDomain}`,
      ':prefix': 'FORM#',
    },
  }));
}
```

### CORS for Submission Endpoint

The form submission API endpoint needs CORS since it receives POSTs from storefront domains:

```typescript
function isAllowedOrigin(origin: string): boolean {
  return (
    origin.endsWith('.myshopify.com') ||
    origin.includes('trycloudflare.com') ||
    origin === process.env.SHOPIFY_APP_URL
  );
}

// Include CORS headers in ALL responses (success and error)
const corsHeaders = {
  'Access-Control-Allow-Origin': isAllowedOrigin(origin) ? origin : '',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'Content-Type',
};
```

### No `X-Frame-Options` for Embedded Apps

Shopify apps render inside an iframe in the admin. Setting `X-Frame-Options: DENY` breaks the entire app.

```typescript
// CDK: CloudFront security headers policy OMITS frameOptions
const securityHeaders = new cloudfront.ResponseHeadersPolicy(this, 'SecurityHeaders', {
  securityHeadersBehavior: {
    strictTransportSecurity: { ... },
    xssProtection: { ... },
    // NO frameOptions — Shopify requires iframe embedding
  },
});
```

Shopify's own CSP provides iframe protection — you don't need `X-Frame-Options`.

### S3 Presigned URLs for File Access

Never expose S3 bucket URLs directly. Use presigned URLs with short TTL:

```typescript
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { GetObjectCommand } from '@aws-sdk/client-s3';

const url = await getSignedUrl(
  s3Client,
  new GetObjectCommand({
    Bucket: process.env.AWS_S3_BUCKET,
    Key: `shops/${shopDomain}/applications/${appId}/${filename}`,
  }),
  { expiresIn: 3600 }  // 1 hour
);
```

---

## Polaris UI & Testing

### Polaris-Specific Playwright Selectors

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

### Toast Notifications

```typescript
// In route action, return toast data
return { ok: true, message: 'Settings saved' };

// In component, show Shopify toast
useEffect(() => {
  if (fetcherData?.ok) {
    window.shopify.toast.show(fetcherData.message);
  }
}, [fetcherData]);
```

### FrameLocator Pattern for Embedded Apps

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

### Auth Setup with `--no-deps`

```bash
# First time: run auth setup (saves session to tests/.auth/shopify.json)
npx playwright test --project=auth-setup --headed

# Subsequent runs: skip auth setup, reuse saved session
npx playwright test --no-deps
```

Auth state file is gitignored. Reuse until session expires. Running with `--no-deps` skips the auth-setup project.

### E2E Test Best Practices

- **Identify non-default rows by Delete button** (names accumulate "(Copy)" suffixes):
  ```typescript
  frame.getByRole('row').filter({ has: frame.getByRole('button', { name: 'Delete' }) });
  ```
- **Settings page Save buttons**: Use `nth()` — Branding=0, Tags=1, Notifications=2
- **Test idempotency**: Read current value first, use a different one to ensure `isDirty` flips
- Tests create fresh forms to avoid interference — no shared fixtures

---

## Local Development

### Docker Compose (DynamoDB Local + LocalStack)

```yaml
services:
  dynamodb-local:
    image: amazon/dynamodb-local:latest
    ports:
      - '8000:8000'
    command: '-jar DynamoDBLocal.jar -sharedDb'

  dynamodb-admin:
    image: aaronshaf/dynamodb-admin
    ports:
      - '8001:8001'
    environment:
      - DYNAMO_ENDPOINT=http://dynamodb-local:8000

  localstack:
    image: localstack/localstack
    ports:
      - '4566:4566'
    environment:
      - SERVICES=sqs,s3
```

### Startup Sequence

```bash
# 1. Start infrastructure
docker compose up -d

# 2. Create DynamoDB table (first time only)
npm run setup

# 3. Start app (runs Vite + Cloudflare tunnel + Shopify CLI)
shopify app dev
```

### Vite HMR + Tunnel Issues

Changes to `.server.ts` service files sometimes don't hot-reload through the Cloudflare tunnel. A full `shopify app dev` restart may be needed. Touching the route file that imports the service doesn't help.

### DynamoDB Local Direct Access

```bash
# Query a record
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  aws dynamodb get-item \
  --table-name B2BOnboard \
  --key '{"PK":{"S":"SHOP#example.myshopify.com"},"SK":{"S":"SHOP#METADATA"}}' \
  --endpoint-url http://localhost:8000 \
  --region us-east-1

# Update a record
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  aws dynamodb update-item \
  --table-name B2BOnboard \
  --key '{"PK":{"S":"SHOP#example.myshopify.com"},"SK":{"S":"SHOP#METADATA"}}' \
  --update-expression 'SET billingPlan = :plan' \
  --expression-attribute-values '{":plan":{"S":"Growth Monthly"}}' \
  --endpoint-url http://localhost:8000 \
  --region us-east-1
```

Use **NoSQL Workbench** (free AWS tool) for a visual DynamoDB browser.

---

## CDK Infrastructure Patterns

### No-VPC Serverless Architecture

All resources are serverless and don't require a VPC:

| Resource | Service |
|----------|---------|
| Compute | Lambda (Docker image) |
| API | API Gateway v2 (HTTP API) |
| Database | DynamoDB |
| Storage | S3 |
| Queue | SQS |
| CDN | CloudFront |
| Email | SES / Resend |
| Secrets | Secrets Manager + SSM Parameter Store |
| Monitoring | CloudWatch + SNS |

### CloudFront CSRF Fix

```typescript
// cdn-stack.ts — essential for React Router POST actions
const apiOrigin = new origins.HttpOrigin(apiDomain, {
  customHeaders: {
    'x-forwarded-host': config.domainName,
  },
});
```

### No X-Frame-Options for Shopify Apps

```typescript
const securityHeaders = new cloudfront.ResponseHeadersPolicy(this, 'SecurityHeaders', {
  securityHeadersBehavior: {
    strictTransportSecurity: {
      accessControlMaxAge: Duration.seconds(63072000),
      includeSubdomains: true,
      preload: true,
      override: true,
    },
    xssProtection: { protection: true, modeBlock: true, override: true },
    referrerPolicy: {
      referrerPolicy: cloudfront.HeadersReferrerPolicy.STRICT_ORIGIN_WHEN_CROSS_ORIGIN,
      override: true,
    },
    // Explicitly NO frameOptions — Shopify iframe embedding requires it
  },
});
```

### ACM Certs in us-east-1

CloudFront requires certificates in `us-east-1`, even when all other resources are in another region. Create manually or use a cross-region CDK construct:

```typescript
// Import certificate by ARN (created manually in us-east-1)
const certificate = acm.Certificate.fromCertificateArn(
  this, 'Cert', config.certificateArn
);
```

### ESM Lambda Build

Use esbuild with ESM format and a `createRequire` banner for Node.js built-in compatibility:

```dockerfile
# Dockerfile.lambda
FROM node:20-slim AS bundler
RUN npx esbuild src/lambda.ts \
  --bundle \
  --format=esm \
  --target=node20 \
  --platform=node \
  --banner:js="import{createRequire}from'module';const require=createRequire(import.meta.url);"
```

### OIDC CI/CD (No Stored AWS Credentials)

Use GitHub Actions OIDC federation for deployments:

```yaml
# .github/workflows/deploy.yml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    environment: staging
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: eu-central-1

      - run: npx cdk deploy --all -c env=staging --require-approval never
```

### BillingStack in us-east-1

AWS Budget and EstimatedCharges metrics only exist in `us-east-1`. Deploy the BillingStack in that region:

```typescript
new BillingStack(app, `B2bOnboardBillingStack-${env}`, {
  env: { account, region: 'us-east-1' },
  // ...
});
```

CDK bootstrap must exist in both regions.

### Monitoring Alarms

Key alarms to set up:

| Alarm | Metric | Threshold |
|-------|--------|-----------|
| API 5xx errors | 5XXError | > 5 in 5 min |
| API latency | Latency p99 | > 10s in 5 min |
| DLQ messages (email) | ApproximateNumberOfMessagesVisible | > 0 |
| DLQ messages (export) | ApproximateNumberOfMessagesVisible | > 0 |
| DynamoDB throttles | ThrottledRequests | > 0 in 5 min |
| Lambda concurrency | ConcurrentExecutions | > 80% reserved |
| Monthly cost | EstimatedCharges | > $30 |

### SQS Worker Configuration

```typescript
// Email queue — batch 10, 60s visibility, 3 retries
const emailQueue = new sqs.Queue(this, 'EmailQueue', {
  visibilityTimeout: Duration.seconds(60),
  deadLetterQueue: { queue: emailDlq, maxReceiveCount: 3 },
});

// Export queue — batch 1, 5min visibility, 2 retries
const exportQueue = new sqs.Queue(this, 'ExportQueue', {
  visibilityTimeout: Duration.minutes(5),
  deadLetterQueue: { queue: exportDlq, maxReceiveCount: 2 },
});
```

---

## Project Structure & Conventions

### Directory Layout

```
your-app/
  app/
    routes/              # File-based routes
    components/          # React components
    services/            # Server-side business logic (*.server.ts)
      dynamodb/          # DynamoDB keys and mappers
    lib/                 # Core infrastructure (dynamodb.server.ts, config.server.ts)
    lambda-workers/      # SQS Lambda handlers
    types/               # TypeScript types
    utils/               # Shared utilities
    styles/              # CSS (proxy.css for inline styles)
    shopify.server.ts    # shopifyApp() config
    lambda.server.ts     # Lambda entry point
  scripts/
    create-table.ts      # DynamoDB table + GSI creation
  tests/
    auth.setup.ts        # Playwright auth setup
    helpers/             # Test utilities (app-frame.ts)
    e2e/                 # Playwright specs
  extensions/            # Shopify app extensions
infra/
  bin/app.ts             # CDK entry point
  lib/                   # Stack definitions
  test/                  # CDK unit tests
docs/                    # Legal pages, DR runbook, compliance
```

### Service File Conventions

- All database access goes through `app/services/*.server.ts`
- Service functions take `shopDomain` as first param (multi-tenant scoping)
- Keys are generated via `app/services/dynamodb/keys.ts`
- Mappers convert DynamoDB items to typed objects in `app/services/dynamodb/mappers.ts`
- File suffix `.server.ts` ensures code is tree-shaken from client bundles

### Environment Variables Reference

| Variable | Source | Description |
|----------|--------|-------------|
| `SHOPIFY_API_KEY` | Secrets Manager | App API key |
| `SHOPIFY_API_SECRET` | Secrets Manager | App API secret |
| `SHOPIFY_APP_URL` | SSM | App URL (e.g., `https://staging.example.com`) |
| `DYNAMODB_TABLE` | SSM | DynamoDB table name |
| `DYNAMODB_ENDPOINT` | .env (local only) | DynamoDB Local endpoint |
| `AWS_S3_BUCKET` | SSM | S3 documents bucket |
| `EMAIL_FROM` | SSM | Sender email address |
| `EMAIL_QUEUE_URL` | SSM | SQS email queue URL |
| `EXPORT_QUEUE_URL` | SSM | SQS export queue URL |
| `RECAPTCHA_SITE_KEY` | Secrets Manager | reCAPTCHA site key |
| `RECAPTCHA_SECRET_KEY` | Secrets Manager | reCAPTCHA secret key |
| `SCOPES` | .env / toml | Comma-separated Shopify scopes |

### Shopify App TOML Config

```toml
# shopify.app.toml
name = "Your App"
client_id = "..."

[access_scopes]
scopes = "read_customers,write_customers,read_files,write_files,read_companies,write_companies,read_products,write_products"

[webhooks]
api_version = "2025-10"

  [webhooks.subscriptions.privacy]
    topics = ["customers/data_request", "customers/redact", "shop/redact"]

[app_proxy]
url = "https://your-domain.com/proxy"
subpath = "wholesale-register"
prefix = "apps"
```
