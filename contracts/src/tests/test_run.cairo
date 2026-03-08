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
                // Events
                TestResource::Event("CatCreated"),
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
        assert!(run.floor == 1, "should start at floor 1");
        assert!(run.max_floors == 3, "should have 3 floors");
        assert!(run.status == RunStatus::Active, "should be active");
        assert!(run.score == 0, "score should be 0");
        assert!(run.seed != 0, "seed should not be zero");
    }

    #[test]
    fn test_map_generation() {
        let (ctx, _cat_id, run_id) = setup_with_run();

        // Node 0 should be Start
        let node0: Node = ctx.world.read_model((run_id, 0_u8));
        assert!(node0.node_type == NodeType::Start, "node 0 should be Start");
        assert!(node0.floor == 1, "node 0 should be floor 1");
        // Start connects to nodes 1 and 2 (bits 1 and 2 set = 0b110 = 6)
        assert!(node0.connections == 6, "start should connect to 1,2");

        // Node 6 should be Boss
        let node6: Node = ctx.world.read_model((run_id, 6_u8));
        assert!(node6.node_type == NodeType::Boss, "node 6 should be Boss");
        assert!(node6.connections == 0, "boss should have no outgoing connections");

        // Middle nodes should exist and have connections
        let node1: Node = ctx.world.read_model((run_id, 1_u8));
        assert!(node1.connections != 0, "node 1 should have connections");
        assert!(node1.floor == 1, "node 1 should be floor 1");

        let node2: Node = ctx.world.read_model((run_id, 2_u8));
        assert!(node2.connections != 0, "node 2 should have connections");
    }

    #[test]
    fn test_choose_path() {
        let (ctx, _cat_id, run_id) = setup_with_run();

        // From start (0), can go to node 1 or 2
        ctx.run_actions.choose_path(run_id, 1);

        let run: Run = ctx.world.read_model(run_id);
        assert!(run.current_node_id == 1, "should be at node 1");
        assert!(run.nodes_visited == 1, "should have visited 1 node");
    }

    #[test]
    fn test_choose_path_forward() {
        let (ctx, _cat_id, run_id) = setup_with_run();

        // Start -> 1 -> 3 (nodes 1-2 connect to 3-4)
        ctx.run_actions.choose_path(run_id, 1);
        ctx.run_actions.choose_path(run_id, 3);

        let run: Run = ctx.world.read_model(run_id);
        assert!(run.current_node_id == 3, "should be at node 3");
        assert!(run.nodes_visited == 2, "should have visited 2 nodes");
    }

    #[test]
    #[should_panic(expected: "no path to that node")]
    fn test_choose_invalid_path_panics() {
        let (ctx, _cat_id, run_id) = setup_with_run();
        // From start (0), cannot go directly to node 6 (boss)
        ctx.run_actions.choose_path(run_id, 6);
    }

    #[test]
    #[should_panic(expected: "not your cat")]
    fn test_choose_path_wrong_owner_panics() {
        let (ctx, _cat_id, run_id) = setup_with_run();
        let other: ContractAddress = OTHER.try_into().unwrap();
        let (run_addr, _) = ctx.world.dns(@"run_actions").unwrap();
        start_cheat_caller_address(run_addr, other);
        ctx.run_actions.choose_path(run_id, 1);
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

        // Move to node 1 first
        ctx.run_actions.choose_path(run_id, 1);

        ctx.encounter_actions.submit_scenario(run_id, 1, scenario_hash);

        let enc: Encounter = ctx.world.read_model((run_id, 1_u8));
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

        ctx.run_actions.choose_path(run_id, 1);
        ctx.encounter_actions.submit_scenario(run_id, 1, 'dark_tunnel');
        ctx.encounter_actions.resolve_encounter(
            run_id, 1, 'stealth_skill', EncounterResult::Success, 0, 25, 0,
        );

        let enc: Encounter = ctx.world.read_model((run_id, 1_u8));
        assert!(enc.result == EncounterResult::Success, "should be success");
        assert!(enc.skill_hash == 'stealth_skill', "skill hash should match");
        assert!(enc.xp_gained == 25, "xp gained should be 25");

        let cat: Cat = ctx.world.read_model(cat_id);
        assert!(cat.xp == 25, "cat xp should be 25");
        assert!(cat.hp == 100, "cat hp should be unchanged");

        let node: Node = ctx.world.read_model((run_id, 1_u8));
        assert!(node.resolved, "node should be resolved");
    }

    #[test]
    fn test_resolve_encounter_partial() {
        let (ctx, cat_id, run_id) = setup_with_run();

        ctx.run_actions.choose_path(run_id, 1);
        ctx.encounter_actions.submit_scenario(run_id, 1, 'rat_ambush');
        ctx.encounter_actions.resolve_encounter(
            run_id, 1, 'combat_skill', EncounterResult::Partial, -15, 10, 0,
        );

        let cat: Cat = ctx.world.read_model(cat_id);
        assert!(cat.hp == 85, "cat should take 15 damage (100-15=85)");
        assert!(cat.xp == 10, "cat should gain 10 xp");
    }

    #[test]
    fn test_resolve_encounter_failure() {
        let (ctx, cat_id, run_id) = setup_with_run();

        ctx.run_actions.choose_path(run_id, 1);
        ctx.encounter_actions.submit_scenario(run_id, 1, 'spike_trap');
        ctx.encounter_actions.resolve_encounter(
            run_id, 1, 'wrong_skill', EncounterResult::Failure, -30, 0, 0,
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

        ctx.run_actions.choose_path(run_id, 1);
        ctx.encounter_actions.submit_scenario(run_id, 1, 'boss_attack');
        ctx.encounter_actions.resolve_encounter(
            run_id, 1, 'skill', EncounterResult::Failure, -50, 0, 0,
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

        ctx.run_actions.choose_path(run_id, 1);
        ctx.encounter_actions.submit_scenario(run_id, 1, 'treasure_chest');
        ctx.encounter_actions.resolve_encounter(
            run_id, 1, 'lockpick', EncounterResult::Success, 0, 15, 1,
        );

        let enc: Encounter = ctx.world.read_model((run_id, 1_u8));
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

        ctx.run_actions.choose_path(run_id, 1);
        ctx.encounter_actions.submit_scenario(run_id, 1, 'rest_site');
        ctx.encounter_actions.resolve_encounter(
            run_id, 1, 'rest', EncounterResult::Success, 20, 5, 0,
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

        ctx.run_actions.choose_path(run_id, 1);
        ctx.encounter_actions.submit_scenario(run_id, 1, 'fountain');
        ctx.encounter_actions.resolve_encounter(
            run_id, 1, 'drink', EncounterResult::Success, 20, 5, 0,
        );

        let cat: Cat = ctx.world.read_model(cat_id);
        assert!(cat.hp == 100, "hp should cap at max_hp (100)");
    }

    #[test]
    fn test_level_up_on_xp_threshold() {
        let (mut ctx, cat_id, run_id) = setup_with_run();

        // Set cat to 90 xp (needs 100 for level 2 at level 1)
        let mut cat: Cat = ctx.world.read_model(cat_id);
        cat.xp = 90;
        ctx.world.write_model_test(@cat);

        ctx.run_actions.choose_path(run_id, 1);
        ctx.encounter_actions.submit_scenario(run_id, 1, 'easy_fight');
        ctx.encounter_actions.resolve_encounter(
            run_id, 1, 'slash', EncounterResult::Success, 0, 15, 0,
        );

        let cat: Cat = ctx.world.read_model(cat_id);
        assert!(cat.level == 2, "cat should level up to 2");
        assert!(cat.xp == 105, "xp should be 105 (90+15)");
        assert!(cat.max_hp == 105, "max_hp should increase by 5");
        assert!(cat.attack == 6, "attack should increase by 1");
        assert!(cat.defense == 6, "defense should increase by 1");
    }

    #[test]
    #[should_panic(expected: "already resolved")]
    fn test_resolve_twice_panics() {
        let (ctx, _cat_id, run_id) = setup_with_run();

        ctx.run_actions.choose_path(run_id, 1);
        ctx.encounter_actions.submit_scenario(run_id, 1, 'fight');
        ctx.encounter_actions.resolve_encounter(
            run_id, 1, 'skill', EncounterResult::Success, 0, 10, 0,
        );
        ctx.encounter_actions.resolve_encounter(
            run_id, 1, 'skill', EncounterResult::Success, 0, 10, 0,
        );
    }

    #[test]
    fn test_full_path_through_floor() {
        let (ctx, _cat_id, run_id) = setup_with_run();

        // Start(0) -> 1 -> 3 -> 5 -> Boss(6)
        ctx.run_actions.choose_path(run_id, 1);
        ctx.encounter_actions.submit_scenario(run_id, 1, 'enc1');
        ctx.encounter_actions.resolve_encounter(
            run_id, 1, 'skill', EncounterResult::Success, 0, 10, 0,
        );

        ctx.run_actions.choose_path(run_id, 3);
        ctx.encounter_actions.submit_scenario(run_id, 3, 'enc2');
        ctx.encounter_actions.resolve_encounter(
            run_id, 3, 'skill', EncounterResult::Success, 0, 10, 0,
        );

        ctx.run_actions.choose_path(run_id, 5);
        ctx.encounter_actions.submit_scenario(run_id, 5, 'enc3');
        ctx.encounter_actions.resolve_encounter(
            run_id, 5, 'skill', EncounterResult::Success, 0, 10, 0,
        );

        ctx.run_actions.choose_path(run_id, 6);
        ctx.encounter_actions.submit_scenario(run_id, 6, 'boss_fight');
        ctx.encounter_actions.resolve_encounter(
            run_id, 6, 'skill', EncounterResult::Success, -10, 50, 0,
        );

        let run: Run = ctx.world.read_model(run_id);
        // Floor 1 boss beaten, should advance to floor 2
        assert!(run.floor == 2, "should advance to floor 2");
        assert!(run.score == 100, "should gain 100 score for clearing floor");
    }
}
