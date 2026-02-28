# Local Development Patterns

## Docker Compose (DynamoDB Local + LocalStack)

```yaml
# docker-compose.yml
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

### Services

| Service | Port | Purpose |
|---------|------|---------|
| DynamoDB Local | 8000 | Local DynamoDB |
| DynamoDB Admin | 8001 | Visual table browser |
| LocalStack | 4566 | Local SQS + S3 |

---

## Startup Sequence

```bash
# 1. Start infrastructure
docker compose up -d

# 2. Create DynamoDB table (first time only)
npm run setup

# 3. Start app (runs Vite + Cloudflare tunnel + Shopify CLI)
shopify app dev
```

The `npm run setup` script creates the DynamoDB table with GSI and configures LocalStack SQS queues.

---

## DynamoDB Local Direct Access

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

---

## `shopify app dev --reset` for Cached Store

The `--store` flag is ignored when there's a cached store association:

```bash
# WRONG — --store flag is ignored
shopify app dev --store different-store.myshopify.com

# CORRECT — reset the cached association first
shopify app dev --reset
# Then select the new store interactively
```

---

## Vite HMR + Tunnel Issues

Changes to `.server.ts` service files sometimes don't hot-reload through the Cloudflare tunnel. A full `shopify app dev` restart may be needed.

**Workarounds:**
- Touch the route file that imports the service (sometimes triggers reload)
- Restart `shopify app dev` for guaranteed fresh state
- Use DynamoDB Admin (port 8001) to verify data changes independently

---

## NoSQL Workbench

Use **NoSQL Workbench** (free AWS tool) for a visual DynamoDB browser. More powerful than dynamodb-admin for:
- Visualizing table structure and GSIs
- Building and testing queries
- Exporting/importing data

---

## Environment Variables for Local Dev

```bash
# .env
SHOPIFY_API_KEY=your-api-key
SHOPIFY_API_SECRET=your-api-secret
SHOPIFY_APP_URL=https://your-tunnel.trycloudflare.com
SCOPES=read_customers,write_customers,read_files,write_files
DYNAMODB_TABLE=B2BOnboard
DYNAMODB_ENDPOINT=http://localhost:8000
AWS_REGION=us-east-1
AWS_S3_BUCKET=local-bucket
AWS_S3_ENDPOINT=http://localhost:4566
EMAIL_QUEUE_URL=http://localhost:4566/000000000000/email-queue
EXPORT_QUEUE_URL=http://localhost:4566/000000000000/export-queue
```

When `DYNAMODB_ENDPOINT` is set, `initConfig()` skips Secrets Manager and SSM calls — `.env` provides all values directly.

---

## Shopify CLI Workflow

### Scaffolding a New App

```bash
# Interactive — prompts for template, language, partner org
shopify app init

# Non-interactive — specify options
shopify app init --name my-app --template remix --flavor typescript
```

Template options: `remix` (recommended), `node`, `ruby`, `php`. After init, the CLI creates `shopify.app.toml` with app configuration.

### Deploying to Shopify

```bash
# Push config + extensions to Shopify (creates a versioned release)
shopify app deploy

# Deploy with a custom message
shopify app deploy --message "v1.2: added billing support"
```

`deploy` pushes the app configuration and any extensions to Shopify's servers. It does **not** deploy your web app — host that separately (Lambda, Docker, etc.).

**Version flow:** Each `deploy` creates a new version. Use `--force` to overwrite the current version instead.

### Other Useful Commands

| Command | Purpose |
|---------|---------|
| `shopify app dev` | Start local dev server with tunnel |
| `shopify app dev --reset` | Clear cached store association |
| `shopify app info` | Show app config and URLs |
| `shopify app env pull` | Pull env vars from partner dashboard |
| `shopify app generate extension` | Scaffold a new extension |

---

## Extension Patterns (Out of Scope)

The following extension types exist but are **out of scope** for this skill:

- **Checkout UI Extensions** — custom checkout steps, upsells, post-purchase
- **Shopify Functions** — serverless backend logic (discounts, payment customization)
- **POS Extensions** — point-of-sale UI tiles and screens

For these, consult the official docs: [shopify.dev/docs/apps/build](https://shopify.dev/docs/apps/build).
