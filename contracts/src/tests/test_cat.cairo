#[cfg(test)]
mod tests {
    use dojo::model::{ModelStorage, ModelStorageTest};
    use dojo::world::WorldStorageTrait;
    use dojo_snf_test::{
        spawn_test_world, NamespaceDef, TestResource, ContractDefTrait, ContractDef,
        WorldStorageTestTrait,
    };
    use snforge_std::start_cheat_caller_address;
    use starknet::ContractAddress;

    use catacombs::systems::cat_actions::{ICatActionsDispatcher, ICatActionsDispatcherTrait};
    use catacombs::models::cat::{Cat, CatAppearance, CatCounter, PlayerCats, pack_appearance, unpack_appearance, AppearanceData};
    use catacombs::models::shiny::{ShinyBalance, SUMMON_COST};

    const PLAYER: felt252 = 'PLAYER';
    const PLAYER2: felt252 = 'PLAYER2';
    const REPO_HASH: felt252 = 'gitlab.crux.casa:alice:cat-mew';

    fn default_appearance() -> felt252 {
        pack_appearance(AppearanceData {
            primary_r: 230, primary_g: 140, primary_b: 38,   // orange fur
            stripe_r: 102, stripe_g: 38, stripe_b: 13,       // dark stripes
            eye_r: 77, eye_g: 179, eye_b: 51,                // green eyes
            head_size: 8, eye_size: 8, eye_spacing: 8,       // mid values
            body_width: 8, tail_size: 8, hat_id: 0,          // no hat
        })
    }

