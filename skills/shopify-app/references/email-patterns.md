# Email Patterns

## Always Queue via SQS

Never send email inline in a request handler. Queue the message and let a worker process it:

```typescript
// WRONG — sending inline blocks the request and may timeout
await resend.emails.send({ to, subject, html });
return { ok: true };

// CORRECT — queue and return immediately
await sqsClient.send(new SendMessageCommand({
  QueueUrl: process.env.EMAIL_QUEUE_URL,
  MessageBody: JSON.stringify({
    templateType: 'application_approved',
    recipientEmail: applicant.email,
    shopDomain,
    variables: {
      applicantName: applicant.name,
      shopName: shop.name,
    },
  }),
}));
return { ok: true };
```

**Why:** Email delivery is slow and unreliable. SQS provides retry, DLQ, and decouples the user-facing request from email delivery.

---

## Email Suppression List

Track bounces and complaints to avoid sending to bad addresses:

```typescript
// Check before sending
const suppressed = await dynamodb.send(new GetCommand({
  TableName: TABLE_NAME,
  Key: keys.suppression(recipientEmail),
}));

if (suppressed.Item) {
  console.log(`Skipping email to suppressed address: ${recipientEmail}`);
  return;
}
```

### Adding to Suppression List

```typescript
async function addSuppression({
  email,
  type,
  reason,
}: {
  email: string;
  type: 'BOUNCE' | 'COMPLAINT';
  reason?: string;
}) {
  await dynamodb.send(new PutCommand({
    TableName: TABLE_NAME,
    Item: {
      PK: `SUPPRESSION#${email.toLowerCase()}`,
      SK: 'SUPPRESSION',
      email: email.toLowerCase(),
      type,
      reason,
      createdAt: new Date().toISOString(),
    },
  }));
}
```

---

## Resend Webhook for Bounces/Complaints

Resend uses Svix for webhook delivery. Verify the signature before processing:

```typescript
// app/routes/api.webhooks.resend.tsx
import { Webhook } from 'svix';

export const action = async ({ request }: ActionFunctionArgs) => {
  const body = await request.text();
  const headers = {
    'svix-id': request.headers.get('svix-id') ?? '',
    'svix-timestamp': request.headers.get('svix-timestamp') ?? '',
    'svix-signature': request.headers.get('svix-signature') ?? '',
  };

  const webhookSecret = process.env.RESEND_WEBHOOK_SECRET;
  if (!webhookSecret) {
    return new Response('Not configured', { status: 500 });
  }

  const wh = new Webhook(webhookSecret);
  let payload;

  try {
    payload = wh.verify(body, headers);
  } catch {
    return new Response('Invalid signature', { status: 401 });
  }

  switch (payload.type) {
    case 'email.bounced':
      await addSuppression({
        email: payload.data.to[0],
        type: 'BOUNCE',
        reason: payload.data.bounce_type,
      });
      break;
    case 'email.complained':
      await addSuppression({
        email: payload.data.to[0],
        type: 'COMPLAINT',
      });
      break;
  }

  return new Response(null, { status: 200 });
};
```
