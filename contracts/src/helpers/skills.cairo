pub const NUM_SKILL_TAGS: u8 = 6;

pub fn skill_tag_at(index: u8) -> felt252 {
    if index == 0 { 'stealth' }
    else if index == 1 { 'combat' }
    else if index == 2 { 'charm' }
    else if index == 3 { 'agility' }
    else if index == 4 { 'arcane' }
    else { 'survival' }
}
