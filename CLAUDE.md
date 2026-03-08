# Deployment

## Environments

| Environment | Branch | Client URL | Explorer | Chain |
|-------------|--------|-----------|---------|-------|
| free | main | `catacombs-free.noods.cc` | `explorer.catacombs.noods.cc` (self-hosted) | Slot Katana (burner) |
| staging | staging | `catacombs-staging.noods.cc` | Sepolia Starkscan | Sepolia (Controller) |
| production | production | `catacombs.noods.cc` | Mainnet Starkscan | Mainnet (Controller) |

## Railway
- Token in `.env` as `RAILWAY_TOKEN` — works with GraphQL API only, NOT the Railway CLI
- API endpoint: `https://backboard.railway.com/graphql/v2`
- Auth header: `Authorization: Bearer $RAILWAY_TOKEN`
- Workspace ID: `13a3fd1b-9b9b-499b-ab88-4f82b4b54e76`
- Project ID: `917e7842-1b7c-460c-90fe-4acbf7c6f706` (name: "catacombs")
- Services: `client` (`59befabc`), `explorer` (`9722184a`)
- Free env ID: `17b65ce0-ab68-4339-ae25-83dddb7690db`
- Staging env ID: `e14a685d-052a-4ad7-a4b9-45619a1cc453`
- Production env ID: `7001107f-06b4-4b2d-aba1-7e9e7864f867`
- To load .env: `export $(cat /home/paul/projects/catacombs/.env | xargs)`
- Custom domains require CNAME pointing to Railway's `requiredValue` (NOT the service domain), unproxied

## Slot (Cartridge)
- CLI: `/home/paul/.slot/bin/slot`
- Katana: `https://api.cartridge.gg/x/catacombs/katana` (chain ID: `WP_CATACOMBS`)
- Torii: `https://api.cartridge.gg/x/catacombs/torii`
- World: `0x06d0cbcf0cfcc7cf77cfe609816dd4818f56027824216ec0d95df4cf456ed00c`
- Torii config format: flat TOML (`world_address = "...", rpc = "..."`)

## Cloudflare
- Token in `.env` as `CLOUDFLARE_TOKEN` — scoped API Token (DNS Zone Edit only)
- Auth header: `Authorization: Bearer $CLOUDFLARE_TOKEN`
- Account ID: `9f79de7451518c7dcca5c99e02eff767`
- Zone: `noods.cc` — Zone ID: `d41fdeec4e58d62a742e23805ab6f31a`
- Railway custom domains need unproxied CNAMEs (DNS only, not orange-clouded)

## GitHub
- PAT in `.env` as `GITHUB_PAT_URTIMUS_PRIME`
- Push: `git push https://${GITHUB_PAT_URTIMUS_PRIME}@github.com/urtimus-prime/catacombs.git <branch>`
- Deploy variables are scoped per GitHub environment (free/staging/production), not repo-level

## Client VITE_CHAIN modes
- `katana` — local Katana, MockConnector (burner accounts)
- `slot` — Slot Katana, MockConnector (burner accounts), WP_CATACOMBS chain ID
- `sepolia` — Sepolia testnet, Cartridge Controller, SN_SEPOLIA chain ID
- `mainnet` — Starknet mainnet, Cartridge Controller, SN_MAIN chain ID

## Katana accounts (safe to commit)
- Predeployed test accounts are public by design (seed "0")
- Private keys in `client/src/starknet.tsx` are NOT secrets
