# CDK Infrastructure

## No-VPC Serverless Architecture

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

---

## CloudFront CSRF Fix

CloudFront's "AllViewerExceptHostHeader" policy replaces `Host` with the API Gateway domain. React Router POST actions compare `Origin` vs `host`/`x-forwarded-host` — mismatch causes 400 "Bad Request".

```typescript
// cdn-stack.ts — essential for React Router POST actions
const apiOrigin = new origins.HttpOrigin(apiDomain, {
  customHeaders: {
    'x-forwarded-host': config.domainName,  // e.g. 'staging.onboard.example.com'
  },
});
```

Without this, every POST action through CloudFront fails silently.

---

## Security Headers (No X-Frame-Options)

Shopify apps render inside an iframe. Setting `X-Frame-Options: DENY` breaks the entire app.

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

Shopify's own CSP provides iframe protection — you don't need `X-Frame-Options`.

---

## ACM Certificates in us-east-1

CloudFront requires certificates in `us-east-1`, even when all other resources are in another region:

```typescript
// Import certificate by ARN (created manually in us-east-1)
const certificate = acm.Certificate.fromCertificateArn(
  this, 'Cert', config.certificateArn
);
```

---

## BillingStack in us-east-1

AWS Budget and EstimatedCharges metrics only exist in `us-east-1`. Deploy the BillingStack in that region:

```typescript
new BillingStack(app, `B2bOnboardBillingStack-${env}`, {
  env: { account, region: 'us-east-1' },
  // ...
});
```

CDK bootstrap must exist in both regions.

---

## OIDC CI/CD (No Stored AWS Credentials)

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

**Key:** No long-lived AWS access keys stored in GitHub. OIDC tokens are short-lived and scoped to the workflow run.

---

## Monitoring Alarms

| Alarm | Metric | Threshold |
|-------|--------|-----------|
| API 5xx errors | 5XXError | > 5 in 5 min |
| API latency | Latency p99 | > 10s in 5 min |
| DLQ messages (email) | ApproximateNumberOfMessagesVisible | > 0 |
| DLQ messages (export) | ApproximateNumberOfMessagesVisible | > 0 |
| DynamoDB throttles | ThrottledRequests | > 0 in 5 min |
| Lambda concurrency | ConcurrentExecutions | > 80% reserved |
| Monthly cost | EstimatedCharges | > $30 |

All alarms send to an SNS topic → email notification.

---

## SQS Worker Configuration

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

| Queue | Batch Size | Visibility Timeout | Max Retries | Use Case |
|-------|-----------|-------------------|-------------|----------|
| Email | 10 | 60s | 3 | Notification emails |
| Export | 1 | 5 min | 2 | CSV/data exports |

---

## ESM Lambda Build

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

See `references/lambda-architecture.md` for the full cold start pattern.
