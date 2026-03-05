# Feature Exploration

Use this framework when planning or analyzing a new Shopify feature — not during active implementation. Run through each step sequentially before writing code.

---

## 1. Shopify Docs Research

Before designing anything, extract hard constraints from Shopify documentation.

### Constraint Checklist

- [ ] **Payload limits** — max request/response sizes, field length limits
- [ ] **Timeouts** — API response deadlines, webhook delivery windows
- [ ] **Naming conventions** — handle formats, key prefixes, namespace rules
- [ ] **Field restrictions** — reserved field names, type constraints, immutable fields
- [ ] **Handle constraints** — uniqueness scope, character restrictions, max length
- [ ] **Breaking change rules** — versioned vs unversioned behavior, deprecation timelines
- [ ] **Required scopes** — OAuth scopes needed, scope change implications for existing installs
- [ ] **Auth patterns** — online vs offline tokens, which endpoints need which
- [ ] **Rate limits** — bucket sizes, restore rates, leaky bucket vs throttle
- [ ] **API version lifecycle** — minimum supported version, sunset dates

### Example

```typescript
// WRONG — jumping to implementation without checking docs
// "I'll just create a metafield with any key format"
await admin.graphql(`mutation { metafieldsSet(metafields: [{
  namespace: "My App Settings",  // spaces not allowed
  key: "config.main",            // dots not allowed
  type: "json",
  value: "${hugePayload}",       // 65,536 character limit
}]) { ... } }`);

// CORRECT — extract constraints first, then design within them
// Docs say: namespace/key must be 3-255 chars, [a-zA-Z0-9_-] only
// Value limit: 65,536 chars for json type
// Reserved namespaces: global, app--{id} (auto-created)
await admin.graphql(`mutation { metafieldsSet(metafields: [{
  namespace: "app_settings",
  key: "main_config",
  type: "json",
  value: "${validatedPayload}",
}]) { ... } }`);
```

---

## 2. Architecture Decision Analysis

Document key design decisions with trade-offs before committing to an approach.

### Decision Record Template

| Decision | Options | Chosen | Rationale |
|----------|---------|--------|-----------|
| Data flow | Sync API / Async webhook / Polling | — | — |
| Storage | DynamoDB item / S3 object / Metafield | — | — |
| Processing | Inline in loader / SQS worker / Step Function | — | — |
| Trigger | User action / Webhook / Cron | — | — |

### Shopify-Specific Trade-off Factors

- **Webhook vs polling** — webhooks are near-real-time but can be missed; polling is reliable but rate-limited
- **Metafield vs DynamoDB** — metafields are Shopify-native (accessible in Liquid) but slow for queries; DynamoDB is fast but requires sync
- **Online vs offline token** — online tokens expire (for user-scoped actions); offline tokens persist (for background jobs)
- **App Bridge action vs direct API** — App Bridge gives native UX but limits control; direct API is flexible but breaks embedded feel
- **Extension vs embedded route** — extensions run in Shopify context (limited); routes have full control but live in iframe

---

## 3. Security Hardening Checklist

Required for features that receive external input or send data to external services. Cross-reference `references/security-patterns.md` for implementation details.

- [ ] **Tenant isolation** — every query scoped by `shopDomain`; no cross-tenant data leakage
- [ ] **PII exposure** — identify personal data fields; encrypt at rest; mask in logs
- [ ] **Input sanitization** — validate all user/webhook input; enforce type, length, format
- [ ] **Idempotency** — webhook handlers and API mutations must be safe to retry
- [ ] **Rate limiting** — protect custom endpoints from abuse (especially public API routes)
- [ ] **Audit trail** — log who changed what and when for sensitive operations
- [ ] **Error info leakage** — never expose stack traces, internal IDs, or table names to clients
- [ ] **HMAC verification** — validate Shopify signatures on webhooks and proxy requests
- [ ] **CSRF protection** — embedded app routes use Shopify session tokens; proxy POST routes need custom protection

---

## 4. Code Path Injection Mapping

Trace exactly where new code integrates into existing functionality before writing it.

### Integration Point Template

| Integration Point | File | Function/Export | How It Connects |
|-------------------|------|----------------|-----------------|
| Route entry | `app/routes/app.*.tsx` | `loader` / `action` | New route or extends existing |
| Service layer | `app/services/*.server.ts` | Named exports | New service or adds functions |
| DynamoDB keys | `app/services/dynamodb/keys.ts` | Key builders | New PK/SK patterns |
| Shopify config | `app/shopify.server.ts` | `shopifyApp()` | New scopes, webhooks, billing |
| CDK infra | `infra/*.ts` | Stack resources | New Lambda, SQS, S3, etc. |
| Extensions | `extensions/*/` | TOML + blocks | New extension points |
| Layout nav | `app/routes/app.tsx` | `<s-app-nav>` | New navigation items |

### Process

1. Read existing files at each integration point
2. Document current function signatures and exports
3. Identify where new code hooks in (new export, new route, config change)
4. Flag any shared code that needs modification (higher risk than new code)

---

## 5. Plan Gating Analysis

