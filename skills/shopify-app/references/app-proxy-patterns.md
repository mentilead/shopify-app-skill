# App Proxy Patterns

## Constraints

| Constraint | Detail |
|-----------|--------|
| **GET only** | Proxy only forwards GET requests. POST must go directly to the app URL. |
| **No external CSS/JS** | `<link>` and `<script src>` resolve against the storefront domain and 404. |
| **No Tailwind `?inline`** | Tailwind 4's Vite plugin doesn't process `@tailwind` for `?inline` imports. |
| **No client-side hydration** | React Router JS bundles don't load through the proxy. |

---

## HMAC Verification with `timingSafeEqual`

Every proxy request includes a signature that must be verified:

```typescript
// app/utils/proxy-auth.ts
import crypto from 'crypto';

export function verifyProxySignature(
  searchParams: URLSearchParams
): { valid: boolean; shop: string | null } {
  const signature = searchParams.get('signature');
  if (!signature) return { valid: false, shop: null };

  const secret = process.env.SHOPIFY_API_SECRET;
  if (!secret) return { valid: false, shop: null };

  // Build message: sort all params except signature, concatenate as key=value
  const params: string[] = [];
  for (const [key, value] of searchParams.entries()) {
    if (key !== 'signature') {
      params.push(`${key}=${value}`);
    }
  }
  params.sort();
  const message = params.join('');

  const computed = crypto
    .createHmac('sha256', secret)
    .update(message)
    .digest('hex');

  try {
    const valid = crypto.timingSafeEqual(
      Buffer.from(computed, 'hex'),
      Buffer.from(signature, 'hex'),
    );
    return { valid, shop: valid ? searchParams.get('shop') : null };
  } catch {
    return { valid: false, shop: null };
  }
}
```

---

## CSS `?inline` Embedding Pattern

Since external stylesheets fail through the proxy, inline CSS using Vite's `?inline` suffix:

```tsx
// Proxy layout — inline CSS since external stylesheets fail through proxy
import proxyStyles from '../styles/proxy.css?inline';

export default function ProxyLayout() {
  return (
    <>
      <style dangerouslySetInnerHTML={{ __html: proxyStyles }} />
      <div className="min-h-screen bg-slate-50">
        <Outlet />
      </div>
    </>
  );
}
```

**Important:** Write hand-crafted utility classes in a dedicated `proxy.css` file. Don't rely on Tailwind processing — Tailwind 4's Vite plugin doesn't process `@tailwind` directives for `?inline` imports.

---

## Form POST → Redirect Pattern

Since App Proxy only forwards GET, form submissions POST directly to the app URL:

```html
<!-- In the proxy-rendered form -->
<form method="POST" action="https://your-app.com/api/submit-application">
  <input type="hidden" name="shop" value="{{ shop }}" />
  <!-- form fields -->
  <button type="submit">Submit</button>
</form>
```

The API endpoint processes the form, then redirects back to the proxy URL:

- **Success:** `?submitted=true`
- **Validation error:** `?error=validation&stateId=<id>` (state stored in DynamoDB with 1-hour TTL for retrieval)

```typescript
// api.submit-application.tsx
export const action = async ({ request }: ActionFunctionArgs) => {
  const formData = await request.formData();
  const shop = formData.get('shop') as string;

  try {
    await processApplication(shop, formData);
    return redirect(`https://${shop}/apps/wholesale-register?submitted=true`);
  } catch (error) {
    if (error instanceof ValidationError) {
      const stateId = await saveFormState(shop, formData);
      return redirect(
        `https://${shop}/apps/wholesale-register?error=validation&stateId=${stateId}`
      );
    }
    throw error;
  }
};
```

---

## Proxy CSS Guidance

- Write utility classes by hand in `app/styles/proxy.css`
- Use simple selectors: `.form-input`, `.form-label`, `.submit-btn`
- Keep styles minimal — the proxy page renders inside the storefront theme
- Test with the actual storefront theme to check for CSS conflicts
- Consider using `!important` sparingly for critical overrides

```css
/* app/styles/proxy.css — hand-crafted, no Tailwind */
.proxy-container {
  max-width: 640px;
  margin: 2rem auto;
  padding: 1.5rem;
}

.form-field {
  margin-bottom: 1rem;
}

.form-label {
  display: block;
  margin-bottom: 0.25rem;
  font-weight: 600;
}

.form-input {
  width: 100%;
  padding: 0.5rem;
  border: 1px solid #ccc;
  border-radius: 4px;
}
```
