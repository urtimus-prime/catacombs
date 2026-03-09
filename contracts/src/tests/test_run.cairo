#[cfg(test)]
mod tests {
    use dojo::model::{ModelStorage, ModelStorageTest};
    use dojo::world::WorldStorageTrait;
    use dojo_snf_test::{
        spawn_test_world, NamespaceDef, TestResource, ContractDefTrait, ContractDef,
        WorldStorageTestTrait,
    };
    use snforge_std::{start_cheat_caller_address, start_cheat_block_timestamp_global};
    use starknet::ContractAddress;

    use catacombs::systems::cat_actions::{ICatActionsDispatcher, ICatActionsDispatcherTrait};
    use catacombs::systems::run_actions::{IRunActionsDispatcher, IRunActionsDispatcherTrait};
    use catacombs::systems::encounter_actions::{
        IEncounterActionsDispatcher, IEncounterActionsDispatcherTrait,
    };
    use catacombs::models::cat::Cat;
    use catacombs::models::run::{Run, RunStatus};
    use catacombs::models::node::{Node, NodeType};
    use catacombs::models::encounter::{Encounter, EncounterResult};
    use catacombs::models::shiny::ShinyBalance;

    const PLAYER: felt252 = 'PLAYER';
    const OTHER: felt252 = 'OTHER';
    const REPO_HASH: felt252 = 'gitlab.crux.casa:alice:cat-mew';

    fn namespace_def() -> NamespaceDef {
        NamespaceDef {
            namespace: "catacombs",
            resources: [
                // Models
                TestResource::Model("Cat"),
                TestResource::Model("CatAppearance"),
                TestResource::Model("CatCounter"),
                TestResource::Model("PlayerCats"),
                TestResource::Model("Run"),
                TestResource::Model("RunCounter"),
                TestResource::Model("Node"),
                TestResource::Model("Encounter"),
                TestResource::Model("Item"),
                TestResource::Model("CatInventory"),
                TestResource::Model("ShinyBalance"),
                // Events
                TestResource::Event("CatCreated"),
                TestResource::Event("ShiniesSpent"),
                TestResource::Event("CatVerified"),
                TestResource::Event("CatLeveledUp"),
                TestResource::Event("RunStarted"),
                TestResource::Event("RunCompleted"),
                TestResource::Event("NodeVisited"),
                TestResource::Event("PathChosen"),
                TestResource::Event("ScenarioGenerated"),
                TestResource::Event("EncounterResolved"),
                TestResource::Event("ItemFound"),
                TestResource::Event("ItemEquipped"),
                // Contracts
                TestResource::Contract("cat_actions"),
                TestResource::Contract("run_actions"),
                TestResource::Contract("encounter_actions"),
            ]
                .span(),
        }
    }

    fn contract_defs() -> Span<ContractDef> {
        [
            ContractDefTrait::new(@"catacombs", @"cat_actions")
                .with_writer_of([dojo::utils::bytearray_hash(@"catacombs")].span()),
            ContractDefTrait::new(@"catacombs", @"run_actions")
                .with_writer_of([dojo::utils::bytearray_hash(@"catacombs")].span()),
            ContractDefTrait::new(@"catacombs", @"encounter_actions")
                .with_writer_of([dojo::utils::bytearray_hash(@"catacombs")].span()),
        ]
            .span()
    }

    fn caller() -> ContractAddress {
        PLAYER.try_into().unwrap()
    }

    #[derive(Drop)]
    struct TestContext {
        world: dojo::world::WorldStorage,
        cat_actions: ICatActionsDispatcher,
        run_actions: IRunActionsDispatcher,
        encounter_actions: IEncounterActionsDispatcher,
    }

    fn setup() -> TestContext {
        let ndef = namespace_def();
        let mut world = spawn_test_world([ndef].span());
        world.sync_perms_and_inits(contract_defs());

        let (cat_addr, _) = world.dns(@"cat_actions").unwrap();
        let (run_addr, _) = world.dns(@"run_actions").unwrap();
        let (enc_addr, _) = world.dns(@"encounter_actions").unwrap();

        start_cheat_caller_address(cat_addr, caller());
        start_cheat_caller_address(run_addr, caller());
        start_cheat_caller_address(enc_addr, caller());

        // Pre-credit SHINIES for cat creation
        world.write_model_test(@ShinyBalance { owner: caller(), balance: 100 });

        TestContext {
            world,
            cat_actions: ICatActionsDispatcher { contract_address: cat_addr },
            run_actions: IRunActionsDispatcher { contract_address: run_addr },
            encounter_actions: IEncounterActionsDispatcher { contract_address: enc_addr },
        }
    }

