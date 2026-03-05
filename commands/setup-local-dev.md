# Setup Local Dev

Verify and configure the local development environment for a Shopify embedded app.

## Arguments

`$ARGUMENTS` = optional flags (e.g., "reset" to start fresh, "check" to only verify without changes)

## Instructions

1. Read `.claude/skills/shopify-app/references/local-dev-patterns.md` for Docker Compose setup, startup sequence, and environment variables.
2. Read `.claude/skills/shopify-app/SKILL.md` for key environment variables table and gotcha #10 (cached store association).
3. Run pre-flight checks:
   - Verify Docker is installed and running: `docker info`
   - Verify Node.js version matches requirements: `node --version`
   - Verify Shopify CLI is installed: `shopify version`
   - Verify npm dependencies are installed: check `node_modules/` exists
   - Check if `docker-compose.yml` exists in the project root
4. If `$ARGUMENTS` contains "check", report the status of each check and stop. Do not make changes.
5. Start infrastructure services:
   - Run `docker compose up -d` to start DynamoDB Local, DynamoDB Admin, and LocalStack
   - Wait for services to be healthy: check ports 8000 (DynamoDB), 8001 (Admin), 4566 (LocalStack)
6. Set up the `.env` file if it doesn't exist:
   - Copy from `.env.example` if available
   - Ensure these local development values are set:
     - `DYNAMODB_ENDPOINT=http://localhost:8000`
     - `AWS_S3_ENDPOINT=http://localhost:4566`
     - `EMAIL_QUEUE_URL` pointing to LocalStack SQS
   - Ask the user for `SHOPIFY_API_KEY` and `SHOPIFY_API_SECRET` if not set
7. Create the DynamoDB table if it doesn't exist:
   - Run `npm run setup` or the table creation script
   - Verify the table was created via DynamoDB Admin at http://localhost:8001
8. If `$ARGUMENTS` contains "reset":
   - Warn the user this will delete local data
   - Run `docker compose down -v` to remove volumes
   - Restart from step 5
9. Report the final status:
   - List all running services and their ports
   - Confirm `.env` is configured
   - Confirm DynamoDB table exists
   - Print the next step: `shopify app dev` to start the app
