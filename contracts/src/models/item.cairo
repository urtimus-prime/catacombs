// Items are loot found during runs.
// They persist on the cat across runs.
// Simple slot-based equipment system for MVP.

#[derive(Serde, Copy, Drop, Introspect, Debug, PartialEq, DojoStore)]
pub enum ItemSlot {
    None,
    Head,
    Body,
    Paws,
    Tail,
    Collar,
}

impl ItemSlotDefault of Default<ItemSlot> {
    fn default() -> ItemSlot {
        ItemSlot::None
    }
}

#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Item {
    #[key]
    pub cat_id: u64,
    #[key]
    pub item_id: u8,
    pub name_hash: felt252, // hash of item name string
    pub slot: ItemSlot,
    pub power: u8,
    pub equipped: bool,
}

// Tracks how many items a cat has.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct CatInventory {
    #[key]
    pub cat_id: u64,
    pub count: u8,
}

// Events

#[derive(Copy, Drop, Serde)]
#[dojo::event]
pub struct ItemFound {
    #[key]
    pub cat_id: u64,
    pub item_id: u8,
    pub name_hash: felt252,
    pub slot: ItemSlot,
    pub power: u8,
}

#[derive(Copy, Drop, Serde)]
#[dojo::event]
pub struct ItemEquipped {
    #[key]
    pub cat_id: u64,
    pub item_id: u8,
    pub slot: ItemSlot,
}
