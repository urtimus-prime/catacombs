# Deployment

## Target
- URL: `catacombs.noods.cc`
- Hosting: Railway (static site)
- DNS: Cloudflare (noods.cc zone)

## Railway
- Token in `.env` as `RAILWAY_TOKEN` — works with GraphQL API only, NOT the Railway CLI
- API endpoint: `https://backboard.railway.com/graphql/v2`
- Auth header: `Authorization: Bearer $RAILWAY_TOKEN`
- Docs: https://docs.railway.com/integrations/api
- Workspace ID: `13a3fd1b-9b9b-499b-ab88-4f82b4b54e76`
- Project ID: `917e7842-1b7c-460c-90fe-4acbf7c6f706` (name: "catacombs")
- Service ID: `59befabc-d5b5-4420-98b8-860f2a0e9eb8` (name: "client")
- Environment ID: `17b65ce0-ab68-4339-ae25-83dddb7690db` (name: "production")
- To load .env properly: `export $(cat /home/paul/projects/catacombs/.env | xargs)`
- Deploy requires either GitHub App connection or Docker image — can't do direct file upload via API
- GitHub repo `urtimus-prime/catacombs` needs Railway GitHub App installed for auto-deploy

## Cloudflare
- Token in `.env` as `CLOUDFLARE_TOKEN` — this is a **scoped API Token** (NOT Global API Key, NOT Wrangler token)
- Permissions: DNS Zone Edit only
- Auth header: `Authorization: Bearer $CLOUDFLARE_TOKEN`
- Must include `account.id` param when listing zones: `?account.id=9f79de7451518c7dcca5c99e02eff767`
- Account ID: `9f79de7451518c7dcca5c99e02eff767`
- Zone: `noods.cc` — Zone ID: `d41fdeec4e58d62a742e23805ab6f31a`
- Use Cloudflare API directly for DNS records, NOT wrangler (token lacks Pages/Workers permissions)

## Katana accounts (safe to commit)
- Katana predeployed test accounts are public by design (printed in every Katana startup log)
- Private keys in `client/src/starknet.tsx` and `client/src/dojo/burner.ts` are NOT secrets

## GitHub
- PAT in `.env` as `GITHUB_PAT_URTIMUS_PRIME`
- Push with: `git push https://${GITHUB_PAT_URTIMUS_PRIME}@github.com/urtimus-prime/catacombs.git main`
- `.env` is gitignored — safe
