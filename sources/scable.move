module scable_vault::scable {

    use std::type_name;
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::balance::{Self, Balance};
    use sui::clock::Clock;
    use sui::dynamic_object_field as dof;
    use protocol::reserve::MarketCoin;
    use protocol::version::Version;
    use protocol::market::Market;
    use protocol::mint;
    use protocol::redeem;
    use spool::spool::Spool;
    use spool::rewards_pool::RewardsPool;
    use spool::user;
    use spool::spool_account::SpoolAccount;
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

    public struct SpoolKey<phantom T> has copy, drop, store {}

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
        let admin_cap = AdminCap { id: object::new(ctx) };
        transfer::transfer(admin_cap, ctx.sender());
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
        vault.coin_balance = vault.coin_balance() + coin_amount;
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
        vault.deposit_scoin(treasury, version, market, clock, scoin, ctx)
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
        let scoin = vault.withdraw_scoin(
            treasury, version, market, clock, scable_coin, ctx,
        );
        redeem::redeem(
            version, market, scoin, clock, ctx,
        )
    }

    public fun stake<T>(
        vault: &mut ScableVault<T>,
        spool: &mut Spool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        if (vault.spool_account_exists() && vault.scoin_balance() > 0) {
            let scoin = coin::from_balance(vault.scoin_balance.withdraw_all(), ctx);
            user::stake(spool, vault.spool_account_mut(), scoin, clock, ctx);
        };
    }

    public fun withdraw_scoin_from_spool<T>(
        vault: &mut ScableVault<T>,
        treasury: &mut ScableTreasury,
        version: &Version,
        market: &mut Market,
        clock: &Clock,
        scable_coin: Coin<SCABLE>,
        spool: &mut Spool,
        ctx: &mut TxContext,
    ): Coin<MarketCoin<T>> {
        let coin_amount = scable_coin.value();
        let scoin_amount = math::calc_coin_to_scoin(
            version, market, type_name::get<T>(), clock, coin_amount,
        );
        if (coin_balance(vault) < coin_amount) err_vault_balance_not_enough();
        vault.coin_balance = vault.coin_balance() - coin_amount;
        event::emit_burn<T>(coin_amount, scoin_amount);
        treasury.cap.burn(scable_coin);
        let scoin_balance = vault.scoin_balance();
        if (scoin_amount > scoin_balance) {
            let unstake_amount = scoin_amount - scoin_balance;
            let scoin = user::unstake(spool, vault.spool_account_mut(), unstake_amount, clock, ctx);
            vault.scoin_balance.join(scoin.into_balance());
        };
        coin::take(&mut vault.scoin_balance, scoin_amount, ctx)
    }

    public fun withdraw_coin_from_spool<T>(
        vault: &mut ScableVault<T>,
        treasury: &mut ScableTreasury,
        version: &Version,
        market: &mut Market,
        clock: &Clock,
        scable_coin: Coin<SCABLE>,
        spool: &mut Spool,
        ctx: &mut TxContext,
    ): Coin<T> {
        let scoin = vault.withdraw_scoin_from_spool(
            treasury, version, market, clock, scable_coin, spool, ctx,
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
        let scoin_surplus_amount = vault.scoin_balance() - scoin_locked_amount;
        let scoin_surplus = coin::take(
            &mut vault.scoin_balance, scoin_surplus_amount, ctx,
        );
        let reward = redeem::redeem(
            version, market, scoin_surplus, clock, ctx,
        );
        event::emit_claim(&reward);
        reward
    }

    public fun claim_from_spool<T>(
        cap: &AdminCap,
        vault: &mut ScableVault<T>,
        version: &Version,
        market: &mut Market,
        clock: &Clock,
        spool: &mut Spool,
        ctx: &mut TxContext,
    ): Coin<T> {
        if (!vault.spool_account_exists())
            return claim(cap, vault, version, market, clock, ctx);
        let scoin_locked_amount = math::calc_coin_to_scoin(
            version, market, type_name::get<T>(), clock, coin_balance(vault),
        );
        let scoin_surplus_amount = vault.total_scoin_balance() - scoin_locked_amount;
        let scoin_balance = vault.scoin_balance();
        if (scoin_surplus_amount > scoin_balance) {
            let unstake_amount = scoin_surplus_amount - scoin_balance;
            let scoin = user::unstake(spool, vault.spool_account_mut(), unstake_amount, clock, ctx);
            vault.scoin_balance.join(scoin.into_balance());
        };
        let scoin_surplus = coin::take(
            &mut vault.scoin_balance, scoin_surplus_amount, ctx,
        );
        let reward = redeem::redeem(
            version, market, scoin_surplus, clock, ctx,
        );
        event::emit_claim(&reward);
        reward
        
    }

    public fun add_spool_account<T>(
        _: &AdminCap,
        vault: &mut ScableVault<T>,
        spool: &mut Spool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        dof::add(
            &mut vault.id,
            SpoolKey<T> {},
            user::new_spool_account<MarketCoin<T>>(spool, clock, ctx),
        );
    }

    public fun claim_spool_reward<T, R>(
        _: &AdminCap,
        vault: &mut ScableVault<T>,
        spool: &mut Spool,
        rewarder: &mut RewardsPool<R>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<R> {
        user::redeem_rewards(spool, rewarder, vault.spool_account_mut(), clock, ctx)
    }

    public fun update_spool_points<T>(
        _: &AdminCap,
        vault: &mut ScableVault<T>,
        spool: &mut Spool,
        clock: &Clock,
    ) {
        user::update_points(spool, vault.spool_account_mut(), clock);
    }

    // Getter Functions
    
    public fun total_supply(treasury: &ScableTreasury): u64 {
        treasury.cap.total_supply()
    }

    public fun coin_balance<T>(vault: &ScableVault<T>): u64 {
        vault.coin_balance
    }

    public fun scoin_balance<T>(vault: &ScableVault<T>): u64 {
        vault.scoin_balance.value()
    }

    public fun spool_account_exists<T>(vault: &ScableVault<T>): bool {
        let key = SpoolKey<T> {};
        dof::exists_with_type<SpoolKey<T>, SpoolAccount<MarketCoin<T>>>(&vault.id, key)
    }

    public fun spool_balance<T>(vault: &ScableVault<T>): u64 {
        if (vault.spool_account_exists()) {
            vault.spool_account().stake_amount()
        } else {
            0
        }
    }

    public fun total_scoin_balance<T>(vault: &ScableVault<T>): u64 {
        vault.spool_balance() + vault.scoin_balance()
    }

    fun spool_account<T>(vault: &ScableVault<T>): &SpoolAccount<MarketCoin<T>> {
        if (!vault.spool_account_exists())
            err_spool_account_not_exists();
        dof::borrow(&vault.id, SpoolKey<T> {})
    }

    fun spool_account_mut<T>(vault: &mut ScableVault<T>): &mut SpoolAccount<MarketCoin<T>> {
        if (!vault.spool_account_exists())
            err_spool_account_not_exists();
        dof::borrow_mut(&mut vault.id, SpoolKey<T> {})
    }

    // Error Function

    fun err_vault_balance_not_enough() { abort 0 }
    fun err_spool_account_not_exists() { abort 0 }
}
