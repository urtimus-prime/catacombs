use starknet::ContractAddress;

// A cat is a persistent character owned by a player.
// Its identity (soul, quirks, skills) lives in a git repo on gitlab.crux.casa.
// On-chain we store stats, progression, and the repo binding.

#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Cat {
    #[key]
    pub id: u64,
    pub owner: ContractAddress,
    // Hash of "provider:username:repo" for Mirror verification
    pub repo_hash: felt252,
    pub hp: u8,
    pub max_hp: u8,
    pub level: u16,
    pub xp: u32,
    pub attack: u8,
    pub defense: u8,
    pub speed: u8,
    pub luck: u8,
    pub alive: bool,
    pub runs_completed: u16,
    pub runs_failed: u16,
    pub verified: bool,
}

// Tracks the next cat ID to mint.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct CatCounter {
    #[key]
    pub world_id: u8, // always 0, singleton
    pub count: u64,
}

// Tracks which cats a player owns.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct PlayerCats {
    #[key]
    pub owner: ContractAddress,
    pub count: u8,
}

// Events

#[derive(Copy, Drop, Serde)]
#[dojo::event]
pub struct CatCreated {
    #[key]
    pub owner: ContractAddress,
    pub cat_id: u64,
    pub repo_hash: felt252,
}

#[derive(Copy, Drop, Serde)]
#[dojo::event]
pub struct CatVerified {
    #[key]
    pub cat_id: u64,
    pub verified: bool,
}

#[derive(Copy, Drop, Serde)]
#[dojo::event]
pub struct CatLeveledUp {
    #[key]
    pub cat_id: u64,
    pub new_level: u16,
}
