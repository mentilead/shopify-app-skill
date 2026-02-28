# Contributing to Shopify App Skill

Thanks for your interest in contributing! This skill helps developers build production-grade embedded Shopify apps with Claude Code.

## Guidelines

### Keep files lean

Every file has a token budget (see README). Patterns should be concise and scannable — no filler text.

| File | Target |
|------|--------|
| SKILL.md | < 4,000 tokens |
| Each reference file | < 3,000 tokens |

### Use WRONG/CORRECT format

Document gotchas and patterns using the WRONG/CORRECT format so Claude Code can learn from concrete examples:

```markdown
### WRONG
\`\`\`typescript
// code that looks right but fails
\`\`\`

### CORRECT
\`\`\`typescript
// code that actually works, with a brief comment explaining why
\`\`\`
```

### Battle-tested only

Every pattern must come from real production experience. Do not add theoretical patterns or untested suggestions. If you haven't hit the issue in a real Shopify app, it doesn't belong here.

### Run validation before submitting

```bash
bash scripts/validate-skill.sh
```

This checks file structure, token budgets, and required sections. Your PR must pass with 0 errors.

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b add-pattern-xyz`)
3. Make your changes following the guidelines above
4. Run `bash scripts/validate-skill.sh` and confirm 0 errors
5. Commit with a clear message describing the pattern added or changed
6. Open a pull request against `main`

## What to Contribute

- New gotchas you've hit in production Shopify apps
- Corrections or improvements to existing patterns
- New reference files for uncovered areas of the stack (open an issue first)
- Typo fixes and clarifications

## Questions?

Open an issue or start a discussion in the repository.
