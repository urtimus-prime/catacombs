pub mod models {
    pub mod cat;
    pub mod run;
    pub mod node;
    pub mod encounter;
    pub mod item;
    pub mod shiny;
}

pub mod interfaces {
    pub mod erc20;
}

pub mod helpers {
    pub mod random;
}

pub mod systems {
    pub mod cat_actions;
    pub mod run_actions;
    pub mod encounter_actions;
    pub mod shiny_actions;
}

#[cfg(test)]
pub mod tests {
    pub mod test_cat;
    pub mod test_run;
}
