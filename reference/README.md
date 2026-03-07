# Dojo Reference Projects

Three reference projects demonstrating different approaches to building on-chain games with Starknet. Use this as a guide when building a new game.

---

## Project Overview

| | **starter** | **number-guess** | **nums** |
|---|---|---|---|
| **Type** | Treasure hunt grid game | Number guessing game | Number placement puzzle |
| **Framework** | Dojo ECS | Raw Starknet + Apibara | Dojo ECS |
| **Frontend** | React + Vite + CSS | None (API only) | React + Vite + Tailwind |
| **Contracts** | Cairo 2.13.1 / Scarb | Cairo 2.15.0 / Scarb | Cairo 2.13.1 / Scarb |
| **Indexing** | Torii (Dojo built-in) | Apibara + PostgreSQL | Torii (Dojo built-in) |
| **Wallet** | Cartridge Controller | External client | Cartridge Controller |
| **Complexity** | Simple (learning) | Medium (infra-focused) | Complex (production) |

---

## 1. starter — Treasure Hunt (Simplest / Best Starting Point)

A turn-based dig-for-treasure game on a 10x10 grid. Players move, dig tiles, find gold or bombs, and level up.

### Tech Stack
- **Contracts**: Cairo + Dojo 1.8.0
- **Client**: React 18 + TypeScript + Vite
- **Indexer**: Torii 1.8.15 (auto-indexes Dojo models)
- **Wallet**: Cartridge Controller with session keys
- **Dev**: Katana local devnet, `sozo migrate`

### Architecture

```
contracts/src/
  models.cairo          # Player model (x, y, health, gold, level, dug bitmap)
  systems/actions.cairo # spawn(), move(), dig() — core game logic
  tests/                # 12 Cairo unit tests

client/src/
  App.tsx               # Main UI — grid, HUD, compass, modals
  starknet.tsx          # Cartridge Controller + session key policies
  tiles.ts              # Client-side tile rendering (Poseidon hash mirroring)
  dojo/
    config.ts           # SDK + Torii/RPC URLs
    contracts.ts        # Type-safe system call wrappers
    models.ts           # TypeScript models mirroring Cairo
```

### Key Patterns

- **Dojo ECS**: Player is a single model keyed by `ContractAddress`. Torii auto-indexes and provides live subscriptions.
- **Two-layer randomness**: Layer 1 (Poseidon hash) is deterministic — client renders tile content without RPC. Layer 2 (block timestamp) determines dig outcome on-chain only.
- **Bitmap encoding**: 100 tiles packed into a single `felt252` (252-bit field). Bit index = `y * 10 + x`.
- **Session keys**: Cartridge Controller whitelists `spawn`, `move`, `dig` — no manual tx approval per action.
- **One-command dev**: `./scripts/dev.sh` boots Katana, migrates, starts Torii, and launches Vite.

### Game Flow
1. `spawn()` → Player at (0,0), 100 health, level 1
2. `move(direction)` → Costs 1 health, clamped to grid bounds
3. `dig()` → Reveals tile: gold (+10) or bomb (-10 health)
4. Gold >= level × 100 → Level up (reset position/health, keep gold)
5. Health = 0 → Game over

---

## 2. number-guess — Guessing Game (Infrastructure Reference)

A number guessing game with custom indexing pipeline. No frontend in this repo — it's a backend/contract/API reference.

### Tech Stack
- **Contracts**: Cairo + game-components library (Provable Games)
- **Indexer**: Apibara (event stream) + Drizzle ORM + PostgreSQL
- **API**: Hono (lightweight HTTP) + WebSocket
- **Infra**: Docker Compose

### Architecture

```
contracts/packages/number_guess/src/
  number_guess.cairo    # 1093-line contract (new_game, guess, settings, objectives)

indexer/
  indexers/number-guess.indexer.ts  # Apibara event processor (396 lines)
  src/lib/schema.ts                # Drizzle schema (game_sessions, guesses, game_stats)
  src/lib/decoder.ts               # Starknet event decoder

api/src/
  routes/               # REST: sessions, leaderboard, stats, players
  ws/subscriptions.ts   # WebSocket real-time events via pg_notify
  middleware/            # Rate limiting
```

### Key Patterns

- **No Dojo**: Uses raw Starknet contracts + game-components library instead of Dojo ECS.
- **Apibara indexer**: Watches `NewGameStarted` and `GuessMade` events, writes to PostgreSQL. Handles chain reorgs with idempotent writes.
- **Real-time pipeline**: Indexer → PostgreSQL `pg_notify` → API WebSocket → Client.
- **Pedersen PRNG**: Secret number = Pedersen hash of (token_id + games_played). Deterministic, auditable.
- **Packed token IDs**: Settings/difficulty embedded in token_id at mint time.
- **Scoring**: Base 100 pts + efficiency bonus (fewer guesses = more points) + perfect game bonus.
- **3 difficulty settings**: Easy (1-10, unlimited), Medium (1-100, 10 tries), Hard (1-1000, 10 tries).

### Data Flow
```
Player tx → Starknet → Contract emits events → Apibara indexes → PostgreSQL
  → pg_notify → WebSocket push to clients
  → REST API serves queries
```

---

## 3. nums — Number Placement Puzzle (Production Reference)

A complex puzzle game: place random numbers (1-999) into 18 ascending slots. Features power-ups, traps, achievements, token rewards, and staking.

### Tech Stack
- **Contracts**: Cairo + Dojo + OpenZeppelin + Ekubo VRF
- **Client**: React 19 + TypeScript + Vite + Tailwind + Radix UI + Framer Motion
- **Indexer**: Torii (Dojo built-in)
- **Wallet**: Cartridge Controller
- **Extras**: Storybook, TanStack Query, Recharts, Sonner toasts