    fn setup_with_cat() -> (TestContext, u64) {
        let ctx = setup();
        let cat_id = ctx.cat_actions.create_cat(REPO_HASH, 0);
        (ctx, cat_id)
    }

    fn setup_with_run() -> (TestContext, u64, u64) {
        start_cheat_block_timestamp_global(1000);
        let (ctx, cat_id) = setup_with_cat();
        let run_id = ctx.run_actions.start_run(cat_id);
        (ctx, cat_id, run_id)
    }

    /// Helper: find a connected node from current node
    fn find_connected_node(ctx: @TestContext, run_id: u64, from_node_id: u8) -> u8 {
        let node: Node = (*ctx.world).read_model((run_id, from_node_id));
        let connections = node.connections;
        // Find the lowest set bit
        let mut i: u8 = 0;
        loop {
            if i >= 26 {
                break 0_u8;
            }
            let mut mask: u32 = 1;
            let mut j: u8 = 0;
            loop {
                if j >= i {
                    break;
                }
                mask = mask * 2;
                j += 1;
            };
            if connections & mask != 0 {
                break i;
            }
            i += 1;
        }
    }

    // ==================== Run Tests ====================

    #[test]
    fn test_start_run() {
        start_cheat_block_timestamp_global(1000);
        let (ctx, cat_id) = setup_with_cat();
        let run_id = ctx.run_actions.start_run(cat_id);

        assert!(run_id == 1, "first run should be id 1");

        let run: Run = ctx.world.read_model(run_id);
        assert!(run.cat_id == cat_id, "run cat_id should match");
        assert!(run.current_node_id == 0, "should start at node 0");
        assert!(run.status == RunStatus::Active, "should be active");
        assert!(run.score == 0, "score should be 0");
        assert!(run.seed != 0, "seed should not be zero");

        // Node 0 should be Start
        let node0: Node = ctx.world.read_model((run_id, 0_u8));
        assert!(node0.node_type == NodeType::Start, "node 0 should be Start");
        assert!(node0.column == 0, "node 0 should be column 0");

        // Node 25 should be Boss
        let node25: Node = ctx.world.read_model((run_id, 25_u8));
        assert!(node25.node_type == NodeType::Boss, "node 25 should be Boss");
        assert!(node25.column == 9, "node 25 should be column 9");

        // node_count should be reasonable (10 cols: 1 + 8*[1-3] + 1 = min 10, max 26)
        assert!(run.node_count >= 10, "node_count should be at least 10");
        assert!(run.node_count <= 26, "node_count should be at most 26");
    }

    #[test]
    fn test_map_connectivity() {
        let (ctx, _cat_id, run_id) = setup_with_run();

        // Start node should have connections
        let node0: Node = ctx.world.read_model((run_id, 0_u8));
        assert!(node0.connections != 0, "start should have connections");

        // Boss node should have no outgoing connections
        let node25: Node = ctx.world.read_model((run_id, 25_u8));
        assert!(node25.connections == 0, "boss should have no outgoing connections");

        // Every connected node should exist with a valid type
        // Check that we can reach at least one node from start
        let first_target = find_connected_node(@ctx, run_id, 0);
        assert!(first_target > 0, "start should connect to a middle node");
        assert!(first_target <= 3, "start should connect to col 1 (nodes 1-3)");

        let target_node: Node = ctx.world.read_model((run_id, first_target));
        assert!(target_node.column == 1, "first target should be in column 1");
    }

    #[test]
    fn test_choose_path() {
        let (ctx, _cat_id, run_id) = setup_with_run();

        // Find a valid first move from start
        let first_target = find_connected_node(@ctx, run_id, 0);

        ctx.run_actions.choose_path(run_id, first_target);

        let run: Run = ctx.world.read_model(run_id);
        assert!(run.current_node_id == first_target, "should be at chosen node");
        assert!(run.nodes_visited == 1, "should have visited 1 node");
    }

