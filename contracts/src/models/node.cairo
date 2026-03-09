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
