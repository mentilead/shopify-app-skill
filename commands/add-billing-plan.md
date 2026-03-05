# Add Billing Plan

Add a new subscription plan with trial support, plan gating, and pricing UI.

## Arguments

`$ARGUMENTS` = plan name and optional details (e.g., "pro $29/month with 14-day trial", "enterprise")

## Instructions

1. Parse the plan name, price, and trial days from `$ARGUMENTS`. If missing, ask the user for plan name, monthly price, and trial length.
2. Read `.claude/skills/shopify-app/references/billing-patterns.md` for the full billing flow, `billing.request()` throw behavior, and `isDevelopmentStore` pattern.
3. Read `.claude/skills/shopify-app/SKILL.md` gotchas #7 (Plus dev stores can't approve test charges) and #8 (Custom apps cannot use Billing API).
4. Add the plan definition to `app/shopify.server.ts` in the `billing` config:
   - Plan name, amount, currencyCode, interval
   - `trialDays` if trial was specified
5. Create or update the billing service function in `app/services/billing.server.ts`:
   - `syncBillingToDb(shopDomain, admin)` — checks active subscription and writes to DynamoDB
   - `loadShopBilling(shopDomain)` — reads current plan from DynamoDB
   - Feature gating helper that maps plans to feature sets
6. Update the layout loader in `app/routes/app.tsx` to sync billing on page load using the `charge_id` redirect pattern from the skill (gotcha #5).
7. Create or update the pricing page at `app/routes/app.pricing.tsx`:
   - Show plan cards with features and pricing
   - Use `useFetcher` for the upgrade action (not `useActionData` — gotcha #3)
   - Handle `isDevelopmentStore` for test charges
8. If the plan gates specific features, add the gating check to relevant loaders/actions.
9. Remind the user to:
    - Test with a non-Plus Basic dev store (gotcha #7)
    - Verify the app is Public or Unlisted distribution (gotcha #8)
    - Test the full flow: trial start → approval → redirect → plan display