    #[test]
    fn test_choose_path_forward() {
        let (ctx, _cat_id, run_id) = setup_with_run();

        // Navigate two steps forward
        let first_target = find_connected_node(@ctx, run_id, 0);
        ctx.run_actions.choose_path(run_id, first_target);

        let second_target = find_connected_node(@ctx, run_id, first_target);
        ctx.run_actions.choose_path(run_id, second_target);

        let run: Run = ctx.world.read_model(run_id);
        assert!(run.current_node_id == second_target, "should be at second node");
        assert!(run.nodes_visited == 2, "should have visited 2 nodes");
    }

    #[test]
    #[should_panic(expected: "no path to that node")]
    fn test_choose_invalid_path_panics() {
        let (ctx, _cat_id, run_id) = setup_with_run();
        // From start (0), cannot go directly to node 25 (boss)
        ctx.run_actions.choose_path(run_id, 25);
    }

    #[test]
    #[should_panic(expected: "not your cat")]
    fn test_choose_path_wrong_owner_panics() {
        let (ctx, _cat_id, run_id) = setup_with_run();
        let other: ContractAddress = OTHER.try_into().unwrap();
        let (run_addr, _) = ctx.world.dns(@"run_actions").unwrap();
        start_cheat_caller_address(run_addr, other);
        let first_target = find_connected_node(@ctx, run_id, 0);
        ctx.run_actions.choose_path(run_id, first_target);
    }

    #[test]
    fn test_abandon_run() {
        let (ctx, cat_id, run_id) = setup_with_run();
        ctx.run_actions.abandon_run(run_id);

        let run: Run = ctx.world.read_model(run_id);
        assert!(run.status == RunStatus::Failed, "run should be failed");

        let cat: Cat = ctx.world.read_model(cat_id);
        assert!(cat.hp == 50, "cat should lose half HP (100/2=50)");
        assert!(cat.runs_failed == 1, "runs_failed should be 1");
    }

    #[test]
    #[should_panic(expected: "run not active")]
    fn test_abandon_twice_panics() {
        let (ctx, _cat_id, run_id) = setup_with_run();
        ctx.run_actions.abandon_run(run_id);
        ctx.run_actions.abandon_run(run_id);
    }

    #[test]
    #[should_panic(expected: "cat is wounded, needs rest")]
    fn test_start_run_wounded_cat_panics() {
        start_cheat_block_timestamp_global(1000);
        let (mut ctx, cat_id) = setup_with_cat();

        // Wound the cat by setting HP to 0
        let mut cat: Cat = ctx.world.read_model(cat_id);
        cat.hp = 0;
        ctx.world.write_model_test(@cat);

        ctx.run_actions.start_run(cat_id);
    }

    // ==================== Encounter Tests ====================

    #[test]
    fn test_submit_scenario() {
        let (ctx, _cat_id, run_id) = setup_with_run();
        let scenario_hash: felt252 = 'a_dark_tunnel_appears';

        // Move to first connected node
        let first_target = find_connected_node(@ctx, run_id, 0);
        ctx.run_actions.choose_path(run_id, first_target);

        ctx.encounter_actions.submit_scenario(run_id, first_target, scenario_hash);

        let enc: Encounter = ctx.world.read_model((run_id, first_target));
        assert!(enc.scenario_hash == scenario_hash, "scenario hash should match");
        assert!(enc.result == EncounterResult::Pending, "should be pending");
    }

    #[test]
    #[should_panic(expected: "not at this node")]
    fn test_submit_scenario_wrong_node_panics() {
        let (ctx, _cat_id, run_id) = setup_with_run();
        // Still at node 0, trying to submit for node 1
        ctx.encounter_actions.submit_scenario(run_id, 1, 'scenario');
    }

    #[test]
    fn test_resolve_encounter_success() {
        let (ctx, cat_id, run_id) = setup_with_run();

        let first_target = find_connected_node(@ctx, run_id, 0);
        ctx.run_actions.choose_path(run_id, first_target);
        ctx.encounter_actions.submit_scenario(run_id, first_target, 'dark_tunnel');
        ctx.encounter_actions.resolve_encounter(
            run_id, first_target, 'stealth_skill', EncounterResult::Success, 0, 25, 0,
        );

        let enc: Encounter = ctx.world.read_model((run_id, first_target));
        assert!(enc.result == EncounterResult::Success, "should be success");
        assert!(enc.skill_hash == 'stealth_skill', "skill hash should match");
        assert!(enc.xp_gained == 25, "xp gained should be 25");

        let cat: Cat = ctx.world.read_model(cat_id);
        assert!(cat.xp == 25, "cat xp should be 25");
        assert!(cat.hp == 100, "cat hp should be unchanged");

        let node: Node = ctx.world.read_model((run_id, first_target));
        assert!(node.resolved, "node should be resolved");
    }

