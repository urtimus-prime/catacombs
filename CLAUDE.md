# Deployment

## Environments

| Environment | Branch | Client URL | Explorer | Chain |
|-------------|--------|-----------|---------|-------|
| free | main | `catacombs-free.noods.cc` | `explorer.catacombs.noods.cc` (self-hosted) | Slot Katana (burner) |
| staging | staging | `catacombs-staging.noods.cc` | Sepolia Voyager | Sepolia (Controller) |
| production | production | `catacombs.noods.cc` | Sepolia Voyager | Sepolia (Controller) |

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
- Free (Katana): `https://api.cartridge.gg/x/catacombs/katana` (chain ID: `WP_CATACOMBS`)
- Free Torii: `https://api.cartridge.gg/x/catacombs/torii`
- Staging Torii: `https://api.cartridge.gg/x/catacombs-staging/torii` (indexes Sepolia world)
- Production Torii: `https://api.cartridge.gg/x/catacombs-production/torii` (indexes Sepolia world)
- Torii config format: flat TOML (`world_address = "...", rpc = "..."`)
- Update Torii world: `slot deployments update <project> torii --config <toml-file>`

## Worlds
- Free (Slot Katana): `0x06d0cbcf0cfcc7cf77cfe609816dd4818f56027824216ec0d95df4cf456ed00c`
- Staging (Sepolia): `0x0723ebd7b8cf2ee8ce1d4134f8f092390b49b6898789d40b5e6d54c10f5d47ce`
- Deployer account (Sepolia): `0x07b74a0227981b8ea8d12bb16276be9f23b3d4d58a5957be6b60688c686e19e3` (keys in `.env`)

## EGS (Embeddable Game Standard)
- Adapter contract (Sepolia): `0x0512e1ac90f210c337a7e3b25a9ec1e602de6cf1a9254ed129b9881bca814525`
- Adapter class hash: `0x34a52a871cff7bd50a6ccc73bfe031e40a45aa6d0bb2be08df07ed2b22ed919`
- Denshokan Token (Sepolia): `0x0142712722e62a38f9c40fcc904610e1a14c70125876ecaaf25d803556734467`
- MinigameRegistry (Sepolia): `0x040f1ed9880611bb7273bf51fd67123ebbba04c282036e2f81314061f6f9b1a1`
- Adapter workspace: `contracts-egs/` (Cairo 2.16.0, Scarb 2.16.0, separate from Dojo)
- Build: `SCARB=~/.local/share/scarb-install/latest/bin/scarb scarb build` (in contracts-egs/)
- Deploy: `SCARB=~/.local/share/scarb-install/latest/bin/scarb ~/.local/bin/sncast -p sepolia declare/deploy`
- sncast 0.55.0 at `~/.local/bin/sncast`, snfoundry config in `contracts-egs/snfoundry.toml`
- Verify tokens: `sncast -p sepolia call --contract-address <adapter> --function get_token_for_run --calldata <run_id>`

### Architecture
- Standalone contract (NOT a Dojo system) — separate Scarb workspace because EGS uses Cairo 2.16.0 / Scarb 2.16.0 while Dojo uses Cairo 2.13.1 / Scarb 2.13.1
- Implements `IMinigameTokenData` (`score`, `game_over`) by cross-contract calling Dojo's `get_run`
- Maps EGS `token_id` (felt252) ↔ Catacombs `run_id` (u64) via storage maps
- Key function: `mint_and_register(to, run_id)` — mints Denshokan ERC721 token + binds to run in one tx
- Frontend calls `mint_and_register` automatically after `start_run` (Sepolia/Mainnet only)
- `score(token_id)` reads `run.score` from Dojo world in real-time (cross-contract call)
- `game_over(token_id)` returns true when `run.status != Active`

### When to redeploy the adapter
- Only if `Run` struct fields/order change or `RunStatus` enum variants change in Dojo contracts
- Adding new Dojo systems, models, or changing non-Run structs does NOT require adapter changes
- Constructor takes `run_actions_address` — must match the current world's run_actions contract (check manifest)

