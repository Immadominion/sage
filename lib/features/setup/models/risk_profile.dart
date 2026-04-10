// Risk profile definitions for the Setup Wizard.
//
// Maps each profile to concrete bot config values used
// during bot creation.
//
// Two modes of derivation:
//   1. **Static presets** (`riskConfigs`) — absolute SOL values calibrated
//      for a 20 SOL bankroll. Used as fallback and by custom-path screens.
//   2. **Bankroll-relative** (`configForBankroll`) — derives position size
//      and daily loss as a fraction of the actual bankroll so that presets
//      stay meaningful regardless of account size.

import 'dart:math' as math;

enum SetupPath { sageAi, custom }

enum RiskProfile { conservative, balanced, aggressive }

/// Execution mode chosen in the final setup step.
enum ExecutionMode { simulation, live }

/// Risk guardrails — maps a profile to concrete bot parameters.
class RiskConfig {
  final double positionSizeSOL;
  final double maxDailyLossSOL;
  final double profitTargetPercent;
  final double stopLossPercent;
  final int maxConcurrentPositions;
  final int maxHoldTimeMinutes;
  final double entryScoreThreshold;

  const RiskConfig({
    required this.positionSizeSOL,
    required this.maxDailyLossSOL,
    required this.profitTargetPercent,
    required this.stopLossPercent,
    required this.maxConcurrentPositions,
    required this.maxHoldTimeMinutes,
    required this.entryScoreThreshold,
  });
}

/// Defaults for the Custom Strategy entry-condition sliders.
class CustomEntryDefaults {
  final double minVolume24h;
  final double minLiquidity;
  final double maxLiquidity;
  final int defaultBinRange;
  final int cooldownMinutes;

  const CustomEntryDefaults({
    this.minVolume24h = 1000,
    this.minLiquidity = 100,
    this.maxLiquidity = 1000000,
    this.defaultBinRange = 10,
    this.cooldownMinutes = 79,
  });
}

// ═══════════════════════════════════════════════════════════════
// Static presets — calibrated for ~20 SOL reference bankroll
// ═══════════════════════════════════════════════════════════════

const riskConfigs = {
  RiskProfile.conservative: RiskConfig(
    positionSizeSOL: 0.5,
    maxDailyLossSOL: 1.5,
    profitTargetPercent: 5,
    stopLossPercent: 4,
    maxConcurrentPositions: 3,
    maxHoldTimeMinutes: 120,
    entryScoreThreshold: 200,
  ),
  RiskProfile.balanced: RiskConfig(
    positionSizeSOL: 1.0,
    maxDailyLossSOL: 3.0,
    profitTargetPercent: 8,
    stopLossPercent: 6,
    maxConcurrentPositions: 5,
    maxHoldTimeMinutes: 240,
    entryScoreThreshold: 150,
  ),
  RiskProfile.aggressive: RiskConfig(
    positionSizeSOL: 2.0,
    maxDailyLossSOL: 8.0,
    profitTargetPercent: 12,
    stopLossPercent: 10,
    maxConcurrentPositions: 8,
    maxHoldTimeMinutes: 360,
    entryScoreThreshold: 100,
  ),
};

/// Default risk config used across all bot creation surfaces.
/// Screens should reference these instead of hardcoding values.
const kDefaultRiskConfig = RiskConfig(
  positionSizeSOL: 1.0,
  maxDailyLossSOL: 3.0,
  profitTargetPercent: 8,
  stopLossPercent: 6,
  maxConcurrentPositions: 5,
  maxHoldTimeMinutes: 240,
  entryScoreThreshold: 150,
);

/// Default custom entry condition values (FreesolGames-tuned).
const kDefaultCustomEntry = CustomEntryDefaults();

// ═══════════════════════════════════════════════════════════════
// Bankroll-relative config derivation  (Finding #3)
// ═══════════════════════════════════════════════════════════════

/// Minimum viable position size (SOL). Below this the position is
/// too small to offset rent + transaction fees.
const double kMinPositionSOL = 0.05;

/// Minimum daily loss limit (SOL).
const double kMinDailyLossSOL = 0.1;

/// Bankroll-relative ratios per risk profile.
///
/// Derived from the original static presets at a 20 SOL reference:
///   conservative: 0.5/20 = 2.5%, 1.5/20 = 7.5%
///   balanced:     1.0/20 = 5.0%, 3.0/20 = 15.0%
///   aggressive:   2.0/20 = 10%,  8.0/20 = 40%
class _BankrollRatios {
  final double positionPct;
  final double dailyLossPct;
  const _BankrollRatios({
    required this.positionPct,
    required this.dailyLossPct,
  });
}

const _bankrollRatios = {
  RiskProfile.conservative: _BankrollRatios(
    positionPct: 0.025,
    dailyLossPct: 0.075,
  ),
  RiskProfile.balanced: _BankrollRatios(positionPct: 0.05, dailyLossPct: 0.15),
  RiskProfile.aggressive: _BankrollRatios(
    positionPct: 0.10,
    dailyLossPct: 0.40,
  ),
};

/// Derive a [RiskConfig] scaled to [bankrollSOL].
///
/// SOL-denominated parameters (position size, daily loss) scale linearly
/// with the bankroll. Percentage-based and count-based parameters are
/// kept from the base presets. Floors are applied so that values never
/// fall below the minimum viable trading amounts, and max concurrent
/// positions are capped so total theoretical exposure stays ≤ 80% of
/// the bankroll.
RiskConfig configForBankroll(RiskProfile profile, double bankrollSOL) {
  final base = riskConfigs[profile]!;
  final ratios = _bankrollRatios[profile]!;

  final positionSize = math.max(
    kMinPositionSOL,
    bankrollSOL * ratios.positionPct,
  );
  final dailyLoss = math.max(
    kMinDailyLossSOL,
    bankrollSOL * ratios.dailyLossPct,
  );

  // Cap concurrent positions so total exposure stays ≤ 80% of bankroll.
  final maxFromBankroll = positionSize > 0
      ? (bankrollSOL * 0.8 / positionSize).floor().clamp(
          1,
          base.maxConcurrentPositions,
        )
      : base.maxConcurrentPositions;

  return RiskConfig(
    positionSizeSOL: _round2(positionSize),
    maxDailyLossSOL: _round2(dailyLoss),
    profitTargetPercent: base.profitTargetPercent,
    stopLossPercent: base.stopLossPercent,
    maxConcurrentPositions: maxFromBankroll,
    maxHoldTimeMinutes: base.maxHoldTimeMinutes,
    entryScoreThreshold: base.entryScoreThreshold,
  );
}

/// Minimum bankroll (SOL) that produces at least one viable position
/// for [profile]. Below this the position is too small to be useful.
double minimumViableBankroll(RiskProfile profile) {
  final ratios = _bankrollRatios[profile]!;
  // Bankroll where derived position = kMinPositionSOL, plus rent reserve.
  return (kMinPositionSOL / ratios.positionPct) + 0.07;
}

/// Returns `true` when [bankrollSOL] is large enough that at least one
/// position can open and the daily loss limit is meaningful.
bool isBankrollViable(RiskProfile profile, double bankrollSOL) {
  final cfg = configForBankroll(profile, bankrollSOL);
  return cfg.positionSizeSOL < bankrollSOL &&
      cfg.maxDailyLossSOL <= bankrollSOL;
}

double _round2(double v) => (v * 100).roundToDouble() / 100;