    #[test]
    fn test_resolve_encounter_partial() {
        let (ctx, cat_id, run_id) = setup_with_run();

        let first_target = find_connected_node(@ctx, run_id, 0);
        ctx.run_actions.choose_path(run_id, first_target);
        ctx.encounter_actions.submit_scenario(run_id, first_target, 'rat_ambush');
        ctx.encounter_actions.resolve_encounter(
            run_id, first_target, 'combat_skill', EncounterResult::Partial, -15, 10, 0,
        );

        let cat: Cat = ctx.world.read_model(cat_id);
        assert!(cat.hp == 85, "cat should take 15 damage (100-15=85)");
        assert!(cat.xp == 10, "cat should gain 10 xp");
    }

    #[test]
    fn test_resolve_encounter_failure() {
        let (ctx, cat_id, run_id) = setup_with_run();

        let first_target = find_connected_node(@ctx, run_id, 0);
        ctx.run_actions.choose_path(run_id, first_target);
        ctx.encounter_actions.submit_scenario(run_id, first_target, 'spike_trap');
        ctx.encounter_actions.resolve_encounter(
            run_id, first_target, 'wrong_skill', EncounterResult::Failure, -30, 0, 0,
        );

        let cat: Cat = ctx.world.read_model(cat_id);
        assert!(cat.hp == 70, "cat should take 30 damage (100-30=70)");
        assert!(cat.xp == 0, "cat should gain no xp on failure");
    }

    #[test]
    fn test_resolve_encounter_cat_down() {
        let (mut ctx, cat_id, run_id) = setup_with_run();

        // Weaken the cat first
        let mut cat: Cat = ctx.world.read_model(cat_id);
        cat.hp = 10;
        ctx.world.write_model_test(@cat);

        let first_target = find_connected_node(@ctx, run_id, 0);
        ctx.run_actions.choose_path(run_id, first_target);
        ctx.encounter_actions.submit_scenario(run_id, first_target, 'boss_attack');
        ctx.encounter_actions.resolve_encounter(
            run_id, first_target, 'skill', EncounterResult::Failure, -50, 0, 0,
        );

        let cat: Cat = ctx.world.read_model(cat_id);
        assert!(cat.hp == 1, "cat should survive with 1 hp");
        assert!(cat.runs_failed == 1, "runs_failed should increment");

        let run: Run = ctx.world.read_model(run_id);
        assert!(run.status == RunStatus::Failed, "run should be failed");
    }

    #[test]
    fn test_resolve_encounter_with_loot() {
        let (ctx, cat_id, run_id) = setup_with_run();

        let first_target = find_connected_node(@ctx, run_id, 0);
        ctx.run_actions.choose_path(run_id, first_target);
        ctx.encounter_actions.submit_scenario(run_id, first_target, 'treasure_chest');
        ctx.encounter_actions.resolve_encounter(
            run_id, first_target, 'lockpick', EncounterResult::Success, 0, 15, 1,
        );

        let enc: Encounter = ctx.world.read_model((run_id, first_target));
        assert!(enc.loot_id == 1, "loot_id should be 1");

        // Check item was created
        use catacombs::models::item::{Item, CatInventory};
        let inventory: CatInventory = ctx.world.read_model(cat_id);
        assert!(inventory.count == 1, "inventory should have 1 item");
    }

    #[test]
    fn test_resolve_encounter_healing() {
        let (mut ctx, cat_id, run_id) = setup_with_run();

        // Damage the cat first
        let mut cat: Cat = ctx.world.read_model(cat_id);
        cat.hp = 60;
        ctx.world.write_model_test(@cat);

        let first_target = find_connected_node(@ctx, run_id, 0);
        ctx.run_actions.choose_path(run_id, first_target);
        ctx.encounter_actions.submit_scenario(run_id, first_target, 'rest_site');
        ctx.encounter_actions.resolve_encounter(
            run_id, first_target, 'rest', EncounterResult::Success, 20, 5, 0,
        );

        let cat: Cat = ctx.world.read_model(cat_id);
        assert!(cat.hp == 80, "cat should heal to 80 (60+20)");
    }

