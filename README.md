# Shopify App Skill

A Claude Code skill for building **production-grade embedded Shopify apps** using the modern serverless stack: React Router v7, Polaris, DynamoDB (single-table), Lambda, SQS, CDK.

Every pattern is battle-tested from real app development and Shopify App Store submission.

## Installation

### Option 1: Claude Code CLI

```bash
claude skill add shopify-app-skill
```

### Option 2: Manual (copy to project)

Copy `SKILL.md` and the `references/` directory into your project's `.claude/skills/` directory:

```bash
git clone https://github.com/peerjakobsen/shopify-app-skill.git
cp shopify-app-skill/SKILL.md .claude/skills/shopify-app/SKILL.md
cp -r shopify-app-skill/references .claude/skills/shopify-app/references
```

### Option 3: Git submodule

```bash
git submodule add https://github.com/peerjakobsen/shopify-app-skill.git .claude/skills/shopify-app
```

## Structure

```
shopify-app-skill/
├── SKILL.md                              # Main entry point (gotchas, quick reference, structure)
├── references/
│   ├── react-router-patterns.md          # Routing, loaders, actions, fetchers, revalidation
│   ├── dynamodb-patterns.md              # Single-table design, keys, queries, transactions, TTL
│   ├── shopify-api-patterns.md           # GraphQL API, customers, metafields, error handling
│   ├── billing-patterns.md              # Billing flow, isDevelopmentStore, plan gating, trials
│   ├── app-proxy-patterns.md            # HMAC verification, CSS inlining, POST redirect
│   ├── webhook-patterns.md             # Handlers, GDPR webhooks, uninstall, reinstall
│   ├── lambda-architecture.md           # Cold start, SQS workers, config loading
│   ├── cdk-infrastructure.md            # CloudFront, OIDC, monitoring, SQS config
│   ├── polaris-ui-patterns.md           # Navigation, tokens, composition, selectors
│   ├── email-patterns.md               # SQS queuing, suppression, Resend webhooks
│   ├── security-patterns.md            # Multi-tenancy, CORS, S3 presigned URLs
│   ├── testing-patterns.md             # Playwright, FrameLocator, auth setup
│   └── local-dev-patterns.md           # Docker, DynamoDB Local, startup sequence
├── plugin.json                          # Plugin manifest
├── scripts/
│   └── validate-skill.sh               # Structure validation script
├── LICENSE                              # MIT
└── README.md                           # This file
```

## Token Budgets

| File | Target |
|------|--------|
| SKILL.md | < 4,000 tokens |
| Each reference file | < 3,000 tokens |

## What's In Scope

- Embedded Shopify apps (inside Shopify admin iframe)
- React Router v7 (`@shopify/shopify-app-react-router`)
- Shopify Polaris UI components
- Shopify GraphQL Admin API
- DynamoDB single-table design
- AWS Lambda + API Gateway v2 + CloudFront
- AWS CDK for infrastructure
- App Proxy, Billing API, Webhooks, GDPR compliance

## What's Out of Scope

- Liquid theme development
- Hydrogen / headless commerce
- Checkout UI Extensions
- Shopify Functions
- POS extensions
- Prisma / PostgreSQL database patterns

## Companion Tools

Use the official [Shopify Dev MCP server](https://shopify.dev/docs/apps/build/devmcp) alongside this skill for documentation search, GraphQL schema exploration, and Liquid validation.

## License

MIT

## Acknowledgments

Built from production experience developing embedded Shopify apps. Patterns refined through real App Store submissions and merchant use.
