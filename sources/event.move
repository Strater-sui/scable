module scable_vault::event {

    use sui::event::emit;
    use sui::coin::Coin;

    // Mint SCABLE

    public struct Mint<phantom T> has copy, drop {
        scoin_amount: u64,
        scable_amount: u64,
    }

    public(package) fun emit_mint<T>(
        scoin_amount: u64,
        scable_amount: u64,
    ) {
        emit(Mint<T> {
            scoin_amount, scable_amount,
        });
    }

    // Burn SCABLE

    public struct Burn<phantom T> has copy, drop {
        scable_amount: u64,
        scoin_amount: u64,
    }

    public(package) fun emit_burn<T>(
        scable_amount: u64,
        scoin_amount: u64,
    ) {
        emit(Burn<T> {
            scable_amount, scoin_amount,
        });
    }

    // Claim underlying stablecoin

    public struct Claim<phantom T> has copy, drop {
        amount: u64,
    }

    public(package) fun emit_claim<T>(coin: &Coin<T>) {
        emit(Claim<T> { amount: coin.value() });
    }
}