    fn namespace_def() -> NamespaceDef {
        NamespaceDef {
            namespace: "catacombs",
            resources: [
                TestResource::Model("Cat"),
                TestResource::Model("CatAppearance"),
                TestResource::Model("CatCounter"),
                TestResource::Model("PlayerCats"),
                TestResource::Model("ShinyBalance"),
                TestResource::Event("CatCreated"),
                TestResource::Event("CatVerified"),
                TestResource::Event("CatLeveledUp"),
                TestResource::Event("ShiniesSpent"),
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

    // Give a player enough SHINIES to create cats in tests
    fn credit_shinies(ref world: dojo::world::WorldStorage, owner: ContractAddress, amount: u64) {
        world.write_model_test(@ShinyBalance { owner, balance: amount });
    }

    fn setup() -> (dojo::world::WorldStorage, ICatActionsDispatcher) {
        let ndef = namespace_def();
        let mut world = spawn_test_world([ndef].span());
        world.sync_perms_and_inits(contract_defs());
        let (contract_address, _) = world.dns(@"cat_actions").unwrap();
        let actions = ICatActionsDispatcher { contract_address };
        start_cheat_caller_address(contract_address, caller());
        // Pre-credit SHINIES for tests
        credit_shinies(ref world, caller(), 100);
        (world, actions)
    }

    #[test]
    fn test_create_cat() {
        let (world, actions) = setup();
        let cat_id = actions.create_cat(REPO_HASH, default_appearance());

        assert!(cat_id == 1, "first cat should be id 1");

        let cat: Cat = world.read_model(cat_id);
        assert!(cat.owner == caller(), "owner should be caller");
        assert!(cat.repo_hash == REPO_HASH, "repo hash should match");
        assert!(cat.hp == 100, "hp should be 100");
        assert!(cat.max_hp == 100, "max_hp should be 100");
        assert!(cat.level == 1, "level should be 1");
        assert!(cat.xp == 0, "xp should be 0");
        assert!(cat.attack >= 3 && cat.attack <= 8, "attack should be 3-8");
        assert!(cat.defense >= 3 && cat.defense <= 8, "defense should be 3-8");
        assert!(cat.speed >= 3 && cat.speed <= 8, "speed should be 3-8");
        assert!(cat.luck >= 3 && cat.luck <= 8, "luck should be 3-8");
        assert!(cat.alive, "cat should be alive");
        assert!(!cat.verified, "cat should not be verified yet");
    }

    #[test]
    fn test_create_multiple_cats() {
        let (world, actions) = setup();
        let cat1 = actions.create_cat(REPO_HASH, default_appearance());
        let cat2 = actions.create_cat('another_repo', default_appearance());

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
        let cat_id = actions.create_cat(REPO_HASH, default_appearance());

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
        let cat_id = actions.create_cat(REPO_HASH, default_appearance());
        let cat = actions.get_cat(cat_id);
        assert!(cat.id == cat_id, "id should match");
        assert!(cat.repo_hash == REPO_HASH, "repo hash should match");
    }

    #[test]
    fn test_different_players_own_separate_cats() {
        let (mut world, actions) = setup();

        // Player 1 creates a cat
        let cat1 = actions.create_cat(REPO_HASH, default_appearance());

        // Switch to player 2 (credit shinies first)
        credit_shinies(ref world, caller2(), 100);
        let (contract_address, _) = world.dns(@"cat_actions").unwrap();
        start_cheat_caller_address(contract_address, caller2());
        let cat2 = actions.create_cat('player2_repo', default_appearance());

        let c1: Cat = world.read_model(cat1);
        let c2: Cat = world.read_model(cat2);
        assert!(c1.owner == caller(), "cat1 owner");
        assert!(c2.owner == caller2(), "cat2 owner");

        let p1_cats: PlayerCats = world.read_model(caller());
        let p2_cats: PlayerCats = world.read_model(caller2());
        assert!(p1_cats.count == 1, "player1 has 1 cat");
        assert!(p2_cats.count == 1, "player2 has 1 cat");
    }

    #[test]
    fn test_appearance_pack_unpack() {
        let data = AppearanceData {
            primary_r: 255, primary_g: 128, primary_b: 0,
            stripe_r: 100, stripe_g: 50, stripe_b: 25,
            eye_r: 10, eye_g: 200, eye_b: 150,
            head_size: 15, eye_size: 0, eye_spacing: 7,
            body_width: 12, tail_size: 3, hat_id: 5,
        };
        let packed = pack_appearance(data);
        let unpacked = unpack_appearance(packed);

        assert!(unpacked.primary_r == 255, "primary_r");
        assert!(unpacked.primary_g == 128, "primary_g");
        assert!(unpacked.primary_b == 0, "primary_b");
        assert!(unpacked.stripe_r == 100, "stripe_r");
        assert!(unpacked.stripe_g == 50, "stripe_g");
        assert!(unpacked.stripe_b == 25, "stripe_b");
        assert!(unpacked.eye_r == 10, "eye_r");
        assert!(unpacked.eye_g == 200, "eye_g");
        assert!(unpacked.eye_b == 150, "eye_b");
        assert!(unpacked.head_size == 15, "head_size");
        assert!(unpacked.eye_size == 0, "eye_size");
        assert!(unpacked.eye_spacing == 7, "eye_spacing");
        assert!(unpacked.body_width == 12, "body_width");
        assert!(unpacked.tail_size == 3, "tail_size");
        assert!(unpacked.hat_id == 5, "hat_id");
    }

    #[test]
    fn test_appearance_stored_on_chain() {
        let (world, actions) = setup();
        let appearance = default_appearance();
        let cat_id = actions.create_cat(REPO_HASH, appearance);

        let stored: CatAppearance = world.read_model(cat_id);
        assert!(stored.packed == appearance, "appearance should be stored");

        let data = unpack_appearance(stored.packed);
        assert!(data.primary_r == 230, "primary_r from chain");
        assert!(data.eye_g == 179, "eye_g from chain");
        assert!(data.hat_id == 0, "hat_id from chain");
    }

    #[test]
    fn test_get_cat_appearance() {
        let (_world, actions) = setup();
        let appearance = default_appearance();
        let cat_id = actions.create_cat(REPO_HASH, appearance);

        let stored = actions.get_cat_appearance(cat_id);
        assert!(stored.packed == appearance, "get_cat_appearance should return stored appearance");
    }

    #[test]
    fn test_create_cat_deducts_shinies() {
        let (world, actions) = setup();
        let before: ShinyBalance = world.read_model(caller());
        assert!(before.balance == 100, "should start with 100 shinies");

        actions.create_cat(REPO_HASH, default_appearance());

        let after: ShinyBalance = world.read_model(caller());
        assert!(after.balance == 100 - SUMMON_COST, "should deduct 10 shinies");
    }

    #[test]
    #[should_panic(expected: "not enough SHINIES")]
    fn test_create_cat_without_shinies_panics() {
        let (mut world, actions) = setup();
        // Zero out balance
        credit_shinies(ref world, caller(), 0);
        actions.create_cat(REPO_HASH, default_appearance());
    }
}
