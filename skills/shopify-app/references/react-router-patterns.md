# React Router Patterns

## File-Based Routing Conventions

React Router v7 uses `@react-router/fs-routes`. Route prefixes determine behavior:

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

### Prefix Meanings

- `app.` = authenticated admin routes (inside Shopify iframe)
- `proxy.` = public routes through App Proxy (HMAC verification, no auth)
- `api.` = headless API endpoints (no UI)
- `webhooks.` = Shopify webhook handlers
- `_index` = index route for a parent segment
- `$param` = dynamic route parameter

---

## Loader/Action Patterns

### Loader with Authentication

```typescript
export const loader = async ({ request }: LoaderFunctionArgs) => {
  const { session, admin } = await authenticate.admin(request);
  const forms = await queryFormsByShop(session.shop);
  return { forms };
};
```

### Action with Fetcher Response

```typescript
export const action = async ({ request }: ActionFunctionArgs) => {
  const { session } = await authenticate.admin(request);
  const formData = await request.formData();

  try {
    await updateSettings(session.shop, {
      brandColor: formData.get('brandColor') as string,
    });
    return { ok: true, message: 'Settings saved' };
  } catch (error) {
    return { ok: false, error: 'Failed to save settings' };
  }
};
```

---

## `useFetcher` vs `useActionData` (GOTCHA)

When submitting via `fetcher.submit()`, responses go to `fetcher.data`, **NOT** `useActionData()`.

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

**When to use which:**
- `useFetcher` — form submissions that shouldn't trigger full page navigation (settings saves, inline edits, delete actions)
- `useActionData` — only works with `<Form>` component submissions (not `fetcher.submit()`)

---

## `useState` Sync with Loader Data (GOTCHA)

After a fetcher action updates the database, the loader returns fresh data — but `useState` still holds the old value.

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

**Key:** Use `updatedAt` (or similar) as a change signal. Don't compare the value itself — the user may have edited it since the last save.

---

## `shouldRevalidate` for Layout Loaders

The layout loader (`app.tsx`) runs `authenticate.admin()` + `billing.check()` on every revalidation. This is expensive and causes page flicker on fetcher actions.

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

---

## Parent + Child Parallel Loader Race Condition (GOTCHA)

React Router v7 runs parent (`app.tsx`) and child loaders **in parallel**. If the parent writes billing data to DynamoDB after approval, child loaders may read stale data.

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

---

## Layout Route (`app.tsx`) Pattern

```tsx
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
  // Billing sync + charge_id redirect (see billing-patterns.md)
  return { apiKey: process.env.SHOPIFY_API_KEY || '', plan: currentPlan };
};

export default function App() {
  const { apiKey } = useLoaderData<typeof loader>();
  return (
    <AppProvider embedded apiKey={apiKey}>
      <s-app-nav>
        <s-link href="/app">Dashboard</s-link>
        <s-link href="/app/forms">Forms</s-link>
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

export function ErrorBoundary() {
  return boundary.error(useRouteError());
}

export const headers: HeadersFunction = (headersArgs) => {
  return boundary.headers(headersArgs);
};
```
