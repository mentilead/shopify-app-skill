#!/usr/bin/env bash
# Validates the shopify-app-skill structure, content, and cross-references.
set -euo pipefail

ERRORS=0
WARNINGS=0

error() { echo "ERROR: $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo "WARNING: $1"; WARNINGS=$((WARNINGS + 1)); }
ok() { echo "OK: $1"; }

# Determine project root (script is in scripts/)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_DIR="$ROOT/skills/shopify-app"

echo "=== Shopify App Skill Validation ==="
echo ""

# --- 1. Check SKILL.md exists ---
if [[ -f "$SKILL_DIR/SKILL.md" ]]; then
  ok "skills/shopify-app/SKILL.md exists"
else
  error "skills/shopify-app/SKILL.md not found"
fi

# --- 2. Check SKILL.md has frontmatter ---
if head -1 "$SKILL_DIR/SKILL.md" | grep -q '^---$'; then
  ok "SKILL.md has frontmatter"
else
  error "SKILL.md missing YAML frontmatter (should start with ---)"
fi

# --- 3. Check all 14 reference files exist ---
REFERENCES=(
  "react-router-patterns.md"
  "dynamodb-patterns.md"
  "shopify-api-patterns.md"
  "billing-patterns.md"
  "app-proxy-patterns.md"
  "webhook-patterns.md"
  "lambda-architecture.md"
  "cdk-infrastructure.md"
  "polaris-ui-patterns.md"
  "email-patterns.md"
  "security-patterns.md"
  "testing-patterns.md"
  "local-dev-patterns.md"
  "production-deployment.md"
)

MISSING_REFS=0
for ref in "${REFERENCES[@]}"; do
  if [[ -f "$SKILL_DIR/references/$ref" ]]; then
    ok "references/$ref exists"
  else
    error "references/$ref not found"
    MISSING_REFS=$((MISSING_REFS + 1))
  fi
done

# --- 4. Check line counts ---
echo ""
echo "--- Line Counts ---"

SKILL_LINES=$(wc -l < "$SKILL_DIR/SKILL.md")
echo "SKILL.md: $SKILL_LINES lines"
if (( SKILL_LINES > 500 )); then
  warn "SKILL.md exceeds 500 lines ($SKILL_LINES lines)"
else
  ok "SKILL.md within line budget"
fi

for ref in "${REFERENCES[@]}"; do
  if [[ -f "$SKILL_DIR/references/$ref" ]]; then
    LINES=$(wc -l < "$SKILL_DIR/references/$ref")
    echo "references/$ref: $LINES lines"
    if (( LINES > 300 )); then
      warn "references/$ref exceeds 300 lines ($LINES lines)"
    fi
  fi
done

# --- 5. Check all reference links in SKILL.md resolve ---
echo ""
echo "--- Cross-Reference Check ---"

while IFS= read -r link; do
  # Extract path from backtick-wrapped references
  ref_path=$(echo "$link" | sed 's/.*`\(references\/[^`]*\)`.*/\1/')
  if [[ -f "$SKILL_DIR/$ref_path" ]]; then
    ok "Link resolves: $ref_path"
  else
    error "Broken link in SKILL.md: $ref_path"
  fi
done < <(grep -o '`references/[^`]*`' "$SKILL_DIR/SKILL.md" | sort -u)

# --- 6. Check all 10 gotchas are present ---
echo ""
echo "--- Gotcha Check ---"

GOTCHA_COUNT=$(grep -c '^### [0-9]\+\.' "$SKILL_DIR/SKILL.md" || true)
echo "Found $GOTCHA_COUNT gotchas in SKILL.md"
if (( GOTCHA_COUNT >= 10 )); then
  ok "All 10 gotchas present"
else
  error "Expected 10 gotchas, found $GOTCHA_COUNT"
fi

# --- 7. Check for WRONG/CORRECT patterns ---
echo ""
echo "--- WRONG/CORRECT Pattern Check ---"

WRONG_COUNT=$(grep -c 'WRONG' "$SKILL_DIR/SKILL.md" || true)
CORRECT_COUNT=$(grep -c 'CORRECT' "$SKILL_DIR/SKILL.md" || true)
echo "SKILL.md: $WRONG_COUNT WRONG, $CORRECT_COUNT CORRECT patterns"
if (( WRONG_COUNT >= 5 )); then
  ok "Sufficient WRONG/CORRECT patterns in SKILL.md"
else
  warn "Expected at least 5 WRONG patterns in SKILL.md"
fi

# --- 8. Check publishing files ---
echo ""
echo "--- Publishing Files ---"

for file in ".claude-plugin/plugin.json" ".claude-plugin/marketplace.json" "README.md" "LICENSE"; do
  if [[ -f "$ROOT/$file" ]]; then
    ok "$file exists"
  else
    error "$file not found"
  fi
done

# --- Summary ---
echo ""
echo "=== Summary ==="
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"

if (( ERRORS > 0 )); then
  echo "FAILED: Fix $ERRORS error(s) above."
  exit 1
else
  echo "PASSED: All checks passed."
  exit 0
fi
