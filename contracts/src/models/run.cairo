// A run is a single catacomb expedition by one cat.
// Each run has a seed that deterministically generates the map.
// Cats persist across runs — a failed run wounds the cat but doesn't kill it.

#[derive(Serde, Copy, Drop, Introspect, Debug, PartialEq, DojoStore)]
pub enum RunStatus {
    Active,
    Completed,
    Failed, // cat wounded, run abandoned or HP=0
}

impl RunStatusDefault of Default<RunStatus> {
    fn default() -> RunStatus {
        RunStatus::Active
    }
}

#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Run {
    #[key]
    pub id: u64,
    pub cat_id: u64,
    pub seed: felt252,
    pub current_node_id: u8,
    pub floor: u8,
    pub max_floors: u8,
    pub status: RunStatus,
    pub score: u32,
    pub nodes_visited: u8,
}

// Singleton counter for run IDs.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct RunCounter {
    #[key]
    pub world_id: u8,
    pub count: u64,
}

// Events

#[derive(Copy, Drop, Serde)]
#[dojo::event]
pub struct RunStarted {
    #[key]
    pub cat_id: u64,
    pub run_id: u64,
    pub seed: felt252,
}

#[derive(Copy, Drop, Serde)]
#[dojo::event]
pub struct RunCompleted {
    #[key]
    pub run_id: u64,
    pub cat_id: u64,
    pub score: u32,
    pub status: RunStatus,
}