    #[test]
    fn test_healing_capped_at_max_hp() {
        let (mut ctx, cat_id, run_id) = setup_with_run();

        // Cat at 95 hp
        let mut cat: Cat = ctx.world.read_model(cat_id);
        cat.hp = 95;
        ctx.world.write_model_test(@cat);

        let first_target = find_connected_node(@ctx, run_id, 0);
        ctx.run_actions.choose_path(run_id, first_target);
        ctx.encounter_actions.submit_scenario(run_id, first_target, 'fountain');
        ctx.encounter_actions.resolve_encounter(
            run_id, first_target, 'drink', EncounterResult::Success, 20, 5, 0,
        );

        let cat: Cat = ctx.world.read_model(cat_id);
        assert!(cat.hp == 100, "hp should cap at max_hp (100)");
    }

    #[test]
    fn test_level_up_on_xp_threshold() {
        let (mut ctx, cat_id, run_id) = setup_with_run();

        // Record initial random stats before level-up
        let cat_before: Cat = ctx.world.read_model(cat_id);
        let atk_before = cat_before.attack;
        let def_before = cat_before.defense;
        let max_hp_before = cat_before.max_hp;

        // Set cat to 90 xp (needs 100 for level 2 at level 1)
        let mut cat: Cat = ctx.world.read_model(cat_id);
        cat.xp = 90;
        ctx.world.write_model_test(@cat);

        let first_target = find_connected_node(@ctx, run_id, 0);
        ctx.run_actions.choose_path(run_id, first_target);
        ctx.encounter_actions.submit_scenario(run_id, first_target, 'easy_fight');
        ctx.encounter_actions.resolve_encounter(
            run_id, first_target, 'slash', EncounterResult::Success, 0, 15, 0,
        );

        let cat: Cat = ctx.world.read_model(cat_id);
        assert!(cat.level == 2, "cat should level up to 2");
        assert!(cat.xp == 105, "xp should be 105 (90+15)");
        assert!(cat.max_hp == max_hp_before + 5, "max_hp should increase by 5");
        assert!(cat.attack == atk_before + 1, "attack should increase by 1");
        assert!(cat.defense == def_before + 1, "defense should increase by 1");
    }

    #[test]
    #[should_panic(expected: "already resolved")]
    fn test_resolve_twice_panics() {
        let (ctx, _cat_id, run_id) = setup_with_run();

        let first_target = find_connected_node(@ctx, run_id, 0);
        ctx.run_actions.choose_path(run_id, first_target);
        ctx.encounter_actions.submit_scenario(run_id, first_target, 'fight');
        ctx.encounter_actions.resolve_encounter(
            run_id, first_target, 'skill', EncounterResult::Success, 0, 10, 0,
        );
        ctx.encounter_actions.resolve_encounter(
            run_id, first_target, 'skill', EncounterResult::Success, 0, 10, 0,
        );
    }

    #[test]
    fn test_full_run_to_boss() {
        let (ctx, cat_id, run_id) = setup_with_run();

        // Traverse the map from start to boss by following connections
        let mut current: u8 = 0;
        let mut steps: u8 = 0;

        loop {
            // Find next connected node
            let next = find_connected_node(@ctx, run_id, current);
            assert!(next > current, "should always move forward");

            ctx.run_actions.choose_path(run_id, next);

            // Check if we reached the boss
            let next_node: Node = ctx.world.read_model((run_id, next));
            if next_node.node_type == NodeType::Boss {
                current = next;
                break;
            }

            // Resolve encounter at this non-boss node
            ctx.encounter_actions.submit_scenario(run_id, next, 'encounter');
            ctx.encounter_actions.resolve_encounter(
                run_id, next, 'skill', EncounterResult::Success, 0, 10, 0,
            );

            current = next;
            steps += 1;

            // Safety: should never take more than 9 steps (cols 1-9)
            assert!(steps <= 9, "too many steps");
        };

        // Now at boss node, resolve boss encounter
        ctx.encounter_actions.submit_scenario(run_id, current, 'boss_fight');
        ctx.encounter_actions.resolve_encounter(
            run_id, current, 'skill', EncounterResult::Success, -10, 50, 0,
        );

        let run: Run = ctx.world.read_model(run_id);
        assert!(run.status == RunStatus::Completed, "run should be completed");
        assert!(run.score == 100, "should gain 100 score for boss");

        let cat: Cat = ctx.world.read_model(cat_id);
        assert!(cat.runs_completed == 1, "runs_completed should be 1");
    }
}
