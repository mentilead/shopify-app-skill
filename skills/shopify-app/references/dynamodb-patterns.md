# DynamoDB Patterns

## Key Structure

Single-table design with composite keys and a GSI for cross-partition queries:

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

---

## Keys Module Pattern

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

---

## `begins_with` Entity Queries

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

---

## Atomic Transactions (Find-or-Create)

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

---

## Batch Deletion (Max 25 Items)

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

---

## TTL Conventions

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

---

## DynamoDB Client Setup

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

---

## Session Storage Implementation

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
