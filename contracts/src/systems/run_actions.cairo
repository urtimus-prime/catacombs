use catacombs::models::run::Run;
use catacombs::models::node::Node;

#[starknet::interface]
pub trait IRunActions<T> {
    // Start a new catacomb run with a cat.
    fn start_run(ref self: T, cat_id: u64) -> u64;

    // Player chooses which node to visit next.
    fn choose_path(ref self: T, run_id: u64, next_node_id: u8);

    // Abandon a run (cat comes home wounded).
    fn abandon_run(ref self: T, run_id: u64);

    // Read run state.
    fn get_run(self: @T, run_id: u64) -> Run;

    // Get a node in a run.
    fn get_node(self: @T, run_id: u64, node_id: u8) -> Node;
}

#[dojo::contract]
pub mod run_actions {
    use super::IRunActions;
    use starknet::{get_caller_address, get_block_timestamp};
    use core::poseidon::poseidon_hash_span;
    use dojo::model::ModelStorage;
    use dojo::event::EventStorage;
    use catacombs::models::cat::Cat;
    use catacombs::models::run::{Run, RunStatus, RunCounter, RunStarted, RunCompleted};
    use catacombs::models::node::{Node, NodeType, NodeVisited, PathChosen};

    const NODES_PER_FLOOR: u8 = 7;
    const DEFAULT_MAX_FLOORS: u8 = 3;

    #[abi(embed_v0)]
    impl RunActionsImpl of IRunActions<ContractState> {
        fn start_run(ref self: ContractState, cat_id: u64) -> u64 {
            let mut world = self.world_default();
            let caller = get_caller_address();

            // Verify ownership and cat health
            let cat: Cat = world.read_model(cat_id);
            assert!(cat.owner == caller, "not your cat");
            assert!(cat.alive, "cat is dead");
            assert!(cat.hp > 0, "cat is wounded, needs rest");

            // Generate run ID
            let mut counter: RunCounter = world.read_model(0_u8);
            counter.count += 1;
            let run_id = counter.count;
            world.write_model(@counter);

            // Generate seed from block timestamp and run ID
            let seed = poseidon_hash_span(
                array![run_id.into(), get_block_timestamp().into(), cat_id.into()].span(),
            );

            // Create run
            let run = Run {
                id: run_id,
                cat_id,
                seed,
                current_node_id: 0,
                floor: 1,
                max_floors: DEFAULT_MAX_FLOORS,
                status: RunStatus::Active,
                score: 0,
                nodes_visited: 0,
            };
            world.write_model(@run);

            // Generate first floor map
            InternalImpl::generate_floor(ref world, run_id, 1, seed);

            world.emit_event(@RunStarted { cat_id, run_id, seed });

            run_id
        }

        fn choose_path(ref self: ContractState, run_id: u64, next_node_id: u8) {
            let mut world = self.world_default();
            let caller = get_caller_address();

            let mut run: Run = world.read_model(run_id);
            assert!(run.status == RunStatus::Active, "run not active");

            // Verify ownership
            let cat: Cat = world.read_model(run.cat_id);
            assert!(cat.owner == caller, "not your cat");

            let current_node: Node = world.read_model((run_id, run.current_node_id));

            // Check connection exists (bit N in connections means connects to node N)
            let mask: u32 = InternalImpl::bit_mask(next_node_id);
            assert!(current_node.connections & mask != 0, "no path to that node");

            // Check target node not already resolved
            let next_node: Node = world.read_model((run_id, next_node_id));
            assert!(!next_node.resolved, "node already visited");

            // Move to next node
            run.current_node_id = next_node_id;
            run.nodes_visited += 1;
            world.write_model(@run);

            world.emit_event(@PathChosen { run_id, from_node: current_node.node_id, to_node: next_node_id });
            world.emit_event(@NodeVisited { run_id, node_id: next_node_id, node_type: next_node.node_type });
        }

