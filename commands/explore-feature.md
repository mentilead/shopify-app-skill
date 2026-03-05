# Explore Feature

Run the 8-step feature exploration framework before implementing a new Shopify feature.

## Arguments

`$ARGUMENTS` = description of the feature to explore (e.g., "order webhooks", "Flow connectors", "billing for pro tier")

## Instructions

1. Read the feature exploration framework from `.claude/skills/shopify-app/references/feature-exploration.md`.
2. Parse the feature description from `$ARGUMENTS`. If empty, ask the user what feature they want to explore.
3. Run through each of the 8 steps for the described feature:
   - **Step 1: Shopify Docs Research** — identify hard constraints from Shopify docs
   - **Step 2: Architecture Decision Analysis** — document key decisions and trade-offs
   - **Step 3: Security Hardening Checklist** — review security concerns
   - **Step 4: Code Path Injection Mapping** — trace integration points in existing code
   - **Step 5: Plan Gating Analysis** — determine billing tier access
   - **Step 6: Monitoring & Observability** — define metrics and alarms
   - **Step 7: Testing Strategy by Environment** — plan tests per environment
   - **Step 8: Breaking Change Risk Assessment** — identify non-changeable contracts
4. Use the "When to Use" table at the bottom of the framework to determine which steps are relevant. Skip steps that don't apply and explain why.
5. For each relevant step, fill in the templates and checklists with specifics for the described feature.
6. Cross-reference other skill references as needed (security-patterns.md, billing-patterns.md, testing-patterns.md, cdk-infrastructure.md).
7. Summarize findings and flag any blockers or open questions before implementation begins.
8. After presenting the summary, ask the user: **"Do you want me to update the relevant feature in `roadmap.md`?"** If yes, read `roadmap.md`, find the matching feature section, and update it with the constraints, decisions, and risks discovered during exploration.
