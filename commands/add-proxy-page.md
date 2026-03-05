# Add App Proxy Page

Scaffold a new App Proxy page with HMAC verification, inline CSS, and server-rendered HTML.

## Arguments

`$ARGUMENTS` = page description (e.g., "application form for job applicants", "order status lookup")

## Instructions

1. Parse the page purpose from `$ARGUMENTS`. If empty, ask the user what the proxy page should display.
2. Read `.claude/skills/shopify-app/references/app-proxy-patterns.md` for constraints, HMAC verification, and CSS inlining patterns.
3. Read `.claude/skills/shopify-app/SKILL.md` gotcha #6 (App Proxy: GET only, no external CSS/JS).
4. Determine the route filename:
   - If this is a new proxy layout: `app/routes/proxy.tsx` (layout) + `app/routes/proxy.<page>.tsx`
   - If extending existing proxy: `app/routes/proxy.<page>.tsx`
5. Review proxy constraints before writing code:
   - **GET only** — the proxy only forwards GET requests. POST submissions must target the direct app URL (`/api/*` route).
   - **No external CSS/JS** — all CSS must be inline `<style>` tags. No `<link>` or `<script src>`.
   - **No Tailwind `?inline`** — Tailwind 4's Vite plugin doesn't process `?inline` imports.
   - **No client-side hydration** — React Router JS bundles don't load. Server-render only.
6. Create the route file with:
   - `loader` that calls `verifyProxySignature(searchParams)` for HMAC verification
   - Server-rendered HTML with all CSS inline in `<style>` tags
   - Proper `Content-Type: text/html` response (or use Shopify's Liquid layout via `application_liquid` content type)
   - Data fetched from service functions, scoped by the shop from the HMAC-verified params
7. If the page needs form submissions:
   - Create a separate `app/routes/api.<form-name>.tsx` action route for POST handling
   - The proxy page form's `action` attribute must point to the direct app URL, not the proxy URL
   - Read `.claude/skills/shopify-app/references/react-router-patterns.md` for API route patterns
8. Create or update service functions as needed, always with `shopDomain` as first parameter.
9. Remind the user to:
    - Configure the App Proxy in the Shopify Partner Dashboard (URL prefix + subpath)
    - Test HMAC verification with a real storefront request
    - Verify no external CSS/JS references leaked into the HTML
