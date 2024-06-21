module scable_vault::scable {

    use std::type_name;
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::balance::{Self, Balance};
    use sui::clock::Clock;
    use protocol::reserve::MarketCoin;
    use protocol::version::Version;
    use protocol::market::Market;
    use protocol::mint;
    use protocol::redeem;
    use scable_vault::math;
    use scable_vault::event;

    // OTW

    public struct SCABLE has drop {}

    // Objects

    public struct ScableTreasury has key {
        id: UID,
        cap: TreasuryCap<SCABLE>,
    }

    public struct ScableVault<phantom T> has key {
        id: UID,
        scoin_balance: Balance<MarketCoin<T>>,
        coin_balance: u64,
    }

    public struct AdminCap has key, store {
        id: UID,
    }

    // Constructor

    fun init(otw: SCABLE, ctx: &mut TxContext) {
        let (cap, metadata) = coin::create_currency(
            otw,
            6,
            b"SCABLE",
            b"SCA-STABLE-LP",
            b"Stablecoin minted by Scallop Stablecoin LP (sUSDC/sUSDT)",
            option::none(),
            ctx,
        );
        transfer::public_transfer(metadata, ctx.sender());
        let treasury = ScableTreasury {
            id: object::new(ctx),
            cap,
        };
        transfer::share_object(treasury);
    }

    // Public Functions

    public fun deposit_scoin<T>(
        vault: &mut ScableVault<T>,
        treasury: &mut ScableTreasury,
        version: &Version,
        market: &mut Market,
        clock: &Clock,
        scoin: Coin<MarketCoin<T>>,
        ctx: &mut TxContext,
    ): Coin<SCABLE> {
        let scoin_amount = scoin.value();
        let coin_amount = math::calc_scoin_to_coin(
            version, market, type_name::get<T>(), clock, scoin_amount,
        );
        vault.coin_balance = coin_balance(vault) + coin_amount;
        event::emit_mint<T>(scoin_amount, coin_amount);
        coin::put(&mut vault.scoin_balance, scoin);
        treasury.cap.mint(coin_amount, ctx)
    }

    public fun deposit_coin<T>(
        vault: &mut ScableVault<T>,
        treasury: &mut ScableTreasury,
        version: &Version,
        market: &mut Market,
        clock: &Clock,
        coin: Coin<T>,
        ctx: &mut TxContext,
    ): Coin<SCABLE> {
        let scoin = mint::mint(
            version, market, coin, clock, ctx,
        );
        deposit_scoin(vault, treasury, version, market, clock, scoin, ctx)
    }

    public fun withdraw_scoin<T>(
        vault: &mut ScableVault<T>,
        treasury: &mut ScableTreasury,
        version: &Version,
        market: &mut Market,
        clock: &Clock,
        scable_coin: Coin<SCABLE>,
        ctx: &mut TxContext,
    ): Coin<MarketCoin<T>> {
        let coin_amount = scable_coin.value();
        let scoin_amount = math::calc_coin_to_scoin(
            version, market, type_name::get<T>(), clock, coin_amount,
        );
        if (coin_balance(vault) < coin_amount) err_vault_balance_not_enough();
        vault.coin_balance = coin_balance(vault) - coin_amount;
        event::emit_burn<T>(coin_amount, scoin_amount);
        treasury.cap.burn(scable_coin);
        coin::take(&mut vault.scoin_balance, scoin_amount, ctx)
    }

    public fun withdraw_coin<T>(
        vault: &mut ScableVault<T>,
        treasury: &mut ScableTreasury,
        version: &Version,
        market: &mut Market,
        clock: &Clock,
        scable_coin: Coin<SCABLE>,
        ctx: &mut TxContext,
    ): Coin<T> {
        let scoin = withdraw_scoin(
            vault, treasury, version, market, clock, scable_coin, ctx,
        );
        redeem::redeem(
            version, market, scoin, clock, ctx,
        )
    }

    // Admin Functions

    public fun create<T>(
        _: &AdminCap,
        ctx: &mut TxContext,
    ) {
        transfer::share_object(ScableVault<T> {
            id: object::new(ctx),
            scoin_balance: balance::zero(),
            coin_balance: 0,
        });
    }

    public fun claim<T>(
        _: &AdminCap,
        vault: &mut ScableVault<T>,
        version: &Version,
        market: &mut Market,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        let scoin_locked_amount = math::calc_coin_to_scoin(
            version, market, type_name::get<T>(), clock, coin_balance(vault),
        );
        let scoin_surplus_amount = scoin_balance(vault) - scoin_locked_amount;
        let scoin_surplus = coin::take(
            &mut vault.scoin_balance, scoin_surplus_amount, ctx,
        );
        redeem::redeem(
            version, market, scoin_surplus, clock, ctx,
        )
    }

    // Getter Functions

    public fun coin_balance<T>(vault: &ScableVault<T>): u64 {
        vault.coin_balance
    }

    public fun scoin_balance<T>(vault: &ScableVault<T>): u64 {
        vault.scoin_balance.value()
    }

    public fun total_supply(treasury: &ScableTreasury): u64 {
        treasury.cap.total_supply()
    }

    // Error Function

    fun err_vault_balance_not_enough() { abort 0 }
}
