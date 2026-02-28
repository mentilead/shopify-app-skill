# Production Deployment Guide

Zero-to-production deployment for embedded Shopify apps on the serverless AWS stack.

---

## 1. AWS Account Setup

Create a standalone AWS account (not a sub-account) to qualify for Free Tier:

```bash
# After account creation:
# 1. Enable MFA on root account (Security Credentials → MFA)
# 2. Create IAM admin user with AdministratorAccess
# 3. Set up billing alerts (Billing → Budgets → Create budget → $30/month)
# 4. Configure CLI profile:
aws configure --profile your-app-prod
# Region: eu-central-1 (or your primary region)
# Output: json
```

Set the profile for all subsequent commands:

```bash
export AWS_PROFILE=your-app-prod
```

---

## 2. ACM Certificate (us-east-1)

CloudFront requires certificates in `us-east-1`, regardless of your app region:

```bash
aws acm request-certificate \
  --domain-name 'app.example.com' \
  --validation-method DNS \
  --region us-east-1

# Output: CertificateArn → save this for CDK config
```

Add the DNS validation CNAME records to your domain. Verify:

```bash
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:ACCOUNT:certificate/CERT_ID \
  --region us-east-1 \
  --query 'Certificate.Status'
# Expected: "ISSUED"
```

---

## 3. CDK Configuration

Configure environments in `cdk.json`:

```json
{
  "app": "npx ts-node --prefer-ts-exts infra/bin/app.ts",
  "context": {
    "environments": {
      "production": {
        "account": "123456789012",
        "region": "eu-central-1",
        "domainName": "app.example.com",
        "certificateArn": "arn:aws:acm:us-east-1:123456789012:certificate/...",
        "notificationEmail": "alerts@example.com"
      },
      "staging": {
        "account": "987654321098",
        "region": "eu-central-1",
        "domainName": "staging.app.example.com",
        "certificateArn": "arn:aws:acm:us-east-1:987654321098:certificate/...",
        "notificationEmail": "alerts@example.com"
      }
    }
  }
}
```

The `-c env=production` flag selects the environment at deploy time.

---

## 4. Secrets Manager Setup

Create 4 secrets per environment (naming convention: `{app}/{env}/{service}`):

```bash
# 1. Shopify credentials (required)
aws secretsmanager create-secret \
  --name 'your-app/production/shopify' \
  --secret-string '{"SHOPIFY_API_KEY":"...","SHOPIFY_API_SECRET":"..."}'

# 2. reCAPTCHA keys (required if using App Proxy forms)
aws secretsmanager create-secret \
  --name 'your-app/production/recaptcha' \
  --secret-string '{"RECAPTCHA_SITE_KEY":"...","RECAPTCHA_SECRET_KEY":"..."}'

# 3. Resend API key (required for email)
aws secretsmanager create-secret \
  --name 'your-app/production/resend' \
  --secret-string '{"RESEND_API_KEY":"..."}'

# 4. GA4 credentials (optional — CDK handles missing gracefully)
aws secretsmanager create-secret \
  --name 'your-app/production/ga4' \
  --secret-string '{"GA4_MEASUREMENT_ID":"...","GA4_API_SECRET":"..."}'
```

---

## 5. Shopify App Creation

In Shopify Partners Dashboard → Apps → Create app:

| Setting | Value |
|---------|-------|
| App URL | `https://app.example.com/app` |
| Allowed redirection URLs | `https://app.example.com/auth/callback` |
| Distribution | Public or Unlisted (not Custom — Custom can't use Billing API) |

Configure webhooks (API version `2025-10`):

| Webhook | Endpoint |
|---------|----------|
| `app/uninstalled` | Managed by Shopify CLI |
| `customers/data_request` | Compliance webhook URL |
| `customers/redact` | Compliance webhook URL |
| `shop/redact` | Compliance webhook URL |

Configure App Proxy if needed:

| Setting | Value |
|---------|-------|
| URL | `https://app.example.com/proxy` |
| Subpath prefix | `apps` |
| Subpath | `your-subpath` |

Copy the API key and secret into Secrets Manager (step 4).

---

## 6. reCAPTCHA Setup

At [Google reCAPTCHA admin](https://www.google.com/recaptcha/admin):

- Type: reCAPTCHA v2 (checkbox)
- Domains: `app.example.com` + your Shopify store domains (e.g., `your-store.myshopify.com`)
- Copy site key and secret key into Secrets Manager (step 4)

---

## 7. Resend Email Setup

At [resend.com](https://resend.com):

1. Verify your sending domain (add DNS records)
2. Create a per-environment API key (e.g., `your-app-production`)
3. Store the API key in Secrets Manager (step 4)
4. **Webhook endpoint** — configure _after_ first deploy (see post-deploy tasks)

---

## 8. CDK Bootstrap

Bootstrap CDK in both regions (app region + us-east-1 for BillingStack):

```bash
# App region
npx cdk bootstrap aws://ACCOUNT_ID/eu-central-1 -c env=production

# us-east-1 (required for BillingStack)
npx cdk bootstrap aws://ACCOUNT_ID/us-east-1 -c env=production
```

**Gotcha:** CDK bootstrap requires `-c env=production` if your `cdk.json` app entry depends on context. Without it, CDK can't resolve the app and bootstrap silently fails.

---

## 9. Build & Deploy

```bash
# Build the app (Lambda Docker image)
npm run build

# Deploy all stacks (order matters — CDK handles dependencies)
npx cdk deploy --all -c env=production --require-approval broadening

# BillingStack deploys separately to us-east-1 (CDK handles this automatically)
```

Stack deployment order (CDK resolves via dependencies):

1. **DatabaseStack** — DynamoDB table, S3 bucket
2. **QueueStack** — SQS queues + DLQs
3. **ComputeStack** — Lambda functions, API Gateway
4. **CdnStack** — CloudFront distribution, security headers
5. **MonitoringStack** — CloudWatch alarms, SNS topic
6. **BillingStack** — AWS Budget alarm (us-east-1)

---

## 10. DNS Configuration

After CdnStack deploys, get the CloudFront distribution domain:

```bash
aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items[?contains(@,'app.example.com')]].DomainName" \
  --output text
# Output: d1234567890.cloudfront.net
```

Add a CNAME record at your DNS provider:

| Type | Name | Value |
|------|------|-------|
| CNAME | `app.example.com` | `d1234567890.cloudfront.net` |

Verify:

```bash
dig app.example.com CNAME +short
# Expected: d1234567890.cloudfront.net

curl -I https://app.example.com/app
# Expected: 302 redirect to Shopify OAuth
```

---

## 11. Post-Deploy Tasks

### SNS Email Confirmation

Check your notification email inbox and confirm the SNS subscription for CloudWatch alarms.

### Resend Webhook Configuration

Now that the app is deployed, configure the Resend webhook:

1. In Resend dashboard → Webhooks → Add endpoint
2. URL: `https://app.example.com/api/webhooks/resend`
3. Events: `email.bounced`, `email.complained`
4. Copy the Svix signing secret
5. Update the Resend secret in Secrets Manager:

```bash
aws secretsmanager update-secret \
  --secret-id 'your-app/production/resend' \
  --secret-string '{"RESEND_API_KEY":"...","RESEND_WEBHOOK_SECRET":"whsec_..."}'
```

**Chicken-and-egg:** You can't get the Svix signing secret until the webhook endpoint exists, which requires the app to be deployed first.

### Lambda Concurrency Quota

New AWS accounts have a default of 10 concurrent Lambda executions. Request an increase:

1. Service Quotas → Lambda → Concurrent executions
2. Request increase to 100+ (approved within 24h typically)

**Symptom if skipped:** `ReservedConcurrencyExceededException` — CDK deploy may fail if reserved concurrency in your stack exceeds the account limit.

---

## 12. GitHub Actions CI/CD

### OIDC Provider Setup

Create the GitHub OIDC provider in IAM (once per account):

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### IAM Role for Deployments

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:your-org/your-app:environment:production"
        }
      }
    }
  ]
}
```

### GitHub Workflow

```yaml
# .github/workflows/deploy.yml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    environment: production  # Requires manual approval
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - run: npm ci
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: eu-central-1
      - run: npm run build
      - run: npx cdk deploy --all -c env=production --require-approval never
```

Set up GitHub environment with required reviewers for production deploys.

---

## 13. Staging vs Production Strategy

| Aspect | Staging | Production |
|--------|---------|------------|
| AWS account | Separate account | Separate account |
| CDK code | Same repo, `-c env=staging` | Same repo, `-c env=production` |
| Shopify app | Separate app in Partners | Separate app in Partners |
| Secrets | Separate Secrets Manager entries | Separate Secrets Manager entries |
| Domain | `staging.app.example.com` | `app.example.com` |
| Dev stores | Non-Plus (Basic) for billing | N/A (real merchants) |

Deploy to staging first, test, then deploy to production:

```bash
# Staging
npx cdk deploy --all -c env=staging --require-approval never

# Production (after staging verification)
npx cdk deploy --all -c env=production --require-approval broadening
```

---

## Common Gotchas

| Symptom | Cause | Fix |
|---------|-------|-----|
| CDK deploy fails with concurrency error | New account has 10 concurrent Lambda limit | Request quota increase in Service Quotas |
| `cdk bootstrap` fails silently | Missing `-c env=` context flag | Add `-c env=production` to bootstrap command |
| Stack stuck in `ROLLBACK_COMPLETE` | Failed deploy can't be updated | Delete stack manually in CloudFormation console, redeploy |
| BillingStack deploy fails (wrong region) | AWS Budget metrics only exist in us-east-1 | Ensure BillingStack targets `us-east-1` in CDK |
| Resend webhooks not verified | Can't get signing secret before deploy | Deploy first, configure webhook after, update secret |
| "This feature isn't currently available" | Plus dev store can't approve test charges | Create a Basic (non-Plus) dev store for billing testing |
| POST actions return 400 Bad Request | CloudFront strips Host header → CSRF mismatch | Add `x-forwarded-host` custom origin header in CDK |
| App breaks out of Shopify admin | Using Polaris `url` prop for internal nav | Use `useNavigate()` instead |