Determine which billing tiers get access to the new feature. Cross-reference `references/billing-patterns.md` for implementation.

### Gating Decision Factors

| Factor | Free Tier | Paid Tier | Notes |
|--------|-----------|-----------|-------|
| **Discoverability** | Show with upgrade prompt | Full access | Lets free users see value |
| **Cost-to-serve** | N/A | Requires compute/storage | SQS workers, S3 storage, API calls |
| **Power feature** | N/A | Full access | Advanced functionality |
| **Table stakes** | Full access | Full access | Expected in all Shopify apps |

### Implementation Pattern

```typescript
// In loader or action:
const { planFeatures } = await loadShopBilling(shopDomain);

if (!planFeatures.includes('feature-name')) {
  // Option A: Return gated state (UI shows upgrade prompt)
  return { gated: true, requiredPlan: 'pro' };

  // Option B: Block with error (for API routes)
  throw new Response('Plan upgrade required', { status: 402 });
}
```

### Questions to Answer

- Is this a free-tier teaser (visible but limited) or paid-only (hidden entirely)?
- Does it have usage limits per tier (e.g., 5 forms free, unlimited paid)?
- Does enabling it increase infrastructure cost per shop?

---

## 6. Monitoring & Observability

Define what to monitor before shipping. Cross-reference `references/cdk-infrastructure.md` for CloudWatch patterns.

### Metrics Template

| Metric | Type | Alarm Threshold | Description |
|--------|------|-----------------|-------------|
| `FeatureName.Invocations` | Count | — | How often the feature is used |
| `FeatureName.Errors` | Count | > 5 in 5min | Feature-specific failures |
| `FeatureName.Duration` | Timer | p99 > 3s | Latency tracking |
| `FeatureName.BusinessEvent` | Count | — | Domain events (e.g., forms submitted) |

### Structured Logging

```typescript
console.log(JSON.stringify({
  level: 'info',
  event: 'feature_name.action_completed',
  shopDomain,
  featureId,
  duration: Date.now() - start,
  metadata: { /* relevant context */ },
}));
```

### Alarm Checklist

- [ ] Error rate alarm with SNS notification
- [ ] Latency alarm (p99) for user-facing paths
- [ ] Dead letter queue alarm for async processing
- [ ] Custom business metric dashboard

---

## 7. Testing Strategy by Environment

Plan tests for each environment's constraints. Cross-reference `references/testing-patterns.md` for implementation.

### Unit Tests (CI — Vitest)

- Service function logic with mocked DynamoDB
- Key generation and mapper functions
- Input validation and edge cases
- **Constraint:** No Shopify API access, no real AWS services

### Manual Testing (Dev Store)

- Full feature flow in embedded app
- Billing integration (use non-Plus Basic dev store)
- Webhook delivery and processing
- App Proxy rendering
- **Constraint:** Requires `shopify app dev` running, dev store installed

### Staging Tests (Deployed)

- End-to-end with real DynamoDB, SQS, S3
- CloudWatch metrics and alarms fire correctly
- Performance under realistic conditions
- **Constraint:** Staging environment must mirror production config

### Test Checklist

- [ ] Happy path unit tests for all service functions
- [ ] Error case unit tests (invalid input, missing data, permission denied)
- [ ] Multi-tenant isolation test (shop A can't see shop B's data)
- [ ] Idempotency test for webhook handlers
- [ ] Manual dev store walkthrough documented

---

## 8. Breaking Change Risk Assessment

Required for features that create public contracts: extension schemas, webhook payloads, metafield keys, proxy URL structures, or API response shapes.

### Identify Non-Changeable Fields

Once shipped, these cannot be renamed or removed without breaking existing installations:

| Contract Type | Non-Changeable | Example |
|--------------|----------------|---------|
| Extension TOML | `handle`, `target` | `handle = "order-summary"` |
| Metafield | `namespace`, `key` | `app_settings.main_config` |
| Webhook payload | Top-level field names | `{ shopDomain, eventType }` |
| Proxy URL | Path structure | `/apps/my-app/forms/:id` |
| DynamoDB keys | PK/SK patterns | `SHOP#domain`, `FORM#id` |

### Forward Compatibility Recommendations

- **Use versioned namespaces** when the schema may evolve: `app_settings_v1`
- **Include a `version` field** in serialized data stored in metafields or S3
- **Design enums as open sets** — consumers should handle unknown values gracefully
- **Prefer additive changes** — add new fields rather than modifying existing ones
- **Document the contract** — if other apps or themes depend on it, it's a public API

### Risk Assessment Template

| Element | Changeable After Ship? | Risk Level | Mitigation |
|---------|----------------------|------------|------------|
| — | Yes / No | Low / Medium / High | — |

---

## When to Use This Framework

| Scenario | Steps to Run |
|----------|-------------|
| New feature from scratch | All 8 steps |
| Adding billing to existing feature | Steps 1, 5, 6 |
| New webhook handler | Steps 1, 3, 4, 7, 8 |
| New App Proxy endpoint | Steps 1, 3, 4, 6, 7 |
| New extension | Steps 1, 4, 7, 8 |
| Security review of existing feature | Steps 3, 6 |
