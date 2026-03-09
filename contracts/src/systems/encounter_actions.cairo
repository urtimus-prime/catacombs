use catacombs::models::encounter::Encounter;

#[starknet::interface]
pub trait IEncounterActions<T> {
    // Oracle submits the scenario hash after LLM generates it from the node seed.
    fn submit_scenario(ref self: T, run_id: u64, node_id: u8, scenario_hash: felt252);

    // Oracle resolves the encounter after evaluating skill vs scenario.
    // This is called by the oracle service after:
    //   1. Reading the cat's skill from their gitlab repo
    //   2. Evaluating it against the generated scenario via LLM
    //   3. Determining the outcome
    fn resolve_encounter(
        ref self: T,
        run_id: u64,
        node_id: u8,
        skill_hash: felt252,
        result: catacombs::models::encounter::EncounterResult,
        hp_delta: i8,
        xp_gained: u16,
        loot_id: u8,
    );

    // Read encounter state.
    fn get_encounter(self: @T, run_id: u64, node_id: u8) -> Encounter;
}

#[dojo::contract]
pub mod encounter_actions {
    use super::IEncounterActions;
    use dojo::model::ModelStorage;
    use dojo::event::EventStorage;
    use catacombs::models::cat::Cat;
    use catacombs::models::run::{Run, RunStatus, RunCompleted};
    use catacombs::models::node::{Node, NodeType};
    use catacombs::models::encounter::{
        Encounter, EncounterResult, ScenarioGenerated, EncounterResolved,
    };
    use catacombs::models::item::{Item, ItemSlot, ItemFound, CatInventory};

    // XP needed to level up: level * 100
    const XP_PER_LEVEL: u32 = 100;

    #[abi(embed_v0)]
    impl EncounterActionsImpl of IEncounterActions<ContractState> {
        fn submit_scenario(
            ref self: ContractState, run_id: u64, node_id: u8, scenario_hash: felt252,
        ) {
            let mut world = self.world_default();

            // TODO: gate to oracle address
            let run: Run = world.read_model(run_id);
            assert!(run.status == RunStatus::Active, "run not active");
            assert!(run.current_node_id == node_id, "not at this node");

            let encounter = Encounter {
                run_id,
                node_id,
                scenario_hash,
                skill_hash: 0,
                result: EncounterResult::Pending,
                hp_delta: 0,
                xp_gained: 0,
                loot_id: 0,
            };
            world.write_model(@encounter);

            world.emit_event(@ScenarioGenerated { run_id, node_id, scenario_hash });
        }

        fn resolve_encounter(
            ref self: ContractState,
            run_id: u64,
            node_id: u8,
            skill_hash: felt252,
            result: EncounterResult,
            hp_delta: i8,
            xp_gained: u16,
            loot_id: u8,
        ) {
            let mut world = self.world_default();

            // TODO: gate to oracle address
            let mut run: Run = world.read_model(run_id);
            assert!(run.status == RunStatus::Active, "run not active");

            let mut encounter: Encounter = world.read_model((run_id, node_id));
            assert!(encounter.scenario_hash != 0, "no scenario submitted");
            assert!(encounter.result == EncounterResult::Pending, "already resolved");

            // Update encounter
            encounter.skill_hash = skill_hash;
            encounter.result = result;
            encounter.hp_delta = hp_delta;
            encounter.xp_gained = xp_gained;
            encounter.loot_id = loot_id;
            world.write_model(@encounter);

            // Apply effects to cat
            let mut cat: Cat = world.read_model(run.cat_id);

            // Apply HP change
            if hp_delta < 0 {
                let damage: u8 = (-hp_delta).try_into().unwrap();
                if damage >= cat.hp {
                    cat.hp = 0;
                } else {
                    cat.hp -= damage;
                }
            } else {
                let heal: u8 = hp_delta.try_into().unwrap();
                cat.hp = if cat.hp + heal > cat.max_hp {
                    cat.max_hp
                } else {
                    cat.hp + heal
                };
            }

            // Apply XP
            cat.xp += xp_gained.into();

            // Check level up
            let xp_needed: u32 = cat.level.into() * XP_PER_LEVEL;
            if cat.xp >= xp_needed {
                cat.level += 1;
                cat.max_hp += 5;
                // Stats grow on level up
                cat.attack += 1;
                cat.defense += 1;
            }

            // Mark node resolved
            let mut node: Node = world.read_model((run_id, node_id));
            node.resolved = true;
            world.write_model(@node);

            // Handle loot
            if loot_id > 0 {
                let mut inventory: CatInventory = world.read_model(cat.id);
                inventory.count += 1;

                let item = Item {
                    cat_id: cat.id,
                    item_id: loot_id,
                    name_hash: 0, // set by oracle
                    slot: ItemSlot::None,
                    power: 1,
                    equipped: false,
                };
                world.write_model(@item);
                world.write_model(@inventory);

                world.emit_event(
                    @ItemFound {
                        cat_id: cat.id,
                        item_id: loot_id,
                        name_hash: 0,
                        slot: ItemSlot::None,
                        power: 1,
                    },
                );
            }

            // Check if cat is down
            if cat.hp == 0 {
                run.status = RunStatus::Failed;
                cat.runs_failed += 1;
                cat.hp = 1; // cat survives but barely — wounded

                world.emit_event(
                    @RunCompleted {
                        run_id, cat_id: run.cat_id, score: run.score, status: RunStatus::Failed,
                    },
                );
            }

            // Check if boss defeated with success -> run completed
            if node.node_type == NodeType::Boss && result != EncounterResult::Failure {
                run.score += 100;
                run.status = RunStatus::Completed;
                cat.runs_completed += 1;

                world.emit_event(
                    @RunCompleted {
                        run_id,
                        cat_id: run.cat_id,
                        score: run.score,
                        status: RunStatus::Completed,
                    },
                );
            }

            world.write_model(@cat);
            world.write_model(@run);

            world.emit_event(
                @EncounterResolved { run_id, node_id, result, hp_delta, xp_gained, loot_id },
            );
        }

        fn get_encounter(self: @ContractState, run_id: u64, node_id: u8) -> Encounter {
            let world = self.world_default();
            world.read_model((run_id, node_id))
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"catacombs")
        }
    }
}
