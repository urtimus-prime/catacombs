pub const NUM_SKILL_TAGS: u8 = 6;

pub fn skill_tag_at(index: u8) -> felt252 {
    if index == 0 { 'stealth' }
    else if index == 1 { 'combat' }
    else if index == 2 { 'charm' }
    else if index == 3 { 'agility' }
    else if index == 4 { 'arcane' }
    else { 'survival' }
}

// Map a skill tag to the relevant cat stat value.
// combat/survival -> attack, stealth/agility -> speed, charm -> luck, arcane -> defense
use catacombs::models::cat::Cat;

pub fn stat_for_skill(cat: @Cat, skill_tag: felt252) -> u8 {
    if skill_tag == 'combat' || skill_tag == 'survival' {
        *cat.attack
    } else if skill_tag == 'stealth' || skill_tag == 'agility' {
        *cat.speed
    } else if skill_tag == 'charm' {
        *cat.luck
    } else {
        // arcane or unknown
        *cat.defense
    }
}
