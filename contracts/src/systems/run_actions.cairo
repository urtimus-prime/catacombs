use catacombs::models::run::Run;
use catacombs::models::node::Node;

#[starknet::interface]
pub trait IRunActions<T> {
    fn start_run(ref self: T, cat_id: u64) -> u64;
    fn choose_path(ref self: T, run_id: u64, next_node_id: u8);
    fn abandon_run(ref self: T, run_id: u64);
    fn get_run(self: @T, run_id: u64) -> Run;
    fn get_node(self: @T, run_id: u64, node_id: u8) -> Node;
}

#[dojo::contract]
pub mod run_actions {
    use super::IRunActions;
    use starknet::{get_caller_address, get_block_timestamp};
    use core::poseidon::poseidon_hash_span;
    use core::dict::{Felt252Dict, Felt252DictTrait};
    use dojo::model::ModelStorage;
    use dojo::event::EventStorage;
    use catacombs::models::cat::Cat;
    use catacombs::models::run::{Run, RunStatus, RunCounter, RunStarted, RunCompleted};
    use catacombs::models::node::{Node, NodeType, NodeVisited, PathChosen};
    use catacombs::helpers::random::RandomTrait;
    use catacombs::helpers::skills::skill_tag_at;

    #[abi(embed_v0)]
    impl RunActionsImpl of IRunActions<ContractState> {
        fn start_run(ref self: ContractState, cat_id: u64) -> u64 {
            let mut world = self.world_default();
            let caller = get_caller_address();

            let cat: Cat = world.read_model(cat_id);
            assert!(cat.owner == caller, "not your cat");
            assert!(cat.alive, "cat is dead");
            assert!(cat.hp > 0, "cat is wounded, needs rest");

            let mut counter: RunCounter = world.read_model(0_u8);
            counter.count += 1;
            let run_id = counter.count;
            world.write_model(@counter);

            let seed = poseidon_hash_span(
                array![run_id.into(), get_block_timestamp().into(), cat_id.into()].span(),
            );

            let node_count = InternalImpl::generate_map(ref world, run_id, seed);

            let run = Run {
                id: run_id,
                cat_id,
                seed,
                current_node_id: 0,
                node_count,
                status: RunStatus::Active,
                score: 0,
                nodes_visited: 0,
            };
            world.write_model(@run);
            world.emit_event(@RunStarted { cat_id, run_id, seed });
            run_id
        }

