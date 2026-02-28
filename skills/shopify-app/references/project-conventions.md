# Project Conventions

## Service File Conventions

### `.server.ts` Suffix Rule

Files ending in `.server.ts` are **tree-shaken from client bundles** by React Router v7's Vite plugin. All database access, secrets, and server-only logic must live in `.server.ts` files.

```
app/services/forms.server.ts       ✓ Tree-shaken from client
app/services/forms.ts              ✗ Leaks server code to browser
app/lib/dynamodb.server.ts         ✓ DynamoDB client stays server-side
app/lib/config.server.ts           ✓ SSM/Secrets Manager stays server-side
```

### `shopDomain` First Parameter

Every service function takes `shopDomain: string` as its first parameter — this is the multi-tenant scoping key for DynamoDB:

```typescript
// CORRECT — shopDomain scopes all queries to one merchant
export async function getForms(shopDomain: string): Promise<Form[]> { ... }
export async function getForm(shopDomain: string, formId: string): Promise<Form | null> { ... }
export async function saveForm(shopDomain: string, form: FormInput): Promise<void> { ... }
```

### Keys Module

Centralize all DynamoDB key generation in `app/services/dynamodb/keys.ts`. Never construct key strings inline in service functions. See `references/dynamodb-patterns.md` for the full keys module.

### Mapper Functions

Convert between DynamoDB items and domain objects at the service boundary:

```typescript
// app/services/dynamodb/mappers.ts

// DynamoDB item → domain object (used in loaders)
function itemToForm(item: Record<string, unknown>): Form {
  return {
    id: (item.SK as string).replace('FORM#', ''),
    title: item.title as string,
    status: item.status as FormStatus,
    updatedAt: item.updatedAt as string,
  };
}

// Form input → DynamoDB item (used in actions)
function formToItem(shopDomain: string, form: FormInput): Record<string, unknown> {
  const { PK, SK, GSI1PK, GSI1SK } = keys.form(shopDomain, form.id);
  return { PK, SK, GSI1PK, GSI1SK, title: form.title, status: form.status, updatedAt: new Date().toISOString() };
}
```

### Complete Service Function Skeleton

```typescript
// app/services/forms.server.ts
import { docClient, TABLE } from '~/lib/dynamodb.server';
import { keys } from '~/services/dynamodb/keys';
import { itemToForm, formToItem } from '~/services/dynamodb/mappers';
import type { Form, FormInput } from '~/types';

export async function getForms(shopDomain: string): Promise<Form[]> {
  const { PK, SKPrefix } = keys.formByShop(shopDomain);
  const result = await docClient.query({
    TableName: TABLE,
    KeyConditionExpression: 'PK = :pk AND begins_with(SK, :sk)',
    ExpressionAttributeValues: { ':pk': PK, ':sk': SKPrefix },
  });
  return (result.Items ?? []).map(itemToForm);
}
```

---

## Environment Variables

| Variable | Local (`.env`) | Production (source) |
|----------|---------------|---------------------|
| `SHOPIFY_API_KEY` | Value from Partners | Secrets Manager |
| `SHOPIFY_API_SECRET` | Value from Partners | Secrets Manager |
| `SHOPIFY_APP_URL` | Cloudflare tunnel URL | SSM Parameter Store |
| `SCOPES` | Comma-separated | Hardcoded in `shopify.server.ts` |
| `DYNAMODB_TABLE` | `B2BOnboard` | SSM Parameter Store |
| `DYNAMODB_ENDPOINT` | `http://localhost:8000` | Not set (AWS SDK default) |
| `AWS_REGION` | `us-east-1` | Lambda runtime |
| `AWS_S3_BUCKET` | `local-bucket` | SSM Parameter Store |
| `AWS_S3_ENDPOINT` | `http://localhost:4566` | Not set |
| `EMAIL_QUEUE_URL` | LocalStack URL | SSM Parameter Store |
| `EXPORT_QUEUE_URL` | LocalStack URL | SSM Parameter Store |
| `RECAPTCHA_SITE_KEY` | Test key | Secrets Manager |
| `RECAPTCHA_SECRET_KEY` | Test key | Secrets Manager |
| `RESEND_API_KEY` | Dev API key | Secrets Manager |
| `RESEND_WEBHOOK_SECRET` | — | Secrets Manager (post-deploy) |

**Secrets Manager naming convention:** `{app}/{env}/{service}` (e.g., `b2b-onboard/production/shopify`).

**Local endpoints:** `DYNAMODB_ENDPOINT` and `AWS_S3_ENDPOINT` are only set locally to point at Docker containers. In production, omitting them lets the AWS SDK use its default regional endpoints.

---

## `shopify.app.toml` Config Template

```toml
# shopify.app.toml — committed to repo, used by `shopify app dev`
name = "Your App Name"
client_id = "abc123-from-partners-dashboard"
application_url = "https://your-tunnel.trycloudflare.com"
embedded = true

[auth]
redirect_urls = [
  "https://your-tunnel.trycloudflare.com/auth/callback",
  "https://your-production-domain.com/auth/callback"
]

[webhooks]
api_version = "2025-10"

  [webhooks.privacy_compliance]
  customer_data_request_url = "https://your-production-domain.com/webhooks/app/customers-data-request"
  customer_deletion_url = "https://your-production-domain.com/webhooks/app/customers-redact"
  shop_deletion_url = "https://your-production-domain.com/webhooks/app/shop-redact"

  # App-specific topics
  [[webhooks.subscriptions]]
  topics = ["app/uninstalled"]
  uri = "https://your-production-domain.com/webhooks/app/uninstalled"

[app_proxy]
url = "https://your-production-domain.com/proxy"
subpath_prefix = "apps"
subpath = "your-app"

[pos]
embedded = false
```

**Notes:**
- `application_url` changes between local (tunnel) and production — update before deploying
- `client_id` comes from the Partners dashboard after app creation
- Webhook URLs must use the production domain (Shopify sends them directly, not through the tunnel)
- `[pos] embedded = false` for non-POS apps

---

## Route File Conventions

| Prefix | Auth | Layout | Example |
|--------|------|--------|---------|
| `app.` | `authenticate.admin()` | Polaris + nav | `app.forms.$id.tsx` |
| `proxy.` | HMAC verification | Public branding | `proxy.$formId.tsx` |
| `api.` | None (custom) | Headless (no UI) | `api.submit-application.tsx` |
| `webhooks.` | `authenticate.webhook()` | None | `webhooks.app.uninstalled.tsx` |

**Layout routes:** `app.tsx` and `proxy.tsx` are layout routes — they wrap all child routes under their prefix. See `references/react-router-patterns.md` for loader/action patterns, `shouldRevalidate`, and billing sync.

---

## Lambda Worker Conventions

Workers live in `app/lambda-workers/` and handle async tasks from SQS queues.

### Entry Point Pattern

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
      await processMessage(payload);
    } catch (err) {
      console.error(`Failed: ${record.messageId}`, err);
      batchItemFailures.push({ itemIdentifier: record.messageId });
    }
  }

  return { batchItemFailures };
}
```

**Key rules:**
- Always call `initConfig()` first — loads SSM/Secrets Manager values on cold start
- Return `SQSBatchResponse` with partial failures so only failed messages retry
- Each worker gets its own SQS queue and CDK Lambda function
- See `references/lambda-architecture.md` for cold start optimization and `initConfig()` details
