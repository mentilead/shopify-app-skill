# Add Entity

Design and scaffold a new DynamoDB entity with single-table key design, service functions, and tenant scoping.

## Arguments

`$ARGUMENTS` = entity name and optional description (e.g., "Notification user notifications for form events", "ExportJob")

## Instructions

1. Parse the entity name from `$ARGUMENTS`. If empty, ask the user what entity to create and its purpose.
2. Read `.claude/skills/shopify-app/references/dynamodb-patterns.md` for key structure, the keys module pattern, and mapper conventions.
3. Read `.claude/skills/shopify-app/references/security-patterns.md` for multi-tenancy scoping requirements.
4. Design the key structure following existing patterns:
   - PK must start with `SHOP#<domain>` for tenant isolation (unless it's a cross-shop entity like Session)
   - SK must use the `ENTITY#<id>` pattern
   - Add GSI1PK/GSI1SK only if cross-partition queries are needed
   - If the entity has a time-based sort need, include a timestamp in the SK or GSI1SK
5. Add key builder functions to `app/services/dynamodb/keys.ts`:
   - `entityName(domain, id)` — returns PK, SK, and optional GSI keys
   - `entityNameByShop(domain)` — returns PK and SKPrefix for queries
6. Create a mapper in `app/services/dynamodb/mappers.ts` (or a new mapper file):
   - `toEntityName(item: Record<string, any>): EntityType` — DynamoDB item to typed object
   - `fromEntityName(entity: EntityType): Record<string, any>` — typed object to DynamoDB item
7. Create service functions in `app/services/<entity-name>.server.ts`:
   - `create<Entity>(shopDomain, data)` — PutItem with condition to prevent overwrites
   - `get<Entity>(shopDomain, id)` — GetItem
   - `query<Entities>ByShop(shopDomain)` — Query with SKPrefix
   - `update<Entity>(shopDomain, id, updates)` — UpdateItem
   - `delete<Entity>(shopDomain, id)` — DeleteItem
   - Every function takes `shopDomain` as the first parameter
8. Create unit tests for the key builders and service functions.
9. Show the user the key design table and ask them to confirm before generating the code.
