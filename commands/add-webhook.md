# Add Webhook Handler

Scaffold a new Shopify webhook handler with proper authentication, idempotency, and GDPR compliance.

## Arguments

`$ARGUMENTS` = the Shopify webhook topic (e.g., "orders/create", "products/update", "app/uninstalled")

## Instructions

1. Parse the webhook topic from `$ARGUMENTS`. If empty, ask the user which webhook topic to handle.
2. Read `.claude/skills/shopify-app/references/webhook-patterns.md` for the handler pattern and GDPR requirements.
3. Read `.claude/skills/shopify-app/references/react-router-patterns.md` for file-naming conventions (webhooks use the `webhooks.` prefix).
4. Determine the route filename from the topic:
   - `orders/create` → `app/routes/webhooks.app.orders-create.tsx`
   - `products/update` → `app/routes/webhooks.app.products-update.tsx`
   - Replace `/` with `.` in the prefix, `-` in the specific topic part.
5. Create the webhook handler route file with:
   - `authenticate.webhook(request)` for verification
   - Structured logging with `shop`, `topic`, and relevant payload fields
   - Idempotency check (query for existing record before processing)
   - Always return `new Response(null, { status: 200 })`
6. Register the webhook in `app/shopify.server.ts` by adding the topic to the `webhooks` configuration if not already present.
7. If the webhook needs to store data, create or update the relevant service function in `app/services/*.server.ts` with `shopDomain` as the first parameter.
8. If the webhook needs new DynamoDB keys, read `.claude/skills/shopify-app/references/dynamodb-patterns.md` and update `app/services/dynamodb/keys.ts`.
9. Create a unit test in `tests/` for the service function logic (not the route handler itself).
10. Remind the user to:
    - Run `shopify app dev` to register the webhook with Shopify
    - Test delivery via Shopify CLI: `shopify app webhook trigger --topic <TOPIC> --address <URL>`
