# Trading Engine Audit — Fix Tiers

> **Date**: April 11, 2026
> **Scope**: sage-backend trading engine, simulation math, ML pipeline, wallet architecture
> **Context**: Deep audit of how profit targets flow through the system, simulation accuracy vs real DLMM, and what makes the bot actually smart.

---

## Key Findings

### 1. Profit Target Is Only an Exit Trigger
- `profitTargetPercent` does NOT influence pool selection, bin range, strategy type, position sizing, or expected hold duration
- It is checked in `checkExitConditions()` as: `pnlPercent >= position.profitTargetPercent`
- Entry decisions are entirely driven by market scoring (volume/liquidity/fee/momentum) and/or ML predictions

### 2. P&L Excludes Fees
- Exit P&L = `((currentPrice - entryPrice) / entryPrice) * 100`
- DLMM LP profit is primarily from **fees**, not price movement
- A position earning 5% fees but down 2% in price shows -2% (should be +3%)

### 3. Simulation Gaps vs Real DLMM
- Dynamic fee model (volatility accumulator) not modeled
- Only the active bin earns fees — our sim spreads fees across all bins
- No liquidity share tracking (assumes 100% of bin fees go to us)
- No protocol fee deduction (5% cut)
- No out-of-range detection

### 4. Always Spot Strategy
- `enterPosition()` always uses `StrategyType.Spot` regardless of market conditions
- Curve and BidAsk distribution code exists in `dlmm-sim-math.ts` but is never used

### 5. ML Model Trains on 1,600 Samples
- Current XGBoost model uses 12 features from Dune aggregates
- Old-faithful-extractor can provide 50–200M labeled samples with 100+ features

---

## Fix Tiers (Priority Order)

### Tier 1 — Fix What's Broken (High Impact, Moderate Effort)

| # | Fix | File(s) | Why |
|---|-----|---------|-----|
| 1.1 | **Include fees in exit P&L** | `trading-engine.ts` checkExitConditions | LP profit is primarily fees. Ignoring them causes premature stop-loss exits on profitable positions. |
| 1.2 | **Active-bin-only fee accrual** | `dlmm-sim-math.ts`, `simulation-executor.ts` | Only the bin where current price sits earns fees. We spread fees across all bins, over-estimating by 5–15× for wide positions. |
| 1.3 | **Model liquidity share** | `simulation-executor.ts`, `market-data.ts` | We assume 100% of bin fees go to us. Real share = our liquidity / total bin liquidity. For popular pools this could be 0.01%. |
| 1.4 | **Protocol fee deduction** | `dlmm-sim-math.ts` | Meteora takes 5% of swap fees. Our sim doesn't deduct this. |

### Tier 2 — Make Profit Target Actually Smart (Medium Effort)

| # | Fix | File(s) | Why |
|---|-----|---------|-----|
| 2.1 | **Fee-inclusive P&L for exit decisions** | `trading-engine.ts` | Change from `(currentPrice - entryPrice) / entryPrice` to `(lpValueNow - lpValueEntry) / lpValueEntry` including accumulated fees. |
| 2.2 | **Adaptive strategy selection** | `trading-engine.ts` enterPosition | Higher profit target → wider bin range + BidAsk shape. Lower target → tight Spot for quick fee capture. |
| 2.3 | **Expected hold duration planning** | `trading-engine.ts` enterPosition | If target is 10% and pool APR is 50% (fees), bot needs ~7h in-range. Pick bin ranges likely to stay in-range that long. |

### Tier 3 — Train Better ML (Highest Long-Term Impact)

| # | Fix | File(s) | Why |
|---|-----|---------|-----|
| 3.1 | **Old Faithful → training pipeline** | `ml-pipeline/`, new scripts | Aggregate Swap/AddLiquidity/RemoveLiquidity into per-pool-per-hour windows. Label by actual LP return. Train on 50M+ vs 1,600. |
| 3.2 | **Per-pool regime classification** | `ml-features.ts`, model training | Use Swap bin traversals to classify pools as trending/ranging/volatile. Different strategies optimal for each. |
| 3.3 | **LP crowding signal** | `ml-features.ts` | High AddLiquidity clustering = lower per-LP fee share. Avoid crowded positions. |

### Tier 4 — Portfolio Intelligence

| # | Fix | File(s) | Why |
|---|-----|---------|-----|
| 4.1 | **Cross-position risk management** | `trading-engine.ts` | If 3 positions are all SOL/USDC, they're correlated. Diversify across token pairs. |
| 4.2 | **Collective P&L awareness** | `trading-engine.ts` | Portfolio-level profit target instead of only per-trade. |
| 4.3 | **Dynamic position sizing** | `trading-engine.ts` enterPosition | Kelly criterion or confidence-weighted sizing from ML predictions. |

---

## Wallet Architecture Status

The wallet system is **fully implemented** but disabled by a frontend feature flag:

| Component | Status | Notes |
|-----------|--------|-------|
| AES-256-GCM keypair encryption | ✅ Done | `crypto-utils.ts` |
| Per-bot keypair generation | ✅ Done | Created in `POST /bot/create` |
| Server-side signing (open/close positions) | ✅ Done | `bot-keypair-executor.ts` |
| Deposit flow (user signs client-side) | ✅ Done | `wallet.ts` prepare-deposit |
| Withdrawal flow (server signs) | ✅ Done | `wallet.ts` POST withdraw |
| Fund isolation (each bot = own wallet) | ✅ Done | Separate keypairs |
| Frontend kill switch | ❌ Blocking | `kLiveTradingEnabled = false` in `live_trading_flags.dart` |
| Backend network guard | ⚠️ Requires mainnet | `SOLANA_NETWORK !== "mainnet-beta"` blocks live mode |

### To Enable Live Trading
1. Set `kLiveTradingEnabled = true` in Flutter
2. Deploy backend with `SOLANA_NETWORK=mainnet-beta` and mainnet RPC
3. Ensure `MASTER_ENCRYPTION_KEY` is set in production env

### Security Model
- Private keys encrypted at rest (AES-256-GCM, env-based master key)
- Decrypted only in-memory during active trading
- Zeroized on bot stop (`keypair.secretKey.fill(0)`)
- Withdrawal whitelist = user's SIWS-verified wallet address
- EmergencyStop + CircuitBreaker enforce risk limits on-chain actions
