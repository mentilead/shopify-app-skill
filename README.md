# Shopify App Skill

[![CI](https://github.com/mentilead/shopify-app-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/mentilead/shopify-app-skill/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/mentilead/shopify-app-skill/releases/tag/v1.0.0)
[![Claude Code Skill](https://img.shields.io/badge/Claude_Code-Skill-cc785c?logo=anthropic)](https://docs.anthropic.com/en/docs/claude-code)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

[![Shopify Embedded App](https://img.shields.io/badge/Shopify-Embedded_App-96bf48?logo=shopify&logoColor=white)](https://shopify.dev/docs/apps)
[![React Router v7](https://img.shields.io/badge/React_Router-v7-ca4245?logo=reactrouter&logoColor=white)](https://reactrouter.com/)
[![Shopify Polaris](https://img.shields.io/badge/Shopify-Polaris-008060?logo=shopify&logoColor=white)](https://polaris.shopify.com/)
[![TypeScript](https://img.shields.io/badge/TypeScript-3178C6?logo=typescript&logoColor=white)](https://www.typescriptlang.org/)
[![DynamoDB Single Table](https://img.shields.io/badge/DynamoDB-Single_Table-4053D6?logo=amazondynamodb&logoColor=white)](https://aws.amazon.com/dynamodb/)
[![AWS Lambda](https://img.shields.io/badge/AWS-Lambda-FF9900?logo=awslambda&logoColor=white)](https://aws.amazon.com/lambda/)
[![AWS CDK](https://img.shields.io/badge/AWS-CDK-232F3E?logo=amazonaws&logoColor=white)](https://aws.amazon.com/cdk/)
[![Amazon SQS](https://img.shields.io/badge/Amazon-SQS-FF4F8B?logo=amazonsqs&logoColor=white)](https://aws.amazon.com/sqs/)

A Claude Code skill for building **production-grade embedded Shopify apps** using the modern serverless stack: React Router v7, Polaris, DynamoDB (single-table), Lambda, SQS, CDK.

Every pattern is battle-tested from real app development and Shopify App Store submission.

## Features at a Glance

- **10 Critical Gotchas** — WRONG/CORRECT examples for the hardest-to-debug issues
- **15 Reference Files** — deep-dive patterns for every layer of the stack
- **Battle-Tested** — every pattern from production Shopify App Store apps
- **Token-Optimized** — designed for Claude Code's context window

## Installation

### Option 1: Plugin Marketplace (Recommended)

```bash
/plugin marketplace add mentilead/shopify-app-skill
/plugin install shopify-app-skill@mentilead-shopify-tools
```

### Option 2: Manual (copy to project)

Copy `skills/shopify-app/SKILL.md` and `skills/shopify-app/references/` into your project's `.claude/skills/` directory:

```bash
git clone https://github.com/mentilead/shopify-app-skill.git
mkdir -p .claude/skills/shopify-app
cp shopify-app-skill/skills/shopify-app/SKILL.md .claude/skills/shopify-app/SKILL.md
cp -r shopify-app-skill/skills/shopify-app/references .claude/skills/shopify-app/references
```

### Option 3: Git submodule

```bash
git submodule add https://github.com/mentilead/shopify-app-skill.git .claude/skills/shopify-app
```

## Structure

```
shopify-app-skill/
├── skills/
│   └── shopify-app/
│       ├── SKILL.md                          # Main entry point (gotchas, quick reference, structure)
│       └── references/
│           ├── react-router-patterns.md      # Routing, loaders, actions, fetchers, revalidation
│           ├── dynamodb-patterns.md          # Single-table design, keys, queries, transactions, TTL
│           ├── shopify-api-patterns.md       # GraphQL API, customers, metafields, error handling
│           ├── billing-patterns.md           # Billing flow, isDevelopmentStore, plan gating, trials
│           ├── app-proxy-patterns.md         # HMAC verification, CSS inlining, POST redirect
│           ├── webhook-patterns.md           # Handlers, GDPR webhooks, uninstall, reinstall
│           ├── lambda-architecture.md        # Cold start, SQS workers, config loading
│           ├── cdk-infrastructure.md         # CloudFront, OIDC, monitoring, SQS config
│           ├── polaris-ui-patterns.md        # Navigation, tokens, composition, selectors
│           ├── email-patterns.md             # SQS queuing, suppression, Resend webhooks
│           ├── security-patterns.md          # Multi-tenancy, CORS, S3 presigned URLs
│           ├── testing-patterns.md           # Playwright, FrameLocator, auth setup
│           ├── local-dev-patterns.md         # Docker, DynamoDB Local, startup sequence
│           ├── production-deployment.md      # CloudFront, OIDC deploys, environment config
│           └── project-conventions.md        # File naming, imports, project structure rules
├── .claude-plugin/
│   ├── plugin.json                           # Plugin manifest
│   └── marketplace.json                      # Marketplace manifest
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug-report.yml                    # Bug report template
│   │   └── pattern-request.yml               # Pattern request template
│   ├── pull_request_template.md              # PR checklist
│   └── workflows/
│       └── ci.yml                            # CI validation
├── scripts/
│   └── validate-skill.sh                     # Structure validation script
├── CHANGELOG.md                              # Release history
├── CODE_OF_CONDUCT.md                        # Contributor Covenant v2.1
├── CONTRIBUTING.md                           # How to contribute
├── LICENSE                                   # MIT
├── README.md                                 # This file
└── SECURITY.md                               # Security policy
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

## Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for details on the process for submitting pull requests, the WRONG/CORRECT pattern format, and how to run validation.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Acknowledgments

Built from production experience developing embedded Shopify apps. Patterns refined through real App Store submissions and merchant use.
