# Polaris UI Patterns

## Navigation (GOTCHA)

Polaris `<Link url="...">` and `<Button url="...">` render plain `<a>` tags. Inside the embedded app iframe, these navigate to the raw app URL, breaking out of the admin iframe.

```tsx
// WRONG — breaks out of iframe
<Button url="/app/pricing">Upgrade</Button>
<Link url="/app/settings">Settings</Link>

// CORRECT — stays in iframe
const navigate = useNavigate();
<Button onClick={() => navigate('/app/pricing')}>Upgrade</Button>

// OK — external URLs are fine with url prop
<Button url="https://admin.shopify.com/store/foo/settings/billing">
  Manage in Shopify
</Button>
```

**Rule:** `url` prop is only safe for external URLs. Use `useNavigate()` for internal routes.

---

## ClientOnly Component

Polaris components access browser APIs that don't exist during SSR. Wrap them to prevent hydration mismatches:

```tsx
// app/components/ClientOnly.tsx
import { useState, useEffect, type ReactNode } from 'react';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

export function ClientOnly({ children, fallback = null }: Props) {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  return mounted ? <>{children}</> : <>{fallback}</>;
}
```

---

## Toast Notifications

```typescript
// In route action, return toast data
return { ok: true, message: 'Settings saved' };

// In component, show Shopify toast
useEffect(() => {
  if (fetcherData?.ok) {
    window.shopify.toast.show(fetcherData.message);
  }
}, [fetcherData]);
```

---

## SSR Hydration Rule

**NEVER use inline event handlers** — they cause hydration mismatches in SSR apps:

```tsx
// WRONG — hydration mismatch
<button onclick="handleClick()">Save</button>

// CORRECT — React event handler
<button onClick={handleClick}>Save</button>
```

Always use React's event system (`onClick`, `onChange`, etc.) via state and handlers.

---

## Polaris Design Tokens

### Responsive Breakpoints

| Breakpoint | Width | Usage |
|-----------|-------|-------|
| `xs` | < 490px | Mobile |
| `sm` | ≥ 490px | Small mobile |
| `md` | ≥ 768px | Tablet |
| `lg` | ≥ 1040px | Desktop |
| `xl` | ≥ 1440px | Wide desktop |

### Gap Scale

| Token | Value | Use for |
|-------|-------|---------|
| `100` | 4px | Tight spacing |
| `200` | 8px | Compact elements |
| `300` | 12px | Default component spacing |
| `400` | 16px | Section spacing |
| `500` | 20px | Card spacing |

### Background Tokens

| Token | Usage |
|-------|-------|
| `bg-surface` | Default card/surface background |
| `bg-surface-secondary` | Secondary surfaces |
| `bg-surface-success` | Success state backgrounds |
| `bg-surface-warning` | Warning state backgrounds |
| `bg-surface-critical` | Error state backgrounds |

---

## Polaris Composition Templates

### Page Layout (`<s-page>`)

```html
<s-page title="Dashboard" subtitle="Overview of your app">
  <s-section>
    <!-- Main content -->
  </s-section>
</s-page>
```

### Section with Grid (`<s-grid>`)

```html
<s-section>
  <s-grid columns="2" gap="400">
    <s-card>
      <s-box padding="400">
        <s-stack gap="200">
          <s-text variant="headingSm">Metric 1</s-text>
          <s-text variant="bodyMd">Value</s-text>
        </s-stack>
      </s-box>
    </s-card>
    <s-card>
      <s-box padding="400">
        <s-stack gap="200">
          <s-text variant="headingSm">Metric 2</s-text>
          <s-text variant="bodyMd">Value</s-text>
        </s-stack>
      </s-box>
    </s-card>
  </s-grid>
</s-section>
```

### Stack Layout (`<s-stack>`)

```html
<s-stack gap="300" align="center">
  <s-text variant="headingMd">Title</s-text>
  <s-badge tone="success">Active</s-badge>
</s-stack>
```

### Box Container (`<s-box>`)

```html
<s-box padding="400" paddingInlineStart="500" background="bg-surface-secondary">
  <!-- Content with custom spacing -->
</s-box>
```

---

## Polaris-Specific Playwright Selectors

```typescript
// Text fields
frame.getByLabel('Company name');

// Buttons
frame.getByRole('button', { name: 'Save' });
frame.getByRole('button', { name: 'Review', exact: true });  // Avoid matching "Review 14 pending"

// Back navigation (backAction renders as button, not link)
frame.getByRole('button', { name: 'Forms' });  // Back to forms list

// Links
frame.getByRole('link', { name: 'View application' });

// Checkboxes
frame.getByRole('checkbox', { name: 'Enable notifications' });

// Select
frame.getByLabel('Country').selectOption('Denmark');
```

See `references/testing-patterns.md` for full Playwright patterns.