### Deployment gotchas
- Constructor arg `run_actions_address` must be the run_actions address from the CURRENT Sepolia world manifest — if you deploy a new world (new seed), you must redeploy the adapter too
- Cartridge Controller cannot deserialize complex ABI types like `Option<GameContextDetails>` — wrap complex calls in simple adapter functions (e.g. `mint(to)` instead of exposing raw `mint_game` with 14 params)
- denshokan-sdk requires starknet.js >=9.0.0 — can't use yet (Dojo stack pins v8). Use raw `account.execute()` calls instead
- Declare transactions on Sepolia can take 1-5 minutes to confirm — poll with `sncast tx-status` before deploying; transactions may be dropped and need re-submission
- Estimated gas for declare can be high (~6-7 STRK) — keep deployer funded via Sepolia faucet

## Cloudflare
- Token in `.env` as `CLOUDFLARE_TOKEN` — account-scoped API Token (DNS Zone Edit + R2 Admin)
- Verify: `GET /accounts/{acct}/tokens/verify` (NOT `/user/tokens/verify` — it's account-scoped)
- Auth header: `Authorization: Bearer $CLOUDFLARE_TOKEN`
- Extract token: `sed -n 's/^CLOUDFLARE_TOKEN="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' .env` (handles quotes)
- Account ID: `9f79de7451518c7dcca5c99e02eff767`
- Zone: `noods.cc` — Zone ID: `d41fdeec4e58d62a742e23805ab6f31a`
- Railway custom domains need unproxied CNAMEs (DNS only, not orange-clouded)

## Cloudflare R2
- Bucket: `catacombs-assets`
- Public URL: `https://pub-f5ae3b0da5d447b4b4f6a8cd2270c415.r2.dev/`
- Custom domain: `https://assets.catacombs.noods.cc/` (active, SSL provisioned)
- Cat viewer assets at: `cat-viewer/` prefix (embed.html, index.js, index.wasm, index.pck)
- Upload: `curl -X PUT .../r2/buckets/catacombs-assets/objects/{key} -H "Authorization: Bearer $TOKEN" --data-binary @file`
- ~56MB total (37MB WASM + 20MB PCK + JS/HTML)

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

## Deployment Gotchas

### Dojo world schema upgrades
- Dojo does NOT allow changing the schema of registered models or events on an existing world
- If you change a struct (add/remove/reorder fields) for a `#[dojo::model]` or `#[dojo::event]`, `sozo migrate` will fail with `"Invalid new schema to upgrade the resource"`
- **Fix**: change the world seed in the dojo profile TOML (e.g. `seed = "catacombs_v2"`) to deploy a fresh world, then update all Torii configs and manifests
- Logic-only changes inside system functions (constants, control flow) are fine — sozo upgrades the contract class in-place

### sozo migrate says "World already synced" unexpectedly
- sozo compares compiled Sierra bytecode against what's on-chain, not against the manifest JSON
- If manifests are stale but on-chain matches the local build, sozo correctly reports "synced"
- Always `sozo build -P <profile>` before migrating to ensure artifacts are fresh
- The dev and sepolia profiles may produce different class hashes for the same source code

### Manifest must be copied to client after deploy
- After `sozo migrate`, copy `contracts/manifest_<env>.json` → `client/src/dojo/manifest_<env>.json`
- The client reads contract addresses from the manifest at build time — stale manifests = wrong addresses = silent RPC failures

### Slot Torii world address
- When deploying a new world, Slot Torii must be updated to index the new address
- `slot deployments update <project> torii --config <toml>` — the TOML has `world_address` and `rpc`
- `slot deployments delete` panics in non-interactive shells — use `update` instead of delete+recreate
- `slot deployments create` requires `--config <path>` (no inline `--world` flag)

### Katana fresh restart
- Restarting Katana (`--dev --dev.no-fee`) wipes all state — world address changes after `sozo migrate`
- Local Torii must be restarted with the new world address
- The client auto-reconnects but won't find data at the old world's contract addresses until manifest is updated and Vite reloads

### GitHub environment variables
- Deploy vars (`VITE_CHAIN`, `VITE_RPC_URL`, `VITE_TORII_URL`, `VITE_EXPLORER_URL`) are scoped per GitHub environment, set via GitHub API
- Changing these does NOT auto-redeploy — you must push to the branch to trigger the workflow
- Railway env vars (PORT, domains) are set on Railway side; VITE_ vars are build-args in the Docker build

### STRK allowance on fresh chains
- On a fresh Katana (or new Sepolia world), the STRK ERC20 allowance for the shiny contract is zero
- Must call `approve` on STRK token for the shiny contract address before `buy_shinies` will work
- Error: `"ERC20: insufficient allowance"` — this is not a balance issue, it's an approve issue
