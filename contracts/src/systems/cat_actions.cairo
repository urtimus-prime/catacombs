#[starknet::interface]
pub trait ICatActions<T> {
    // Create a new cat with appearance. appearance is a bit-packed felt252.
    // repo_hash = poseidon("gitlab.crux.casa:{username}:{repo_name}")
    fn create_cat(ref self: T, repo_hash: felt252, appearance: felt252) -> u64;

    // Mark a cat as verified (called by oracle after Mirror SSH verification).
    fn verify_cat(ref self: T, cat_id: u64);

    // Read cat state.
    fn get_cat(self: @T, cat_id: u64) -> catacombs::models::cat::Cat;

    // Read cat appearance.
    fn get_cat_appearance(self: @T, cat_id: u64) -> catacombs::models::cat::CatAppearance;
}

#[dojo::contract]
pub mod cat_actions {
    use super::ICatActions;
    use starknet::get_caller_address;
    use dojo::model::ModelStorage;
    use dojo::event::EventStorage;
    use catacombs::models::cat::{Cat, CatAppearance, CatCounter, PlayerCats, CatCreated, CatVerified};

    #[abi(embed_v0)]
    impl CatActionsImpl of ICatActions<ContractState> {
        fn create_cat(ref self: ContractState, repo_hash: felt252, appearance: felt252) -> u64 {
            let mut world = self.world_default();
            let caller = get_caller_address();

            // Get and increment cat counter
            let mut counter: CatCounter = world.read_model(0_u8);
            counter.count += 1;
            let cat_id = counter.count;
            world.write_model(@counter);

            // Create the cat with base stats
            let cat = Cat {
                id: cat_id,
                owner: caller,
                repo_hash,
                hp: 100,
                max_hp: 100,
                level: 1,
                xp: 0,
                attack: 5,
                defense: 5,
                speed: 5,
                luck: 5,
                alive: true,
                runs_completed: 0,
                runs_failed: 0,
                verified: false,
            };
            world.write_model(@cat);

            // Store appearance
            world.write_model(@CatAppearance { cat_id, packed: appearance });

            // Track player's cat count
            let mut player_cats: PlayerCats = world.read_model(caller);
            player_cats.count += 1;
            world.write_model(@player_cats);

            // Emit event
            world.emit_event(@CatCreated { owner: caller, cat_id, repo_hash });

            cat_id
        }

        fn verify_cat(ref self: ContractState, cat_id: u64) {
            let mut world = self.world_default();

            // TODO: gate this to oracle address only
            let mut cat: Cat = world.read_model(cat_id);
            let zero: starknet::ContractAddress = 0.try_into().unwrap();
            assert!(cat.owner != zero, "cat does not exist");

            cat.verified = true;
            world.write_model(@cat);

            world.emit_event(@CatVerified { cat_id, verified: true });
        }

        fn get_cat(self: @ContractState, cat_id: u64) -> Cat {
            let world = self.world_default();
            world.read_model(cat_id)
        }

        fn get_cat_appearance(self: @ContractState, cat_id: u64) -> CatAppearance {
            let world = self.world_default();
            world.read_model(cat_id)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"catacombs")
        }
    }
}
