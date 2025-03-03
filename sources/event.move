module scable_vault::event {

    use sui::event::emit;
    use sui::balance::Balance;
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

    // Mint SCABLE by Navi

    public struct MintByNavi<phantom T> has copy, drop {
        amount: u64,
    }

    public(package) fun emit_mint_by_navi<T>(
        amount: u64,
    ) {
        emit(MintByNavi<T> { amount });
    }

    // Burn SCABLE by Navi

    public struct BurnByNavi<phantom T> has copy, drop {
        amount: u64,
    }

    public(package) fun emit_burn_by_navi<T>(
        amount: u64,
    ) {
        emit(BurnByNavi<T> { amount });
    }

    // Claim Navi Reward

    public struct ClaimFromNavi<phantom T> has copy, drop {
        amount: u64,
    }

    public(package) fun emit_claim_from_navi<T>(balance: &Balance<T>) {
        emit(ClaimFromNavi<T> { amount: balance.value() });
    }
}