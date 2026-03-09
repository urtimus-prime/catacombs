// Nodes form the branching map of a catacomb run.
// The entire run is a single 10-column DAG (like Slay the Spire).
// Players choose which node to visit next from available connections.

#[derive(Serde, Copy, Drop, Introspect, Debug, PartialEq, DojoStore)]
pub enum NodeType {
    Start,
    Combat,
    Treasure,
    Rest,
    Event,     // narrative choice / LLM scenario
    Boss,      // end of run
}

impl NodeTypeDefault of Default<NodeType> {
    fn default() -> NodeType {
        NodeType::Start
    }
}

#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Node {
    #[key]
    pub run_id: u64,
    #[key]
    pub node_id: u8,
    pub column: u8,
    pub row: u8,
    pub node_type: NodeType,
    pub resolved: bool,
    pub outcome_seed: felt252,
    pub skill_tag_1: felt252,
    pub skill_tag_2: felt252,
    pub difficulty: u8,
    // Connections stored as packed bits: bit N = connects to node N
    // Supports up to 32 nodes per run
    pub connections: u32,
}

// Stores the resolution outcome for a node (written by choose_path auto-resolve)
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct NodeOutcome {
    #[key]
    pub run_id: u64,
    #[key]
    pub node_id: u8,
    pub skill_tag: felt252,
    pub cat_stat: u8,
    pub roll: u8,
    pub difficulty: u8,
    pub result: u8,        // 0=N/A, 1=Success, 2=Partial, 3=Failure
    pub hp_delta: i8,
    pub xp_gained: u16,
    pub score_delta: u32,
    pub cat_hp_after: u8,
    pub cat_xp_after: u32,
    pub leveled_up: bool,
}

// Events

#[derive(Copy, Drop, Serde)]
#[dojo::event]
pub struct NodeVisited {
    #[key]
    pub run_id: u64,
    pub node_id: u8,
    pub node_type: NodeType,
}

#[derive(Copy, Drop, Serde)]
#[dojo::event]
pub struct PathChosen {
    #[key]
    pub run_id: u64,
    pub from_node: u8,
    pub to_node: u8,
}

// Emitted when a node is auto-resolved on entry (skill check, rest, treasure)
#[derive(Copy, Drop, Serde)]
#[dojo::event]
pub struct NodeResolved {
    #[key]
    pub run_id: u64,
    pub node_id: u8,
    pub node_type: NodeType,
    pub skill_tag: felt252,     // primary skill checked (0 for passive nodes)
    pub cat_stat: u8,           // cat's relevant stat value
    pub roll: u8,               // d20 roll (0 for passive nodes)
    pub difficulty: u8,         // threshold to beat
    pub result: u8,             // 0=N/A, 1=Success, 2=Partial, 3=Failure
    pub hp_delta: i8,           // signed HP change
    pub xp_gained: u16,         // XP earned
    pub score_delta: u32,       // score earned
    pub cat_hp_after: u8,       // cat HP after resolution
    pub cat_xp_after: u32,      // cat XP after resolution
    pub leveled_up: bool,       // whether cat leveled up
}
