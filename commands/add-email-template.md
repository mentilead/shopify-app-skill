# Add Email Template

Create a new email template with SQS queuing, Lambda worker processing, and suppression list checking.

## Arguments

`$ARGUMENTS` = template name and purpose (e.g., "application_approved for notifying applicants", "weekly_digest")

## Instructions

1. Parse the template name and purpose from `$ARGUMENTS`. If empty, ask the user what email to create and when it should be sent.
2. Read `.claude/skills/shopify-app/references/email-patterns.md` for SQS queuing, suppression lists, and worker patterns.
3. Read `.claude/skills/shopify-app/references/lambda-architecture.md` for SQS worker handler patterns.
4. Create or update the email template definition:
   - Add the template type to the email types (e.g., in an enum or constant map)
   - Define the required template variables (recipient, subject line, dynamic fields)
   - Create the HTML template (inline CSS only — email clients strip `<style>` tags inconsistently)
5. Add the SQS queue send helper in the relevant service function:
   - Queue via `SendMessageCommand` with `templateType`, `recipientEmail`, `shopDomain`, and `variables`
   - Never send email inline in request handlers — always queue
6. Update the email worker Lambda (`app/lambda-workers/email-worker.ts` or similar):
   - Add a case for the new template type
   - Check the suppression list before sending
   - Render the template with variables
   - Send via Resend (or configured provider)
   - Log success/failure with structured logging
7. If the email needs new DynamoDB storage (e.g., custom templates per shop):
   - Read `.claude/skills/shopify-app/references/dynamodb-patterns.md`
   - Add keys to `app/services/dynamodb/keys.ts` using the `EMAIL_TEMPLATE#<type>` pattern
8. Create a unit test for the template rendering logic.
9. Remind the user to:
    - Test with a real email address in the dev environment
    - Verify the SQS dead letter queue is configured for failed sends
    - Check the email renders correctly in major clients (Gmail, Outlook, Apple Mail)
