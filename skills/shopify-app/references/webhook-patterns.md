# Webhook Patterns

## Webhook Handler Pattern

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

**Key points:**
- Always use `authenticate.webhook(request)` for verification
- Always return status 200 (Shopify retries on failure)
- Keep handlers idempotent — webhooks may be delivered more than once

---

## Mandatory GDPR Webhooks

Every Shopify app must implement these three:

### 1. `customers/data_request`

Log the request and fulfill within 30 days:

```typescript
// app/routes/webhooks.app.customers-data-request.tsx
export const action = async ({ request }: ActionFunctionArgs) => {
  const { shop, topic, payload } = await authenticate.webhook(request);

  // Log the request for manual fulfillment
  logAuditEvent({
    shopDomain: shop,
    action: 'gdpr.data_request',
    resourceType: 'Customer',
    resourceId: payload.customer?.id,
  });

  return new Response(null, { status: 200 });
};
```

### 2. `customers/redact`

Delete customer PII — uploaded files from S3 + DynamoDB records:

```typescript
// app/routes/webhooks.app.customers-redact.tsx
export const action = async ({ request }: ActionFunctionArgs) => {
  const { shop, payload } = await authenticate.webhook(request);

  // Delete each application's uploaded documents from S3
  // Delete customer-related DynamoDB records

  return new Response(null, { status: 200 });
};
```

### 3. `shop/redact`

Delete all shop data — S3 prefixes + DynamoDB items:

```typescript
// app/routes/webhooks.app.shop-redact.tsx
export const action = async ({ request }: ActionFunctionArgs) => {
  const { shop } = await authenticate.webhook(request);

  // Delete S3 prefixes: shops/{domain}/ and exports/{safeDomain}/
  // Delete all DynamoDB items for the shop

  return new Response(null, { status: 200 });
};
```

---

## Uninstall Cleanup with Batch Delete

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

**Note:** Query may return items with different SK prefixes (FORM#, APPLICATION#, etc.). Delete them all.

---

## Reinstall Detection

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

Reinstall detection happens in the `app.tsx` loader during `authenticate.admin()` — if the shop record exists with `uninstalledAt` set, the shop has reinstalled.

---

## Shopify App TOML Webhook Config

```toml
# shopify.app.toml
[webhooks]
api_version = "2025-10"

  [webhooks.subscriptions.privacy]
    topics = ["customers/data_request", "customers/redact", "shop/redact"]
```

The `APP_UNINSTALLED` webhook is registered automatically by the Shopify app package when declared in the route structure.
