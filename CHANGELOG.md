# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-02-28

### Added

- **SKILL.md** — main entry point with 10 critical gotchas, quick reference, and file structure
- **react-router-patterns.md** — routing, loaders, actions, fetchers, revalidation
- **dynamodb-patterns.md** — single-table design, keys, queries, transactions, TTL
- **shopify-api-patterns.md** — GraphQL API, customers, metafields, error handling
- **billing-patterns.md** — billing flow, isDevelopmentStore, plan gating, trials
- **app-proxy-patterns.md** — HMAC verification, CSS inlining, POST redirect
- **webhook-patterns.md** — handlers, GDPR webhooks, uninstall, reinstall
- **lambda-architecture.md** — cold start, SQS workers, config loading
- **cdk-infrastructure.md** — CloudFront, OIDC, monitoring, SQS config
- **polaris-ui-patterns.md** — navigation, tokens, composition, selectors
- **email-patterns.md** — SQS queuing, suppression, Resend webhooks
- **security-patterns.md** — multi-tenancy, CORS, S3 presigned URLs
- **testing-patterns.md** — Playwright, FrameLocator, auth setup
- **local-dev-patterns.md** — Docker, DynamoDB Local, startup sequence
- **production-deployment.md** — CloudFront, OIDC deploys, environment config
- **project-conventions.md** — file naming, imports, project structure rules
- CI validation workflow
- Plugin marketplace manifests
- Validation script (`scripts/validate-skill.sh`)

[1.0.0]: https://github.com/mentilead/shopify-app-skill/releases/tag/v1.0.0
