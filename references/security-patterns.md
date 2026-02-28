# Security Patterns

## Multi-Tenancy Scoping

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

**Rule:** Service functions always take `shopDomain` as the first parameter. The DynamoDB key structure (`PK = SHOP#<domain>`) enforces isolation at the data layer.

---

## CORS for Submission Endpoint

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

**Important:** Include CORS headers on error responses too — browsers block reading error details without them.

---

## S3 Presigned URLs for File Access

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

**S3 key convention:** `shops/{shopDomain}/applications/{appId}/{filename}` — enables bulk deletion by prefix during GDPR shop/redact.

---

## No X-Frame-Options for Embedded Apps

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

---

## Audit Logging (Fire-and-Forget)

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
