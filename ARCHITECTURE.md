# Catacombs Architecture

## Overview

On-chain roguelike where cats explore procedurally generated catacombs.
Cats are persistent characters whose identity (personality, skills) lives in
git repos on gitlab.crux.casa, verified via Mirror SSH signatures.

## System Diagram

```
Player (Browser)
    |
    v
Frontend (React + Dojo SDK)
    |
    +-- Cartridge Wallet (auth, tx signing)
    |
    +-- Dojo Contracts (Starknet)
    |     cat_actions    -- create/verify cats
    |     run_actions    -- start runs, choose paths, generate maps
    |     encounter_actions -- submit scenarios, resolve encounters
    |
    +-- Oracle Service (off-chain)
    |     LLM scenario generation (seed -> scenario text)
    |     Skill evaluation (cat skill + scenario -> outcome)
    |     Mirror verification relay
    |
    +-- gitlab.crux.casa
          Cat repos managed by backend
          skills/ directory (skill definitions)
          soul.md, quirks.md (cat personality)
```

## Data Flow

### Cat Creation
1. Player connects Cartridge wallet
2. Frontend creates gitlab repo via API: gitlab.crux.casa/{player}/cat-{name}
3. Repo initialized with soul.md, quirks.md, skills/
4. Mirror verifies player owns repo (SSH sig challenge)
5. Contract stores cat with repo_hash, marked verified

### Catacomb Run
1. Player starts run -> contract generates seed, creates node map
2. Player sees branching paths (Slay the Spire style)
3. Player chooses next node
4. Oracle reads node seed, generates scenario via LLM
5. Player picks skill from their cat's repo
6. Oracle evaluates skill relevance in scenario context via LLM
7. Oracle submits outcome to contract (success/partial/failure)
8. Contract applies HP/XP/loot changes
9. Repeat until boss defeated or cat HP=0

### Skill Growth
- Between runs, new skills can be added to cat's repo
- Skills earned through gameplay experiences
- Backend manages git operations (player never touches git)

## Models

### On-Chain (Dojo)
- Cat: id, owner, repo_hash, stats (hp/atk/def/spd/lck), level, xp
- Run: id, cat_id, seed, current_node, floor, status, score
- Node: run_id, node_id, type, connections (bitmask), resolved, seed
- Encounter: run_id, node_id, scenario_hash, skill_hash, result, effects
- Item: cat_id, item_id, slot, power, equipped

### Off-Chain (Git Repo)
- soul.md: Cat's deeper personality, lore, voice
- quirks.md: Behavioral traits, preferences
- skills/{category}/{skill}/skill.json: Skill definitions
- skills/{category}/{skill}/SKILL.md: Skill flavor text

## Node Types
- Start: Entry point, no encounter
- Combat: Fight scenario, LLM generates enemy/situation
- Event: Narrative choice, skill-based resolution
- Treasure: Loot room
- Rest: Heal HP
- Shop: Spend gold on items
- Boss: Floor-ending challenge

## Map Layout (per floor)
```
        [1: Combat]---[3: Event]
       /                        \
[0: Start]                   [5: Rest]---[6: Boss]
       \                        /
        [2: Event]---[4: Treasure]
```
7 nodes per floor, 3 floors per run = 21 nodes max per run.

## Tech Stack
- Contracts: Cairo 2.13.1 / Dojo 1.8.0
- Frontend: React + TypeScript + Dojo SDK + Cartridge Connector
- Identity: Mirror (SSH signature verification)
- Git hosting: gitlab.crux.casa (self-hosted GitLab)
- Oracle: Node.js service calling Claude API for scenario gen + skill eval
