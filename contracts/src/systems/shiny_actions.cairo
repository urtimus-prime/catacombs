#[starknet::interface]
pub trait IShinyActions<T> {
    // Buy SHINIES with STRK. 1 SHINY = 1 STRK (1e18 wei).
    // Caller must approve this contract to spend `amount` STRK first.
    fn buy_shinies(ref self: T, amount: u64);

    // Read a player's SHINIES balance.
    fn get_balance(self: @T, owner: starknet::ContractAddress) -> u64;
}

#[dojo::contract]
pub mod shiny_actions {
    use super::IShinyActions;
    use starknet::{get_caller_address, get_contract_address, ContractAddress};
    use dojo::model::ModelStorage;
    use dojo::event::EventStorage;
    use catacombs::models::shiny::{ShinyBalance, ShiniesBought};
    use catacombs::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};

    // STRK token address (same on Katana, Sepolia, and Mainnet)
    const STRK_ADDRESS: felt252 =
        0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d;

    // 1 STRK = 1e18 wei
    const ONE_STRK: u256 = 1_000_000_000_000_000_000;

    #[abi(embed_v0)]
    impl ShinyActionsImpl of IShinyActions<ContractState> {
        fn buy_shinies(ref self: ContractState, amount: u64) {
            assert!(amount > 0, "amount must be > 0");

            let mut world = self.world_default();
            let caller = get_caller_address();
            let this = get_contract_address();

            // Transfer STRK from caller to this contract
            let strk_addr: ContractAddress = STRK_ADDRESS.try_into().unwrap();
            let strk = IERC20Dispatcher { contract_address: strk_addr };
            let strk_cost: u256 = amount.into() * ONE_STRK;

            let success = strk.transfer_from(caller, this, strk_cost);
            assert!(success, "STRK transfer failed");

            // Credit SHINIES
            let mut bal: ShinyBalance = world.read_model(caller);
            bal.balance += amount;
            world.write_model(@bal);

            world.emit_event(@ShiniesBought { buyer: caller, amount, strk_paid: strk_cost });
        }

        fn get_balance(self: @ContractState, owner: ContractAddress) -> u64 {
            let world = self.world_default();
            let bal: ShinyBalance = world.read_model(owner);
            bal.balance
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"catacombs")
        }
    }
}
