// Encounters are resolved at each node.
// The LLM oracle generates a scenario from the node's seed.
// The player picks a skill from their cat's repo.
// The oracle evaluates skill relevance and returns an outcome.
// The outcome hash is stored on-chain for auditability.

#[derive(Serde, Copy, Drop, Introspect, Debug, PartialEq, DojoStore)]
pub enum EncounterResult {
    Pending,
    Success,    // full reward, no damage
    Partial,    // some reward, some damage
    Failure,    // no reward, full damage
}

impl EncounterResultDefault of Default<EncounterResult> {
    fn default() -> EncounterResult {
        EncounterResult::Pending
    }
}

#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Encounter {
    #[key]
    pub run_id: u64,
    #[key]
    pub node_id: u8,
    // Hash of the LLM-generated scenario text
    pub scenario_hash: felt252,
    // Hash of the skill the player chose to use
    pub skill_hash: felt252,
    // Oracle's evaluation result
    pub result: EncounterResult,
    // Effects on the cat
    pub hp_delta: i8,
    pub xp_gained: u16,
    pub loot_id: u8, // 0 = no loot
}

// Events

#[derive(Copy, Drop, Serde)]
#[dojo::event]
pub struct ScenarioGenerated {
    #[key]
    pub run_id: u64,
    pub node_id: u8,
    pub scenario_hash: felt252,
}

#[derive(Copy, Drop, Serde)]
#[dojo::event]
pub struct EncounterResolved {
    #[key]
    pub run_id: u64,
    pub node_id: u8,
    pub result: EncounterResult,
    pub hp_delta: i8,
    pub xp_gained: u16,
    pub loot_id: u8,
}
