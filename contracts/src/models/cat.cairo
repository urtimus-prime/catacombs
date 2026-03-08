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

// Cat appearance data, bit-packed into a single felt252.
// Layout (96 bits, LSB first):
//   [0..7]   primary_r    (8 bits, 0-255)
//   [8..15]  primary_g    (8 bits)
//   [16..23] primary_b    (8 bits)
//   [24..31] stripe_r     (8 bits)
//   [32..39] stripe_g     (8 bits)
//   [40..47] stripe_b     (8 bits)
//   [48..55] eye_r        (8 bits)
//   [56..63] eye_g        (8 bits)
//   [64..71] eye_b        (8 bits)
//   [72..75] head_size    (4 bits, 0-15)
//   [76..79] eye_size     (4 bits)
//   [80..83] eye_spacing  (4 bits)
//   [84..87] body_width   (4 bits)
//   [88..91] tail_size    (4 bits)
//   [92..95] hat_id       (4 bits, 0-15)
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct CatAppearance {
    #[key]
    pub cat_id: u64,
    pub packed: felt252,
}

// Unpacked appearance for convenience (not stored on-chain)
#[derive(Copy, Drop, Serde, Debug)]
pub struct AppearanceData {
    pub primary_r: u8,
    pub primary_g: u8,
    pub primary_b: u8,
    pub stripe_r: u8,
    pub stripe_g: u8,
    pub stripe_b: u8,
    pub eye_r: u8,
    pub eye_g: u8,
    pub eye_b: u8,
    pub head_size: u8,
    pub eye_size: u8,
    pub eye_spacing: u8,
    pub body_width: u8,
    pub tail_size: u8,
    pub hat_id: u8,
}

// Bit offsets for packing (cumulative bit positions)
const TWO_POW_8: u256 = 0x100;                 // 2^8
const TWO_POW_16: u256 = 0x10000;              // 2^16
const TWO_POW_24: u256 = 0x1000000;            // 2^24
const TWO_POW_32: u256 = 0x100000000;          // 2^32
const TWO_POW_40: u256 = 0x10000000000;        // 2^40
const TWO_POW_48: u256 = 0x1000000000000;      // 2^48
const TWO_POW_56: u256 = 0x100000000000000;    // 2^56
const TWO_POW_64: u256 = 0x10000000000000000;  // 2^64
const TWO_POW_72: u256 = 0x1000000000000000000;         // 2^72
const TWO_POW_76: u256 = 0x10000000000000000000;        // 2^76
const TWO_POW_80: u256 = 0x100000000000000000000;       // 2^80
const TWO_POW_84: u256 = 0x1000000000000000000000;      // 2^84
const TWO_POW_88: u256 = 0x10000000000000000000000;     // 2^88
const TWO_POW_92: u256 = 0x100000000000000000000000;    // 2^92

const TWO_POW_4_NZ: NonZero<u256> = 0x10;
const TWO_POW_8_NZ: NonZero<u256> = 0x100;

pub fn pack_appearance(data: AppearanceData) -> felt252 {
    assert!(data.head_size <= 15, "head_size overflow");
    assert!(data.eye_size <= 15, "eye_size overflow");
    assert!(data.eye_spacing <= 15, "eye_spacing overflow");
    assert!(data.body_width <= 15, "body_width overflow");
    assert!(data.tail_size <= 15, "tail_size overflow");
    assert!(data.hat_id <= 15, "hat_id overflow");

    let packed: u256 = data.primary_r.into()
        + data.primary_g.into() * TWO_POW_8
        + data.primary_b.into() * TWO_POW_16
        + data.stripe_r.into() * TWO_POW_24
        + data.stripe_g.into() * TWO_POW_32
        + data.stripe_b.into() * TWO_POW_40
        + data.eye_r.into() * TWO_POW_48
        + data.eye_g.into() * TWO_POW_56
        + data.eye_b.into() * TWO_POW_64
        + data.head_size.into() * TWO_POW_72
        + data.eye_size.into() * TWO_POW_76
        + data.eye_spacing.into() * TWO_POW_80
        + data.body_width.into() * TWO_POW_84
        + data.tail_size.into() * TWO_POW_88
        + data.hat_id.into() * TWO_POW_92;

    packed.try_into().unwrap()
}

pub fn unpack_appearance(packed: felt252) -> AppearanceData {
    let mut v: u256 = packed.into();
    let (rest, primary_r) = DivRem::div_rem(v, TWO_POW_8_NZ);
    let (rest, primary_g) = DivRem::div_rem(rest, TWO_POW_8_NZ);
    let (rest, primary_b) = DivRem::div_rem(rest, TWO_POW_8_NZ);
    let (rest, stripe_r) = DivRem::div_rem(rest, TWO_POW_8_NZ);
    let (rest, stripe_g) = DivRem::div_rem(rest, TWO_POW_8_NZ);
    let (rest, stripe_b) = DivRem::div_rem(rest, TWO_POW_8_NZ);
    let (rest, eye_r) = DivRem::div_rem(rest, TWO_POW_8_NZ);
    let (rest, eye_g) = DivRem::div_rem(rest, TWO_POW_8_NZ);
    let (rest, eye_b) = DivRem::div_rem(rest, TWO_POW_8_NZ);
    let (rest, head_size) = DivRem::div_rem(rest, TWO_POW_4_NZ);
    let (rest, eye_size) = DivRem::div_rem(rest, TWO_POW_4_NZ);
    let (rest, eye_spacing) = DivRem::div_rem(rest, TWO_POW_4_NZ);
    let (rest, body_width) = DivRem::div_rem(rest, TWO_POW_4_NZ);
    let (rest, tail_size) = DivRem::div_rem(rest, TWO_POW_4_NZ);
    let (_, hat_id) = DivRem::div_rem(rest, TWO_POW_4_NZ);

    AppearanceData {
        primary_r: primary_r.try_into().unwrap(),
        primary_g: primary_g.try_into().unwrap(),
        primary_b: primary_b.try_into().unwrap(),
        stripe_r: stripe_r.try_into().unwrap(),
        stripe_g: stripe_g.try_into().unwrap(),
        stripe_b: stripe_b.try_into().unwrap(),
        eye_r: eye_r.try_into().unwrap(),
        eye_g: eye_g.try_into().unwrap(),
        eye_b: eye_b.try_into().unwrap(),
        head_size: head_size.try_into().unwrap(),
        eye_size: eye_size.try_into().unwrap(),
        eye_spacing: eye_spacing.try_into().unwrap(),
        body_width: body_width.try_into().unwrap(),
        tail_size: tail_size.try_into().unwrap(),
        hat_id: hat_id.try_into().unwrap(),
    }
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
