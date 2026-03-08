#[cfg(test)]
mod tests {
    use dojo::model::ModelStorage;
    use dojo::world::WorldStorageTrait;
    use dojo_snf_test::{
        spawn_test_world, NamespaceDef, TestResource, ContractDefTrait, ContractDef,
        WorldStorageTestTrait,
    };
    use snforge_std::start_cheat_caller_address;
    use starknet::ContractAddress;

    use catacombs::systems::cat_actions::{ICatActionsDispatcher, ICatActionsDispatcherTrait};
    use catacombs::models::cat::{Cat, CatCounter, PlayerCats};

    const PLAYER: felt252 = 'PLAYER';
    const PLAYER2: felt252 = 'PLAYER2';
    const REPO_HASH: felt252 = 'gitlab.crux.casa:alice:cat-mew';

    fn namespace_def() -> NamespaceDef {
        NamespaceDef {
            namespace: "catacombs",
            resources: [
                TestResource::Model("Cat"),
                TestResource::Model("CatCounter"),
                TestResource::Model("PlayerCats"),
                TestResource::Event("CatCreated"),
                TestResource::Event("CatVerified"),
                TestResource::Event("CatLeveledUp"),
                TestResource::Contract("cat_actions"),
            ]
                .span(),
        }
    }

    fn contract_defs() -> Span<ContractDef> {
        [
            ContractDefTrait::new(@"catacombs", @"cat_actions")
                .with_writer_of([dojo::utils::bytearray_hash(@"catacombs")].span()),
        ]
            .span()
    }

    fn caller() -> ContractAddress {
        PLAYER.try_into().unwrap()
    }

    fn caller2() -> ContractAddress {
        PLAYER2.try_into().unwrap()
    }

    fn setup() -> (dojo::world::WorldStorage, ICatActionsDispatcher) {
        let ndef = namespace_def();
        let mut world = spawn_test_world([ndef].span());
        world.sync_perms_and_inits(contract_defs());
        let (contract_address, _) = world.dns(@"cat_actions").unwrap();
        let actions = ICatActionsDispatcher { contract_address };
        start_cheat_caller_address(contract_address, caller());
        (world, actions)
    }

    #[test]
    fn test_create_cat() {
        let (world, actions) = setup();
        let cat_id = actions.create_cat(REPO_HASH);

        assert!(cat_id == 1, "first cat should be id 1");

        let cat: Cat = world.read_model(cat_id);
        assert!(cat.owner == caller(), "owner should be caller");
        assert!(cat.repo_hash == REPO_HASH, "repo hash should match");
        assert!(cat.hp == 100, "hp should be 100");
        assert!(cat.max_hp == 100, "max_hp should be 100");
        assert!(cat.level == 1, "level should be 1");
        assert!(cat.xp == 0, "xp should be 0");
        assert!(cat.attack == 5, "attack should be 5");
        assert!(cat.defense == 5, "defense should be 5");
        assert!(cat.speed == 5, "speed should be 5");
        assert!(cat.luck == 5, "luck should be 5");
        assert!(cat.alive, "cat should be alive");
        assert!(!cat.verified, "cat should not be verified yet");
    }

    #[test]
    fn test_create_multiple_cats() {
        let (world, actions) = setup();
        let cat1 = actions.create_cat(REPO_HASH);
        let cat2 = actions.create_cat('another_repo');

        assert!(cat1 == 1, "first cat id");
        assert!(cat2 == 2, "second cat id");

        let counter: CatCounter = world.read_model(0_u8);
        assert!(counter.count == 2, "counter should be 2");

        let player_cats: PlayerCats = world.read_model(caller());
        assert!(player_cats.count == 2, "player should have 2 cats");
    }

    #[test]
    fn test_verify_cat() {
        let (world, actions) = setup();
        let cat_id = actions.create_cat(REPO_HASH);

        let cat: Cat = world.read_model(cat_id);
        assert!(!cat.verified, "should not be verified before");

        actions.verify_cat(cat_id);

        let cat: Cat = world.read_model(cat_id);
        assert!(cat.verified, "should be verified after");
    }

    #[test]
    #[should_panic(expected: "cat does not exist")]
    fn test_verify_nonexistent_cat_panics() {
        let (_world, actions) = setup();
        actions.verify_cat(999);
    }

    #[test]
    fn test_get_cat() {
        let (_world, actions) = setup();
        let cat_id = actions.create_cat(REPO_HASH);
        let cat = actions.get_cat(cat_id);
        assert!(cat.id == cat_id, "id should match");
        assert!(cat.repo_hash == REPO_HASH, "repo hash should match");
    }

    #[test]
    fn test_different_players_own_separate_cats() {
        let (world, actions) = setup();

        // Player 1 creates a cat
        let cat1 = actions.create_cat(REPO_HASH);

        // Switch to player 2
        let (contract_address, _) = world.dns(@"cat_actions").unwrap();
        start_cheat_caller_address(contract_address, caller2());
        let cat2 = actions.create_cat('player2_repo');

        let c1: Cat = world.read_model(cat1);
        let c2: Cat = world.read_model(cat2);
        assert!(c1.owner == caller(), "cat1 owner");
        assert!(c2.owner == caller2(), "cat2 owner");

        let p1_cats: PlayerCats = world.read_model(caller());
        let p2_cats: PlayerCats = world.read_model(caller2());
        assert!(p1_cats.count == 1, "player1 has 1 cat");
        assert!(p2_cats.count == 1, "player2 has 1 cat");
    }
}