        fn choose_path(ref self: ContractState, run_id: u64, next_node_id: u8) {
            let mut world = self.world_default();
            let caller = get_caller_address();

            let mut run: Run = world.read_model(run_id);
            assert!(run.status == RunStatus::Active, "run not active");

            let cat: Cat = world.read_model(run.cat_id);
            assert!(cat.owner == caller, "not your cat");

            let current_node: Node = world.read_model((run_id, run.current_node_id));
            let mask: u32 = InternalImpl::bit_mask(next_node_id);
            assert!(current_node.connections & mask != 0, "no path to that node");

            let next_node: Node = world.read_model((run_id, next_node_id));
            assert!(!next_node.resolved, "node already visited");

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

            run.status = RunStatus::Failed;
            cat.runs_failed += 1;
            cat.hp = cat.hp / 2;

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

        fn node_id_for(col: u8, row: u8) -> u8 {
            if col == 0 {
                0
            } else if col == 9 {
                25
            } else {
                (col - 1) * 3 + 1 + row
            }
        }

        fn u8_to_felt(v: u8) -> felt252 {
            v.into()
        }

        fn generate_map(ref world: dojo::world::WorldStorage, run_id: u64, seed: felt252) -> u8 {
            let mut rng = RandomTrait::new_deterministic(seed);

            // Phase 1: Column widths
            let pinch_col: u8 = rng.between(3_u8, 6_u8);

            let mut widths: Felt252Dict<u8> = Default::default();
            widths.insert(Self::u8_to_felt(0), 1);
            let mut c: u8 = 1;
            loop {
                if c > 8 {
                    break;
                }
                if c == pinch_col {
                    widths.insert(Self::u8_to_felt(c), 1);
                } else {
                    let w: u8 = rng.between(2_u8, 3_u8);
                    widths.insert(Self::u8_to_felt(c), w);
                }
                c += 1;
            };
            widths.insert(Self::u8_to_felt(9), 1);

            // Phase 2: Build connections
            let mut connections: Felt252Dict<u32> = Default::default();
            let mut has_incoming: Felt252Dict<u8> = Default::default();

            let mut c: u8 = 0;
            loop {
                if c > 8 {
                    break;
                }
                let cur_width: u8 = widths.get(Self::u8_to_felt(c));
                let next_width: u8 = widths.get(Self::u8_to_felt(c + 1));
                let is_pinch: bool = cur_width == 1 && c > 0;

                let mut r: u8 = 0;
                loop {
                    if r >= cur_width {
                        break;
                    }
                    let src_id = Self::node_id_for(c, r);
                    let mut conn: u32 = connections.get(Self::u8_to_felt(src_id));

                    if is_pinch {
                        let mut tr: u8 = 0;
                        loop {
                            if tr >= next_width {
                                break;
                            }
                            let tgt_id = Self::node_id_for(c + 1, tr);
                            conn = conn | Self::bit_mask(tgt_id);
                            has_incoming.insert(Self::u8_to_felt(tgt_id), 1);
                            tr += 1;
                        };
                    } else {
                        let num_connections: u8 = rng.between(1_u8, 2_u8);
                        let min_target: u8 = if r == 0 { 0 } else { r - 1 };
                        let max_target: u8 = if r + 1 >= next_width { next_width - 1 } else { r + 1 };
                        let primary_row: u8 = if r >= next_width { next_width - 1 } else { r };
                        let primary_id = Self::node_id_for(c + 1, primary_row);
                        conn = conn | Self::bit_mask(primary_id);
                        has_incoming.insert(Self::u8_to_felt(primary_id), 1);

                        if num_connections >= 2 && min_target < max_target {
                            if primary_row > min_target {
                                let sec_id = Self::node_id_for(c + 1, min_target);
                                conn = conn | Self::bit_mask(sec_id);
                                has_incoming.insert(Self::u8_to_felt(sec_id), 1);
                            } else if primary_row < max_target {
                                let sec_id = Self::node_id_for(c + 1, max_target);
                                conn = conn | Self::bit_mask(sec_id);
                                has_incoming.insert(Self::u8_to_felt(sec_id), 1);
                            }
                        }
                    }

                    connections.insert(Self::u8_to_felt(src_id), conn);
                    r += 1;
                };

                // Fixup: ensure every node in c+1 has at least 1 incoming
                let mut tr: u8 = 0;
                loop {
                    if tr >= next_width {
                        break;
                    }
                    let tgt_id = Self::node_id_for(c + 1, tr);
                    if has_incoming.get(Self::u8_to_felt(tgt_id)) == 0 {
                        let src_row: u8 = if tr >= cur_width { cur_width - 1 } else { tr };
                        let src_id = Self::node_id_for(c, src_row);
                        let mut conn: u32 = connections.get(Self::u8_to_felt(src_id));
                        conn = conn | Self::bit_mask(tgt_id);
                        connections.insert(Self::u8_to_felt(src_id), conn);
                        has_incoming.insert(Self::u8_to_felt(tgt_id), 1);
                    }
                    tr += 1;
                };

                c += 1;
            };

            // Phase 3: Node types
            let mut node_types: Felt252Dict<u8> = Default::default();
            node_types.insert(0, 0); // Start
            node_types.insert(25, 5); // Boss

            let mut has_treasure: bool = false;
            let mut has_rest: bool = false;
            let mut last_ce_id: u8 = 0; // last combat/event id
            let mut second_last_ce_id: u8 = 0;

            let mut c: u8 = 1;
            loop {
                if c > 8 {
                    break;
                }
                let w: u8 = widths.get(Self::u8_to_felt(c));
                let mut r: u8 = 0;
                loop {
                    if r >= w {
                        break;
                    }
                    let nid = Self::node_id_for(c, r);
                    let roll: u8 = rng.between(0_u8, 99_u8);
                    let ntype: u8 = if roll < 40 {
                        1
                    } else if roll < 70 {
                        4
                    } else if roll < 85 {
                        2
                    } else {
                        3
                    };

                    if ntype == 2 { has_treasure = true; }
                    if ntype == 3 { has_rest = true; }
                    if ntype == 1 || ntype == 4 {
                        second_last_ce_id = last_ce_id;
                        last_ce_id = nid;
                    }

                    node_types.insert(Self::u8_to_felt(nid), ntype);
                    r += 1;
                };
                c += 1;
            };

            // Guarantees
            if !has_treasure && last_ce_id > 0 {
                node_types.insert(Self::u8_to_felt(last_ce_id), 2);
            }
            if !has_rest {
                if second_last_ce_id > 0 {
                    node_types.insert(Self::u8_to_felt(second_last_ce_id), 3);
                } else if last_ce_id > 0 {
                    let mut found: bool = false;
                    let mut cc: u8 = 1;
                    loop {
                        if cc > 8 || found {
                            break;
                        }
                        let ww: u8 = widths.get(Self::u8_to_felt(cc));
                        let mut rr: u8 = 0;
                        loop {
                            if rr >= ww || found {
                                break;
                            }
                            let candidate = Self::node_id_for(cc, rr);
                            let ct: u8 = node_types.get(Self::u8_to_felt(candidate));
                            if ct == 1 || ct == 4 {
                                node_types.insert(Self::u8_to_felt(candidate), 3);
                                found = true;
                            }
                            rr += 1;
                        };
                        cc += 1;
                    };
                }
            }

            // Phase 4: Write nodes
            let mut total_nodes: u8 = 0;

            // Start node
            let start_node = Node {
                run_id,
                node_id: 0,
                column: 0,
                row: 0,
                node_type: NodeType::Start,
                resolved: false,
                outcome_seed: 0,
                skill_tag_1: 0,
                skill_tag_2: 0,
                difficulty: 0,
                connections: connections.get(0),
            };
            world.write_model(@start_node);
            total_nodes += 1;

            // Middle nodes
            let mut c: u8 = 1;
            loop {
                if c > 8 {
                    break;
                }
                let w: u8 = widths.get(Self::u8_to_felt(c));
                let mut r: u8 = 0;
                loop {
                    if r >= w {
                        break;
                    }
                    let nid = Self::node_id_for(c, r);
                    let nt_code: u8 = node_types.get(Self::u8_to_felt(nid));
                    let node_type = Self::code_to_node_type(nt_code);
                    let node_seed = poseidon_hash_span(array![seed, Self::u8_to_felt(nid)].span());

                    let is_passive = nt_code == 2 || nt_code == 3;

                    let difficulty: u8 = if is_passive {
                        0
                    } else {
                        let base: u8 = (c - 1) / 3 + 1;
                        let max_diff: u8 = if base + 1 > 3 { 3 } else { base + 1 };
                        rng.between(base, max_diff)
                    };

                    let skill_tag_1: felt252 = if is_passive {
                        0
                    } else {
                        let idx: u8 = rng.between(0_u8, 5_u8);
                        skill_tag_at(idx)
                    };

                    let skill_tag_2: felt252 = if is_passive {
                        0
                    } else {
                        let has_second: u8 = rng.between(0_u8, 1_u8);
                        if has_second == 1 {
                            let idx2: u8 = rng.between(0_u8, 4_u8);
                            let tag2 = skill_tag_at(idx2);
                            if tag2 == skill_tag_1 {
                                skill_tag_at(5)
                            } else {
                                tag2
                            }
                        } else {
                            0
                        }
                    };

                    let node = Node {
                        run_id,
                        node_id: nid,
                        column: c,
                        row: r,
                        node_type,
                        resolved: false,
                        outcome_seed: node_seed,
                        skill_tag_1,
                        skill_tag_2,
                        difficulty,
                        connections: connections.get(Self::u8_to_felt(nid)),
                    };
                    world.write_model(@node);
                    total_nodes += 1;

                    r += 1;
                };
                c += 1;
            };

            // Boss node
            let boss_node = Node {
                run_id,
                node_id: 25,
                column: 9,
                row: 0,
                node_type: NodeType::Boss,
                resolved: false,
                outcome_seed: poseidon_hash_span(array![seed, 99].span()),
                skill_tag_1: 0,
                skill_tag_2: 0,
                difficulty: 3,
                connections: 0,
            };
            world.write_model(@boss_node);
            total_nodes += 1;

            total_nodes
        }

        fn code_to_node_type(code: u8) -> NodeType {
            if code == 0 { NodeType::Start }
            else if code == 1 { NodeType::Combat }
            else if code == 2 { NodeType::Treasure }
            else if code == 3 { NodeType::Rest }
            else if code == 4 { NodeType::Event }
            else { NodeType::Boss }
        }

        fn bit_mask(bit: u8) -> u32 {
            let mut result: u32 = 1;
            let mut i: u8 = 0;
            loop {
                if i >= bit {
                    break;
                }
                result = result * 2;
                i += 1;
            };
            result
        }
    }
}
