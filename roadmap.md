# Shopify App Skill — Roadmap

## What This Is

A Claude Code skill for building **production-grade embedded Shopify apps** using the modern serverless stack: React Router v7, Polaris, DynamoDB (single-table), Lambda, SQS, CDK. Every pattern encoded in this skill is battle-tested from real app development and Shopify App Store submission.

## Why This Skill Exists

Existing Shopify Claude Code plugins (Saroj Punde's 16-plugin "Shopify Dev Toolkit", davila7's templates, etc.) have critical gaps:

- **They target Prisma/PostgreSQL** — our stack uses DynamoDB single-table design, which has fundamentally different patterns (key design, `begins_with` queries, batch operations, TTL, transactions)
- **No serverless architecture coverage** — Lambda cold starts, SQS workers, CDK infrastructure-as-code, Secrets Manager/SSM config loading are completely absent
- **No billing implementation** — the Shopify Billing API has unintuitive behavior (`billing.request()` throws on success, parallel loader race conditions, Plus dev stores can't approve test charges) that existing skills don't document
- **No App Proxy patterns** — GET-only constraint, no external CSS/JS, inline styles, POST-redirect-back flow
- **Shallow on gotchas** — the hardest-to-debug issues (Polaris `url` prop breaking iframe, `useFetcher` vs `useActionData`, `useState` not syncing with loader, CloudFront CSRF, `NODE_ENV` for billing `isTest`) are undocumented anywhere
- **No deployment pipeline** — CDK stacks, OIDC CI/CD, CloudFront configuration, ACM certificates, monitoring alarms
- **No GDPR/compliance** — mandatory webhook handlers, data retention, S3 cleanup patterns

This skill fills those gaps with production-proven code patterns and explicit WRONG/CORRECT examples.

## Skill Format & Structure

The skill should follow Claude Code's native format:

```
shopify-app-skill/
├── SKILL.md                          # Main entry point — activation rules, quick reference, gotchas
├── shopify-app-skill.md              # Source learnings (existing file, used as reference during build)
├── roadmap.md                        # This file
├── references/
│   ├── react-router-patterns.md      # File-based routing, loaders, actions, fetchers, revalidation
│   ├── dynamodb-patterns.md          # Single-table design, keys module, queries, transactions, TTL
│   ├── shopify-api-patterns.md       # GraphQL API, customer CRUD, metafields, error handling
│   ├── billing-patterns.md           # Full billing flow, isDevelopmentStore, plan gating, trial info
│   ├── app-proxy-patterns.md         # HMAC verification, CSS inlining, POST-redirect, constraints
│   ├── webhook-patterns.md           # Handlers, GDPR mandatory webhooks, uninstall cleanup, reinstall
│   ├── lambda-architecture.md        # Cold start lazy-init, SQS workers, partial batch failure, config
│   ├── cdk-infrastructure.md         # Stacks, CloudFront CSRF fix, security headers, SQS, monitoring
│   ├── polaris-ui-patterns.md        # Navigation, toast, ClientOnly, selectors, testing
│   ├── email-patterns.md             # SQS queuing, suppression list, Resend webhooks
│   ├── security-patterns.md          # Multi-tenancy scoping, CORS, S3 presigned URLs, no X-Frame-Options
│   ├── testing-patterns.md           # Playwright embedded app testing, auth setup, FrameLocator, selectors
│   ├── local-dev-patterns.md         # Docker Compose, DynamoDB Local, LocalStack, startup sequence
│   └── production-deployment.md      # Full zero-to-production deployment guide, AWS setup, DNS, secrets
└── scripts/                          # Optional helper scripts
    └── validate-skill.sh             # Checks SKILL.md structure and references
```

## Phase 1: Create SKILL.md (Core Entry Point)

### Goal
Create the main `SKILL.md` file that Claude Code loads when the skill activates. This is the most important file — it must be concise enough to fit in context but comprehensive enough to prevent the top 10 most common mistakes.

### Tasks

- [ ] **Write YAML frontmatter** with activation triggers
  - Triggers: "shopify app", "embedded app", "polaris", "shopify remix", "react router shopify", "dynamodb shopify", "app proxy", "shopify billing", "shopify webhook", "CDK shopify"
  - Description: Production patterns for embedded Shopify apps with React Router v7, DynamoDB, Lambda, CDK
  
- [ ] **Write the CRITICAL GOTCHAS section** (top of SKILL.md, read first)
  - Extract all 10 gotchas from `shopify-app-skill.md` into concise WRONG/CORRECT code blocks
  - These are the highest-value patterns — each one prevents hours of debugging
  - Format: brief explanation → WRONG code block → CORRECT code block → one-line rule
  
- [ ] **Write the Quick Reference section**
  - `shopifyApp()` configuration skeleton (just the essential fields)
  - File-based routing naming conventions table
  - Layout route pattern (`app.tsx`) with billing sync and error boundary
  - `shouldRevalidate` pattern for heavy layout loaders
  - ClientOnly wrapper component
  
- [ ] **Write the "When to consult references" section**
  - Map common tasks to reference files: "Building a form?" → `references/app-proxy-patterns.md`
  - Keep this as a simple lookup table

### Success Criteria
- SKILL.md is under 4000 tokens (stays within context budget)
- All 10 critical gotchas are present with code examples
- Claude Code can scaffold a new Shopify app route correctly after reading only SKILL.md
- No duplication with reference files — SKILL.md links to them for deep dives

---

## Phase 2: Create Core Reference Files

### Goal
Extract detailed patterns from `shopify-app-skill.md` into focused reference files. Each file should be self-contained enough to solve a specific class of problems.

### Tasks

- [ ] **`references/react-router-patterns.md`**
  - File-based routing conventions (app.*, proxy.*, api.*, webhooks.*)
  - Loader/action patterns with proper error handling
  - `useFetcher` vs `useActionData` (with the gotcha)
  - `useState` sync with loader data (with the gotcha)
  - `shouldRevalidate` for layout loaders
  - Parent + child parallel loader race condition

- [ ] **`references/dynamodb-patterns.md`**
  - Full key structure table (Session, Shop, Form, Application, Event, etc.)
  - Keys module pattern (centralized key generation)
  - `begins_with` entity queries
  - Atomic transactions with find-or-create
  - Batch deletion (max 25 items)
  - TTL conventions table
  - DynamoDB client setup with local endpoint support
  - Session storage implementation (SessionStorage interface)

- [ ] **`references/shopify-api-patterns.md`**
  - Always check both `errors` and `userErrors`
  - GID extraction (`gid.split('/').pop()`)
  - Phone E.164 normalization
  - Metafield definitions (handle `TAKEN` error)
  - Customer create pattern (check exists → update or create)
  - Dual metafield namespace convention (custom + app namespace)

- [ ] **`references/billing-patterns.md`**
  - Full billing flow diagram (text)
  - `billing.request()` throws on success — let it propagate
  - `isDevelopmentStore()` detection via GraphQL
  - Trial info extraction from `billing.check()`
  - Plan-gating pattern with PLAN_LIMITS config
  - Plus dev stores can't approve test charges (workaround: Basic dev store)
  - Custom apps cannot use Billing API (must be Public/Unlisted)
  - `charge_id` redirect pattern to avoid parallel loader race

- [ ] **`references/app-proxy-patterns.md`**
  - Constraints table (GET only, no external CSS/JS, no Tailwind ?inline, no hydration)
  - HMAC verification with `timingSafeEqual`
  - CSS `?inline` embedding pattern
  - Form POST → redirect pattern (success: `?submitted=true`, error: `?error=validation&stateId=xxx`)
  - Hand-crafted proxy CSS guidance

- [ ] **`references/webhook-patterns.md`**
  - Webhook handler pattern (authenticate.webhook)
  - Mandatory GDPR webhooks (3 required endpoints with S3 cleanup)
  - Uninstall cleanup with batch delete
  - Reinstall detection (clear uninstalledAt marker)

### Success Criteria
- Each reference file is focused on one domain (no cross-cutting concerns)
- Every code example is copy-pasteable with minimal modification
- WRONG/CORRECT patterns are used wherever there's a common mistake

---

## Phase 3: Create Infrastructure & Operations Reference Files

### Goal
Cover the deployment, infrastructure, and operational patterns that no existing Shopify skill addresses.

### Tasks

- [ ] **`references/lambda-architecture.md`**
  - Cold start lazy-init pattern (cached handler, initConfig)
  - `initConfig()` for Secrets Manager + SSM Parameter Store
  - SQS workers with partial batch failure (`ReportBatchItemFailures`)
  - ESM Lambda build with createRequire banner

- [ ] **`references/cdk-infrastructure.md`**
  - No-VPC serverless architecture resource table
  - CloudFront CSRF fix (x-forwarded-host custom header)
  - No X-Frame-Options for Shopify apps (with explanation)
  - ACM certs must be in us-east-1 for CloudFront
  - BillingStack in us-east-1 (AWS Budget/EstimatedCharges)
  - OIDC CI/CD pattern (GitHub Actions, no stored credentials)
  - Monitoring alarms table (5xx, latency, DLQ, throttles, cost)
  - SQS worker configuration (email: batch 10/60s/3 retries, export: batch 1/5min/2 retries)

- [ ] **`references/email-patterns.md`**
  - Always queue via SQS (never inline)
  - Email suppression list (bounces + complaints)
  - Resend webhook for bounces/complaints (Svix verification)

- [ ] **`references/security-patterns.md`**
  - Multi-tenancy scoping rule (every query scoped to authenticated shop)
  - CORS for submission endpoint (allowed origins pattern)
  - S3 presigned URLs with short TTL
  - No X-Frame-Options for embedded apps
  - Audit logging (fire-and-forget pattern)

- [ ] **`references/testing-patterns.md`**
  - Playwright FrameLocator pattern for embedded apps
  - Auth setup with `--no-deps`
  - Polaris-specific selectors (text fields, buttons, back nav, checkboxes)
  - Toast notification testing
  - Test idempotency patterns
  - Three-tier testing strategy (Vitest unit/integration, mock-bridge CI, Playwright local)

- [ ] **`references/local-dev-patterns.md`**
  - Docker Compose config (DynamoDB Local + LocalStack + DynamoDB Admin)
  - Startup sequence (docker → setup → shopify app dev)
  - DynamoDB Local direct access commands
  - `shopify app dev --reset` for cached store association
  - Vite HMR + tunnel issues workaround

### Success Criteria
- A developer can set up a complete local dev environment following only local-dev-patterns.md
- CDK patterns are complete enough to deploy a working staging environment
- Monitoring section covers the minimum viable alerting for a production app

---

## Phase 3.5: Production Deployment & Operations Guide

### Goal
Document the complete journey from zero to a running production app — the operational knowledge that no existing Shopify skill covers. This fills the gap between "I have CDK code" and "my app is live in production."

### Background
This phase was born from a real Phase 8.5 production deployment of B2B Onboard, where we created a new AWS account from scratch and hit undocumented issues (Lambda reserved concurrency limits on new accounts, CDK bootstrap requiring app context, Resend webhook chicken-and-egg, Plus dev stores rejecting test charges, etc.).

### Tasks

- [x] **`references/production-deployment.md`** — comprehensive zero-to-production guide covering:
  - AWS account setup (standalone account for Free Tier, billing alerts, root MFA, IAM admin user, CLI profile)
  - ACM certificate request in us-east-1 (CloudFront requirement) with DNS validation
  - CDK configuration (`cdk.json` environment config with account, region, domain, cert ARN, notification email)
  - Secrets Manager setup (4 secrets per environment: shopify, recaptcha, resend, ga4; naming convention; GA4 is optional)
  - Shopify app creation in Partners Dashboard (app URL, redirect URL, scopes, webhooks, app proxy, compliance webhooks)
  - reCAPTCHA setup (v2 checkbox, production domain)
  - Resend email setup (per-environment API key, webhook endpoint configured post-deploy, Svix signing secret)
  - CDK bootstrap in both regions (app region + us-east-1 for BillingStack)
  - Build & deploy sequence (stack ordering, BillingStack deploys separately to us-east-1)
  - DNS configuration (CNAME → CloudFront distribution domain, verification with dig + curl)
  - Post-deploy tasks (SNS email confirmation, Resend webhook + secret update, Lambda concurrency quota increase)
  - GitHub Actions CI/CD (OIDC provider, IAM role, production environment with required reviewers)
  - Staging vs production strategy (separate accounts, identical CDK code with `-c env=`, separate Shopify apps, separate secrets)
  - Common gotchas with explicit symptoms and fixes:
    - Lambda reserved concurrency exceeds new account limit (10 concurrent executions default)
    - CDK app entry requires `-c env=` even for bootstrap
    - Failed stacks need manual CloudFormation console delete before redeploy
    - BillingStack must deploy to us-east-1
    - Resend webhook signing secret chicken-and-egg
    - Plus dev stores can't approve test charges (use Basic dev store)
    - CloudFront CSRF from missing x-forwarded-host header

### Success Criteria
- A developer can go from zero AWS account to a live production Shopify app following only this guide
- Every step includes the exact CLI commands and expected output
- All gotchas encountered during real deployments are documented with symptoms and fixes
- The guide works for any Shopify embedded app on this stack, not just B2B Onboard (domain/app names are parameterized)

---

## Phase 4: Incorporate Best Practices from Existing Plugins

### Goal
Cherry-pick the strongest patterns from the Shopify Dev Toolkit and other community plugins, adapting them to our serverless stack.

### What to Incorporate

From **Saroj Punde's Shopify Dev Toolkit**:
- [ ] **Polaris design tokens** — exact gap scales, background tokens, border tokens, responsive breakpoints (≥577px small, ≥769px medium, ≥1025px large)
- [ ] **Polaris composition templates** — index table pages, settings pages, dashboard layouts using `<s-page>`, `<s-section>`, `<s-grid>`, `<s-box>`, `<s-stack>`, `<s-text>`, `<s-badge>`, `<s-card>`
- [ ] **SSR hydration rule** — "NEVER use inline event handlers — they cause hydration mismatches in SSR apps"
- [ ] **Orchestrator pattern** — decompose full-stack features into database → API → UI layer tasks

From **Shopify's Official Dev MCP Server** (`shopify.dev/docs/apps/build/devmcp`):
- [ ] **Note in SKILL.md** that the official Shopify Dev MCP should be used alongside this skill for documentation search, GraphQL schema exploration, and Liquid validation
- [ ] Add MCP server config snippet for `claude_desktop_config.json`

From **davila7/claude-code-templates**:
- [ ] **Shopify CLI workflow patterns** — app init, app dev, app deploy
- [ ] **Extension patterns** — note that checkout extensions and Shopify Functions exist but are out of scope for this skill (link to official docs)

### What NOT to Incorporate
- Prisma/PostgreSQL patterns (we use DynamoDB)
- Liquid theme development (out of scope — this skill is for embedded apps)
- Composio MCP integration (different paradigm)
- Hydrogen/headless patterns (out of scope for now)

### Success Criteria
- Polaris patterns reference exact token values, not vague guidance
- The skill explicitly states what's in scope vs out of scope
- MCP server recommendation is present but doesn't create a dependency

---

## Phase 5: Write Project Structure & Conventions Reference

### Goal
Document the canonical project structure so Claude Code generates files in the right places with the right naming conventions.

### Tasks

- [ ] **Add project structure section to SKILL.md** (abbreviated) and full version in a reference file
  - Directory layout (app/routes, app/services, app/lib, app/lambda-workers, infra/, tests/, etc.)
  - Service file conventions (*.server.ts, shopDomain as first param, keys module, mappers)
  - Environment variables reference table
  - Shopify App TOML config template

### Success Criteria
- Claude Code places new files in the correct directories
- New service functions follow the established pattern (shopDomain scoping, keys module, error handling)

---

## Phase 6: Validation & Refinement

### Goal
Test the skill against real development tasks and refine based on failures.

### Tasks

- [x] **Test: Scaffold a new route** — ask Claude Code to create a new settings page with loader, action, and Polaris UI. Verify it uses `useNavigate()` instead of `url` prop, handles `useFetcher` correctly, and scopes DB queries by shop.
- [x] **Test: Add a webhook handler** — ask Claude Code to create a new webhook handler. Verify it uses `authenticate.webhook`, returns 200, and follows the pattern.
- [x] **Test: Add billing plan** — ask Claude Code to add a new billing tier. Verify it updates PLAN_LIMITS, uses `isDevelopmentStore()`, and handles the `charge_id` redirect.
- [x] **Test: Create CDK stack** — ask Claude Code to add a new SQS queue with DLQ and Lambda worker. Verify it follows the established patterns.
- [x] **Test: Fix a bug** — describe a symptom (e.g., "banner doesn't show after save") and verify Claude Code identifies the `useFetcher`/`useActionData` confusion.
- [x] **Refine SKILL.md** based on test failures — if Claude Code makes a mistake, add the correction to the appropriate reference file or promote it to a gotcha in SKILL.md.

### Success Criteria
- All 5 test scenarios produce correct code on first attempt
- No critical gotchas are missed during generation
- Skill stays within reasonable token budget (SKILL.md < 4000 tokens, each reference < 3000 tokens)

---

## Phase 7: Publish & Maintain

### Goal
Make the skill installable and keep it current as Shopify evolves.

### Tasks

- [x] **Add `.claude-plugin/marketplace.json`** manifest for plugin registry listing
- [x] **Add README.md** with installation instructions, scope description, and acknowledgments
- [x] **Add LICENSE** (MIT)
- [ ] **Publish to GitHub** and register on plugin directories (buildwithclaude.com, Smithery, MCP Market)
- [x] **Set up update cadence** — review after each Shopify API version release (quarterly) and after each new app built

### Ongoing Maintenance
- Each new app built generates new learnings → update relevant reference files
- Shopify API version bumps may change GraphQL patterns → update shopify-api-patterns.md
- React Router major versions → update react-router-patterns.md
- CDK/AWS changes → update cdk-infrastructure.md and lambda-architecture.md

---

## Key Design Decisions

### Single Skill vs Multi-Plugin
**Decision: Single skill with reference files** (not 16 separate plugins like the Shopify Dev Toolkit).

Rationale: Our patterns are tightly coupled — billing affects loaders, DynamoDB patterns affect webhooks, CDK affects Lambda architecture. Splitting into separate plugins creates coordination overhead and risks inconsistent advice. A single skill with modular reference files gives Claude Code the full picture while keeping SKILL.md lean.

### DynamoDB-First, Not Database-Agnostic
**Decision: Opinionated DynamoDB patterns only.**

Rationale: DynamoDB single-table design has fundamentally different patterns from relational databases. Teaching both would dilute the skill. Developers using Prisma/PostgreSQL can use existing plugins. Our skill targets the cost-optimized serverless stack.

### Gotchas-First Structure
**Decision: SKILL.md leads with the top 10 gotchas before anything else.**

Rationale: The highest value of this skill is preventing mistakes that cost hours to debug. Claude Code should internalize these constraints before generating any code. Reference files provide depth; SKILL.md provides guardrails.

### Explicit WRONG/CORRECT Examples
**Decision: Every pattern that has a common mistake includes both WRONG and CORRECT code.**

Rationale: LLMs learn patterns from examples. Showing only the correct way leaves ambiguity about what NOT to do. The WRONG example with a clear "// WRONG" comment creates a strong negative signal that prevents the exact mistake.

### Out-of-Scope Boundaries
The following are explicitly out of scope for this skill:
- Liquid theme development (use Saroj Punde's theme plugins)
- Hydrogen/headless commerce
- Checkout UI Extensions
- Shopify Functions
- POS extensions
- Prisma/PostgreSQL database patterns

These boundaries prevent scope creep and keep the skill focused on what it does best: embedded app development with serverless AWS infrastructure.
