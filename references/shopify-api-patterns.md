# Shopify API Patterns

## Always Check Both `errors` and `userErrors`

GraphQL responses can fail in two ways:

```typescript
const response = await admin.graphql(MUTATION, { variables: { input } });
const { data, errors } = await response.json();

// 1. Top-level errors (syntax, auth, rate limit)
if (errors?.length) {
  console.error('GraphQL errors:', errors);
  return { success: false, error: errors.map((e) => e.message).join(', ') };
}

// 2. User errors (validation, business logic)
const userErrors = data?.mutationName?.userErrors;
if (userErrors?.length) {
  console.error('User errors:', userErrors);
  return { success: false, error: userErrors.map((e) => e.message).join(', ') };
}
```

```typescript
// WRONG — only checks one error type
if (errors) throw new Error('GraphQL failed');

// CORRECT — always check both
if (errors?.length) return { error: errors[0].message };
if (data?.mutation?.userErrors?.length) return { error: data.mutation.userErrors[0].message };
```

---

## GID Extraction

Shopify returns GraphQL IDs as URIs. Extract the numeric ID:

```typescript
// 'gid://shopify/Customer/12345' → '12345'
const numericId = gid.split('/').pop();
```

---

## Phone E.164 Normalization

Shopify `customerCreate` rejects improperly formatted phone numbers (especially US 555-xxx-xxxx test numbers).

```typescript
function normalizePhone(phone: string | undefined): string | undefined {
  if (!phone) return undefined;
  const cleaned = phone.startsWith('+')
    ? '+' + phone.slice(1).replace(/\D/g, '')
    : phone.replace(/\D/g, '');
  return cleaned || undefined;
}
```

Always normalize before sending to Shopify. Use real-looking numbers for testing (e.g., `+4531587642` for Danish).

---

## Metafield Definitions (Handle `TAKEN` Error)

When creating metafield definitions, the definition may already exist. Filter out the `TAKEN` error code:

```typescript
const { data } = await admin.graphql(CREATE_METAFIELD_DEFINITION, {
  variables: { definition },
});

const userErrors = data?.metafieldDefinitionCreate?.userErrors ?? [];
const realErrors = userErrors.filter((e) => e.code !== 'TAKEN');

if (realErrors.length) {
  console.error('Metafield definition error:', realErrors);
}
```

---

## Customer Create Pattern

```typescript
// 1. Check if customer exists first
const existingResponse = await admin.graphql(
  `{ customers(first: 1, query: "email:${email}") { edges { node { id } } } }`
);

// 2. If exists, add tags via update mutation
// 3. If new, create with all fields
const createResponse = await admin.graphql(CUSTOMER_CREATE_MUTATION, {
  variables: {
    input: {
      email,
      firstName,
      lastName,
      phone: normalizePhone(phone),
      tags: ['B2B', 'Wholesale'],
      metafields: [
        { namespace: 'custom', key: 'company_name', value: companyName, type: 'single_line_text_field' },
        { namespace: 'b2b_onboard', key: 'application_id', value: applicationId, type: 'single_line_text_field' },
      ],
    },
  },
});
```

---

## Dual Metafield Namespace Convention

Use two namespaces for different visibility:

| Namespace | Visibility | Use for |
|-----------|-----------|---------|
| `custom` | Merchant-visible in Shopify admin | Data merchants should see/edit |
| `<app_namespace>` | App-specific, hidden from admin | Internal app tracking data |

```typescript
metafields: [
  // Merchant-visible
  { namespace: 'custom', key: 'company_name', value: companyName, type: 'single_line_text_field' },
  // App-internal
  { namespace: 'b2b_onboard', key: 'application_id', value: applicationId, type: 'single_line_text_field' },
]
```
