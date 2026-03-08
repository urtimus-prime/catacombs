use starknet::ContractAddress;

// SHINIES balance for each player.
// In-game currency used to summon cats.

#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct ShinyBalance {
    #[key]
    pub owner: ContractAddress,
    pub balance: u64,
}

// Cost in SHINIES to summon a cat.
pub const SUMMON_COST: u64 = 10;

// Events

#[derive(Copy, Drop, Serde)]
#[dojo::event]
pub struct ShiniesBought {
    #[key]
    pub buyer: ContractAddress,
    pub amount: u64,
    pub strk_paid: u256,
}

#[derive(Copy, Drop, Serde)]
#[dojo::event]
pub struct ShiniesSpent {
    #[key]
    pub spender: ContractAddress,
    pub amount: u64,
    pub reason: felt252,
}
