# Billing Patterns

## Full Billing Flow

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

---

## `billing.request()` Throws on Success

This is unintuitive — `billing.request()` throws a redirect `Response` when the subscription is successfully created. Let it propagate:

```typescript
// WRONG — catching the redirect prevents billing from working
try {
  await billing.request({ plan: planName, isTest });
} catch (e) {
  return { error: 'Billing failed' };
}

// CORRECT — let the redirect throw propagate
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

---

## `isDevelopmentStore()` Detection

```typescript
// WRONG — always false on Lambda (staging + production)
isTest: process.env.NODE_ENV !== 'production'

// CORRECT — detect via Shopify GraphQL API
async function isDevelopmentStore(
  admin: AdminApiContext
): Promise<boolean> {
  const response = await admin.graphql(
    `{ shop { plan { partnerDevelopment } } }`
  );
  const { data } = await response.json();
  return data?.shop?.plan?.partnerDevelopment === true;
}

// Usage in billing action:
isTest: await isDevelopmentStore(admin)
```

---

## Trial Info from `billing.check()`

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

---

## Plan-Gating Pattern with PLAN_LIMITS

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

Check limits in service functions before allowing actions:

```typescript
const limits = getPlanLimits(shop.billingPlan);
const currentCount = await countFormsByShop(shopDomain);
if (currentCount >= limits.maxForms) {
  return { error: `Your ${shop.billingPlan || 'free'} plan allows ${limits.maxForms} forms.` };
}
```

---

## Plus Dev Store Workaround

Plus development stores show "This feature isn't currently available" when redirected to the billing confirmation page. This is a known Shopify bug.

| Store | Plan | Use for |
|-------|------|---------|
| your-app-dev | Plus | B2B features, app proxy, integration testing |
| your-app-billing-test | Basic | Billing flow testing |

---

## Custom App Restriction

Apps with "Custom" distribution cannot use the Billing API at all. The app must be **Public** or **Unlisted**:

```typescript
// shopify.server.ts — must be AppStore or SingleMerchant, not ShopifyAdmin
const shopify = shopifyApp({
  distribution: AppDistribution.AppStore,
  // ...
});
```

---

## `charge_id` Redirect Pattern

After billing approval, Shopify redirects to `/app?charge_id=XXX`. The parent loader processes this and redirects to avoid the parallel loader race condition:

```typescript
// In app.tsx loader
const url = new URL(request.url);
if (url.searchParams.has('charge_id')) {
  // Sync billing to DynamoDB first...
  url.searchParams.delete('charge_id');
  throw redirect(url.pathname + url.search);
}
```

This forces all loaders to re-run with fresh DynamoDB data.

---

## Plan Definition in `shopifyApp()` Config

```typescript
// In shopify.server.ts
const shopify = shopifyApp({
  billing: {
    'Starter Monthly': {
      amount: 9.99,
      currencyCode: 'USD',
      interval: BillingInterval.Every30Days,
    },
    'Growth Monthly': {
      amount: 29.99,
      currencyCode: 'USD',
      interval: BillingInterval.Every30Days,
      trialDays: 14,
    },
  },
  // ...other config
});
```