        fn abandon_run(ref self: ContractState, run_id: u64) {
            let mut world = self.world_default();
            let caller = get_caller_address();

            let mut run: Run = world.read_model(run_id);
            assert!(run.status == RunStatus::Active, "run not active");

            let mut cat: Cat = world.read_model(run.cat_id);
            assert!(cat.owner == caller, "not your cat");

            // Cat comes home wounded
            run.status = RunStatus::Failed;
            cat.runs_failed += 1;
            cat.hp = cat.hp / 2; // lose half HP as penalty

            world.write_model(@run);
            world.write_model(@cat);

            world.emit_event(@RunCompleted { run_id, cat_id: run.cat_id, score: run.score, status: RunStatus::Failed });
        }

        fn get_run(self: @ContractState, run_id: u64) -> Run {
            let world = self.world_default();
            world.read_model(run_id)
        }

        fn get_node(self: @ContractState, run_id: u64, node_id: u8) -> Node {
            let world = self.world_default();
            world.read_model((run_id, node_id))
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"catacombs")
        }

        // Generate a floor's node map.
        // Layout: Start -> 2-3 branches -> 2-3 middle nodes -> Boss
        // Node 0 = start, nodes 1-5 = encounters, node 6 = boss
        fn generate_floor(ref world: dojo::world::WorldStorage, run_id: u64, floor: u8, seed: felt252) {
            let floor_seed = poseidon_hash_span(array![seed, floor.into()].span());

            // Start node (0) connects to nodes 1, 2, and maybe 3
            let start_connections: u32 = 0b0000_0110; // connects to 1, 2
            let start_node = Node {
                run_id,
                node_id: 0,
                floor,
                node_type: NodeType::Start,
                resolved: false,
                outcome_seed: 0,
                connections: start_connections,
            };
            world.write_model(@start_node);

            // Generate middle nodes (1-5) with types based on seed
            let mut i: u8 = 1;
            while i < NODES_PER_FLOOR - 1 {
                let node_seed = poseidon_hash_span(array![floor_seed, i.into()].span());
                let node_type = Self::seed_to_node_type(node_seed, i);

                // Middle nodes connect forward. Nodes 1-2 connect to 3-4, nodes 3-4 connect to 5, node 5 connects to boss(6)
                let connections: u32 = if i <= 2 {
                    0b0001_1000 // connect to 3, 4
                } else if i <= 4 {
                    0b0010_0000 // connect to 5
                } else {
                    0b0100_0000 // connect to 6 (boss)
                };

                let node = Node {
                    run_id,
                    node_id: i,
                    floor,
                    node_type,
                    resolved: false,
                    outcome_seed: node_seed,
                    connections,
                };
                world.write_model(@node);
                i += 1;
            };

            // Boss node (6) - no outgoing connections
            let boss_node = Node {
                run_id,
                node_id: NODES_PER_FLOOR - 1,
                floor,
                node_type: NodeType::Boss,
                resolved: false,
                outcome_seed: poseidon_hash_span(array![floor_seed, 99].span()),
                connections: 0,
            };
            world.write_model(@boss_node);
        }

        // Deterministically assign node type from seed.
        fn seed_to_node_type(seed: felt252, position: u8) -> NodeType {
            // Use lower bits of seed for type selection
            let seed_u256: u256 = seed.into();
            let type_roll: u8 = (seed_u256 % 100).try_into().unwrap();

            if type_roll < 35 {
                NodeType::Combat
            } else if type_roll < 55 {
                NodeType::Event
            } else if type_roll < 70 {
                NodeType::Treasure
            } else if type_roll < 85 {
                NodeType::Rest
            } else {
                NodeType::Shop
            }
        }

        fn bit_mask(bit: u8) -> u32 {
            let mut result: u32 = 1;
            let mut i: u8 = 0;
            while i < bit {
                result = result * 2;
                i += 1;
            };
            result
        }
    }
}