### Architecture

```
contracts/src/
  systems/
    play.cairo          # Core: set(), select(), apply(), claim()
    setup.cairo          # Game initialization
    collection.cairo     # NFT collection
    token.cairo          # ERC20 NUMS token
    vault.cairo          # Staking
  models/game.cairo      # Game state (slots, powers, traps, level, gold)
  elements/
    powers/              # 8+ power-ups (reroll, swap, mirror, halve, etc.)
    traps/               # 5 traps (bomb, lucky, magnet, ufo, windy)
    achievements/        # Achievement system
    quests/              # Quest system
  helpers/
    packer.cairo         # Bit packing for slots/powers/traps
    random.cairo         # Seeded RNG
    verifier.cairo       # Game-over/validity checks

client/src/
  models/game.ts         # TypeScript Game class mirroring Cairo exactly
  engines/index.ts       # GameEngine (blockchain operation wrapper)
  elements/              # Client-side power/trap implementations
  helpers/               # Packer, verifier, rewarder, random (mirrors Cairo)
  context/               # 13+ React contexts (practice, entities, audio, etc.)
  hooks/                 # actions, games, leaderboard, staking, etc.
  components/
    scenes/              # Full-screen views (home, game, leaderboard)
    containers/          # Smart components (slots, power-ups)
    elements/            # Slot, card, power-up, stage indicators
    ui/                  # shadcn-style primitives (button, dropdown, etc.)
  pages/
    home.tsx             # Lobby with active games
    game.tsx             # Main gameplay
```

### Key Patterns

- **Model mirroring**: TypeScript `Game` class exactly mirrors Cairo `Game` model, enabling local practice mode that matches on-chain behavior.
- **Dual-mode execution**: Blockchain mode (Starknet txs + Torii subscriptions) and Practice mode (local GameEngine, no chain) share the same Game model.
- **Bit packing**: Powers, traps, and slot states packed into felt252 fields for gas efficiency. Unpacked in TypeScript for UI.
- **Ekubo VRF**: Verifiable random function for on-chain randomness. Prevents manipulation.
- **Context-based state**: 13+ specialized React contexts (practice, entities, loading, audio, prices, quests, achievements, vault, etc.).
- **Reward economics**: Supply-based reward curves, break-even calculations, multiplier tiers via starter packs.
- **Component architecture**: Dojo components (`PlayableComponent`, `AchievableComponent`, `QuestableComponent`, `RankableComponent`) for composable game features.

### Game Flow
1. Purchase game via starterpack (sets multiplier)
2. Receive random number (1-999), place in one of 18 ascending slots
3. Traps trigger on placement (bomb blocks, magnet moves, etc.)
4. Every 4 levels, choose from 2 random power-ups
5. Fill all slots = win, stuck with no moves = lose
6. Claim accumulated NUMS token rewards

---

## Common Patterns Across Projects

### Dojo ECS (starter + nums)
- Models define on-chain state, keyed by entity ID or address
- Systems are stateless functions that modify models
- Torii auto-indexes models and provides gRPC/WebSocket subscriptions
- `sozo migrate` deploys and sets up world permissions
- Client uses `@dojoengine/sdk` for subscriptions and calls

### Cartridge Controller (starter + nums)
- Session keys whitelist specific contract methods for auto-signing
- Configured in a `policies` array with contract address + entry point
- Eliminates per-action wallet popups during gameplay

### Cairo Contract Testing
- All three projects have Cairo unit tests
- Use SNForge for test execution
- Cheat helpers (set caller, set timestamp) for deterministic testing

### Client-Contract Symmetry
- TypeScript models mirror Cairo models field-for-field
- Enables client-side simulation/validation before submitting transactions
- Practice/offline modes use the same game logic

### Randomness Approaches
| Project | Method | Trade-off |
|---------|--------|-----------|
| starter | Poseidon hash + block timestamp | Deterministic rendering, runtime outcomes |
| number-guess | Pedersen hash(token_id + games_played) | Fully deterministic, auditable |
| nums | Ekubo VRF | Cryptographically verifiable, production-grade |

---

## Quick Start Reference

### Dojo Project (starter/nums pattern)
```bash
# 1. Build contracts
cd contracts && scarb build

# 2. Start local devnet
katana --dev

# 3. Deploy
sozo migrate --dev

# 4. Start indexer
torii --world <world_address>

# 5. Start client
cd client && pnpm install && pnpm dev
```

### Raw Starknet Project (number-guess pattern)
```bash
# 1. Build contracts
cd contracts && scarb build

# 2. Start infrastructure
docker-compose up -d postgres

# 3. Deploy contract
./scripts/deploy_number_guess.sh

# 4. Run indexer
npm run dev:indexer

# 5. Run API
npm run dev:api
```

---

## When Building a New Game

| Decision | Recommendation |
|----------|---------------|
| **Starting out** | Fork `starter` — simplest setup, one-command dev |
| **Need custom indexing** | Reference `number-guess` for Apibara + PostgreSQL pipeline |
| **Production game** | Reference `nums` for power-ups, achievements, token economics |
| **State management** | Use Dojo ECS + Torii unless you need custom queries |
| **Randomness** | Ekubo VRF for production, Poseidon hash for prototyping |
| **Wallet UX** | Cartridge Controller + session keys for seamless gameplay |
| **Testing** | Cairo unit tests (SNForge) + Playwright e2e |
| **Styling** | Tailwind + Radix UI (nums) or plain CSS (starter) |
