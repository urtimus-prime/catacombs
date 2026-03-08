pub mod models {
    pub mod cat;
    pub mod run;
    pub mod node;
    pub mod encounter;
    pub mod item;
}

pub mod systems {
    pub mod cat_actions;
    pub mod run_actions;
    pub mod encounter_actions;
}

#[cfg(test)]
pub mod tests {
    pub mod test_cat;
    pub mod test_run;
}
