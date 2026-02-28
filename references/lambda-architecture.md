# Lambda Architecture

## Cold Start Lazy-Init Pattern

Cache the handler across invocations and initialize config on cold start:

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

**Key points:**
- `cachedHandler` persists across warm invocations
- `initConfig()` only runs once per cold start
- Lazy imports prevent module loading before env vars are set

---

## `initConfig()` for Secrets Manager + SSM

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

**Pattern:** SSM stores non-sensitive config (table names, URLs). Secrets Manager stores sensitive values (API keys). Fetch both in parallel on cold start.

---

## SQS Workers with Partial Batch Failure

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

**Critical:** Return `batchItemFailures` so only failed messages return to the queue. Configure with `ReportBatchItemFailures` in CDK:

```typescript
// In CDK stack
emailLambda.addEventSource(new SqsEventSource(emailQueue, {
  batchSize: 10,
  reportBatchItemFailures: true,
}));
```

---

## ESM Lambda Build with `createRequire`

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

**Why:** Some Node.js packages (especially native AWS SDK modules) use `require()` internally. The `createRequire` banner makes `require` available in ESM context without switching to CommonJS format.
