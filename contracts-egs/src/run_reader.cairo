// Cross-contract interface for reading Catacombs Dojo world state.
// Must match the ABI of the deployed run_actions contract exactly.
// Run struct serializes as 8 flat felts; Node as 11 flat felts.

#[derive(Serde, Copy, Drop, Debug, PartialEq)]
pub enum RunStatus {
    Active,     // 0
    Completed,  // 1
    Failed,     // 2
}

#[derive(Serde, Copy, Drop, Debug)]
pub struct Run {
    pub id: u64,
    pub cat_id: u64,
    pub seed: felt252,
    pub current_node_id: u8,
    pub node_count: u8,
    pub status: RunStatus,
    pub score: u32,
    pub nodes_visited: u8,
}

#[starknet::interface]
pub trait IRunActions<T> {
    fn get_run(self: @T, run_id: u64) -> Run;
}
