// Model interfaces matching on-chain Cairo structs.
// fieldOrder MUST match the order in the Cairo struct.

export interface Cat {
  fieldOrder: string[];
  id: number;
  owner: string;
  repo_hash: string;
  hp: number;
  max_hp: number;
  level: number;
  xp: number;
  attack: number;
  defense: number;
  speed: number;
  luck: number;
  alive: boolean;
  runs_completed: number;
  runs_failed: number;
  verified: boolean;
}

export interface Run {
  fieldOrder: string[];
  id: number;
  cat_id: number;
  seed: string;
  current_node_id: number;
  floor: number;
  max_floors: number;
  status: number; // 0=Active, 1=Completed, 2=Failed
  score: number;
  nodes_visited: number;
}

export interface Node {
  fieldOrder: string[];
  run_id: number;
  node_id: number;
  floor: number;
  node_type: number; // 0=Start,1=Combat,2=Treasure,3=Rest,4=Event,5=Shop,6=Boss
  resolved: boolean;
  outcome_seed: string;
  connections: number;
}

export interface Encounter {
  fieldOrder: string[];
  run_id: number;
  node_id: number;
  scenario_hash: string;
  skill_hash: string;
  result: number; // 0=Pending,1=Success,2=Partial,3=Failure
  hp_delta: number;
  xp_gained: number;
  loot_id: number;
}

export interface CatAppearance {
  fieldOrder: string[];
  cat_id: number;
  packed: string;
}

export interface SchemaType {
  [namespace: string]: { [model: string]: { [field: string]: any } };
  catacombs: {
    Cat: Cat;
    CatAppearance: CatAppearance;
    Run: Run;
    Node: Node;
    Encounter: Encounter;
  };
}

export const schema: SchemaType = {
  catacombs: {
    Cat: {
      fieldOrder: [
        "id", "owner", "repo_hash", "hp", "max_hp", "level", "xp",
        "attack", "defense", "speed", "luck", "alive",
        "runs_completed", "runs_failed", "verified",
      ],
      id: 0, owner: "", repo_hash: "0x0", hp: 0, max_hp: 0,
      level: 0, xp: 0, attack: 0, defense: 0, speed: 0, luck: 0,
      alive: false, runs_completed: 0, runs_failed: 0, verified: false,
    },
    CatAppearance: {
      fieldOrder: ["cat_id", "packed"],
      cat_id: 0, packed: "0x0",
    },
    Run: {
      fieldOrder: [
        "id", "cat_id", "seed", "current_node_id", "floor",
        "max_floors", "status", "score", "nodes_visited",
      ],
      id: 0, cat_id: 0, seed: "0x0", current_node_id: 0,
      floor: 0, max_floors: 0, status: 0, score: 0, nodes_visited: 0,
    },
    Node: {
      fieldOrder: [
        "run_id", "node_id", "floor", "node_type", "resolved",
        "outcome_seed", "connections",
      ],
      run_id: 0, node_id: 0, floor: 0, node_type: 0,
      resolved: false, outcome_seed: "0x0", connections: 0,
    },
    Encounter: {
      fieldOrder: [
        "run_id", "node_id", "scenario_hash", "skill_hash",
        "result", "hp_delta", "xp_gained", "loot_id",
      ],
      run_id: 0, node_id: 0, scenario_hash: "0x0", skill_hash: "0x0",
      result: 0, hp_delta: 0, xp_gained: 0, loot_id: 0,
    },
  },
};

export enum ModelsMapping {
  Cat = "catacombs-Cat",
  CatAppearance = "catacombs-CatAppearance",
  CatCounter = "catacombs-CatCounter",
  PlayerCats = "catacombs-PlayerCats",
  Run = "catacombs-Run",
  RunCounter = "catacombs-RunCounter",
  Node = "catacombs-Node",
  Encounter = "catacombs-Encounter",
  Item = "catacombs-Item",
  CatInventory = "catacombs-CatInventory",
}

export const NODE_TYPES = ["Start", "Combat", "Treasure", "Rest", "Event", "Shop", "Boss"] as const;
export const RUN_STATUS = ["Active", "Completed", "Failed"] as const;
export const ENCOUNTER_RESULTS = ["Pending", "Success", "Partial", "Failure"] as const;
