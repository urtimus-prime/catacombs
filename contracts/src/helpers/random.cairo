use core::poseidon::poseidon_hash_span;

#[derive(Copy, Drop, Serde)]
pub struct Random {
    pub seed: felt252,
    pub nonce: usize,
}

#[generate_trait]
pub impl RandomImpl of RandomTrait {
    /// Create a new RNG seeded from the transaction hash + a salt.
    /// tx_hash is unknown until block inclusion, preventing precomputation.
    fn new(salt: felt252) -> Random {
        let tx_hash = starknet::get_tx_info().unbox().transaction_hash;
        let seed = poseidon_hash_span([tx_hash, salt].span());
        Random { seed, nonce: 0 }
    }

    /// Create a deterministic RNG from just a seed (no tx_hash).
    fn new_deterministic(seed: felt252) -> Random {
        Random { seed, nonce: 0 }
    }

    /// Advance the RNG and return the next seed.
    fn next_seed(ref self: Random) -> felt252 {
        self.nonce += 1;
        self.seed = poseidon_hash_span([self.seed, self.nonce.into()].span());
        self.seed
    }

    /// Return a random value in [min, max] (inclusive).
    fn between<
        T, +Into<T, u128>, +Into<T, u256>, +TryInto<u128, T>, +PartialOrd<T>, +Copy<T>, +Drop<T>,
    >(
        ref self: Random, min: T, max: T,
    ) -> T {
        let seed: u256 = self.next_seed().into();
        assert(min <= max, 'min must be <= max');
        let range: u128 = max.into() - min.into() + 1;
        let rand = (seed.low % range) + min.into();
        rand.try_into().unwrap()
    }
}
