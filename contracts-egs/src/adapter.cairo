// Catacombs EGS Adapter
//
// Standalone Starknet contract (not a Dojo system) that bridges between
// the Embeddable Game Standard and the Catacombs Dojo world.
//
// - Implements IMinigameTokenData by cross-contract calling Dojo's get_run
// - Maps EGS token_id (felt252) <-> Catacombs run_id (u64)
// - Players still call Dojo contracts directly for gameplay
// - This adapter is read-only for game state; only write is register_run

#[starknet::interface]
pub trait ICatacombsAdapter<T> {
    /// Bind an EGS token to a Catacombs run. Caller must own the token.
    fn register_run(ref self: T, token_id: felt252, run_id: u64);
    /// Look up which run a token is bound to (0 = unbound).
    fn get_run_for_token(self: @T, token_id: felt252) -> u64;
    /// Look up which token a run is bound to (0 = unbound).
    fn get_token_for_run(self: @T, run_id: u64) -> felt252;
}

#[starknet::contract]
mod CatacombsEgsAdapter {
    use game_components_embeddable_game_standard::minigame::minigame_component::MinigameComponent;
    use game_components_interfaces::minigame::core::{IMINIGAME_ID, IMinigameTokenData};
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use catacombs_egs::run_reader::{
        RunStatus, IRunActionsDispatcher, IRunActionsDispatcherTrait,
    };

    // ── Components ──────────────────────────────────────────────────

    component!(path: MinigameComponent, storage: minigame, event: MinigameEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl MinigameImpl = MinigameComponent::MinigameImpl<ContractState>;
    impl MinigameInternalImpl = MinigameComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    // ── Storage ─────────────────────────────────────────────────────

    #[storage]
    struct Storage {
        #[substorage(v0)]
        minigame: MinigameComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        /// EGS token_id → Catacombs run_id
        token_to_run: Map<felt252, u64>,
        /// Catacombs run_id → EGS token_id
        run_to_token: Map<u64, felt252>,
        /// Address of the deployed Dojo run_actions contract
        run_actions_address: ContractAddress,
    }

    // ── Events ──────────────────────────────────────────────────────

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        MinigameEvent: MinigameComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        RunRegistered: RunRegistered,
    }

    #[derive(Drop, starknet::Event)]
    struct RunRegistered {
        #[key]
        token_id: felt252,
        run_id: u64,
        player: ContractAddress,
    }

    // ── Constructor ─────────────────────────────────────────────────

    #[constructor]
    fn constructor(
        ref self: ContractState,
        run_actions_address: ContractAddress,
        token_address: ContractAddress,
        creator_address: ContractAddress,
    ) {
        // Register SRC5 interface for EGS discovery
        self.src5.register_interface(IMINIGAME_ID);

        // Store the Dojo contract address for cross-contract reads
        self.run_actions_address.write(run_actions_address);

        // Initialize the MinigameComponent (registers with EGS Registry)
        self
            .minigame
            .initializer(
                creator_address,
                "Catacombs",
                "On-chain rogue-like dungeon crawler with persistent cats",
                "Catacombs",
                "Catacombs",
                "Roguelike",
                "", // image URL (can be updated later)
                Option::None, // color
                Option::None, // client_url
                Option::None, // renderer_address
                Option::None, // settings_address
                Option::None, // objectives_address
                token_address,
                Option::None, // royalty_fraction
                Option::None, // skills_address
                1, // version
            );
    }

    // ── IMinigameTokenData ──────────────────────────────────────────

    #[abi(embed_v0)]
    impl MinigameTokenDataImpl of IMinigameTokenData<ContractState> {
        fn score(self: @ContractState, token_id: felt252) -> u64 {
            let run_id = self.token_to_run.read(token_id);
            if run_id == 0 {
                return 0;
            }
            let dispatcher = IRunActionsDispatcher {
                contract_address: self.run_actions_address.read(),
            };
            let run = dispatcher.get_run(run_id);
            run.score.into()
        }

        fn game_over(self: @ContractState, token_id: felt252) -> bool {
            let run_id = self.token_to_run.read(token_id);
            if run_id == 0 {
                return false;
            }
            let dispatcher = IRunActionsDispatcher {
                contract_address: self.run_actions_address.read(),
            };
            let run = dispatcher.get_run(run_id);
            run.status != RunStatus::Active
        }

        fn score_batch(self: @ContractState, token_ids: Span<felt252>) -> Array<u64> {
            let mut results: Array<u64> = array![];
            for token_id in token_ids {
                results.append(self.score(*token_id));
            };
            results
        }

        fn game_over_batch(self: @ContractState, token_ids: Span<felt252>) -> Array<bool> {
            let mut results: Array<bool> = array![];
            for token_id in token_ids {
                results.append(self.game_over(*token_id));
            };
            results
        }
    }

    // ── ICatacombsAdapter ───────────────────────────────────────────

    #[abi(embed_v0)]
    impl CatacombsAdapterImpl of super::ICatacombsAdapter<ContractState> {
        fn register_run(ref self: ContractState, token_id: felt252, run_id: u64) {
            // Verify caller owns the EGS token
            self.minigame.assert_token_ownership(token_id);

            // Ensure this token hasn't already been bound
            assert!(self.token_to_run.read(token_id) == 0, "token already bound");

            // Ensure this run hasn't already been bound
            assert!(self.run_to_token.read(run_id) == 0, "run already bound");

            // EGS lifecycle hooks
            self.minigame.pre_action(token_id);

            // Bind token <-> run
            self.token_to_run.write(token_id, run_id);
            self.run_to_token.write(run_id, token_id);

            self
                .emit(
                    RunRegistered {
                        token_id, run_id, player: get_caller_address(),
                    },
                );

            self.minigame.post_action(token_id);
        }

        fn get_run_for_token(self: @ContractState, token_id: felt252) -> u64 {
            self.token_to_run.read(token_id)
        }

        fn get_token_for_run(self: @ContractState, run_id: u64) -> felt252 {
            self.run_to_token.read(run_id)
        }
    }
}
