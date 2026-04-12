import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:sage/core/config/live_trading_flags.dart';
import 'package:sage/core/config/simulation_defaults.dart';
import 'package:sage/core/models/bot.dart';
import 'package:sage/core/models/strategy.dart';
import 'package:sage/core/repositories/bot_repository.dart';
import 'package:sage/core/theme/app_colors.dart';
import 'package:sage/core/theme/app_theme.dart';
import 'package:sage/core/utils/bot_validators.dart';
import 'package:sage/features/setup/models/risk_profile.dart';
import 'package:sage/shared/widgets/deposit_sheet.dart';
import 'package:sage/shared/widgets/sage_bottom_sheet.dart';

import 'package:sage/features/automate/presentation/widgets/bot_form_fields.dart';
import 'package:sage/features/automate/presentation/widgets/strategy_preset_selector.dart';

/// Bot creation bottom sheet — "Single Setup Sheet" design.
///
/// Fields:
/// - Name (free text)
/// - Mode (simulation / live)
/// - Strategy mode (rule-based / sage-ai / both)
/// - Position size (SOL)
/// - Entry threshold (%)
/// - Max concurrent positions
///
/// All other params use FreesolGames defaults.
class CreateBotSheet extends ConsumerStatefulWidget {
  const CreateBotSheet({super.key});

  @override
  ConsumerState<CreateBotSheet> createState() => _CreateBotSheetState();

  /// Show the bottom sheet.
  static Future<Bot?> show(BuildContext context) {
    return showModalBottomSheet<Bot>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateBotSheet(),
    );
  }
}

class _CreateBotSheetState extends ConsumerState<CreateBotSheet> {
  final _nameController = TextEditingController(text: 'My Bot');
  BotMode _mode = BotMode.simulation;
  StrategyMode _strategyMode = StrategyMode.ruleBased;
  double _positionSize = kDefaultRiskConfig.positionSizeSOL;
  double _simulationBalanceSol = kDefaultSimulationBalanceSOL;
  double _entryThreshold = kDefaultRiskConfig.entryScoreThreshold;
  int _maxConcurrent = kDefaultRiskConfig.maxConcurrentPositions;
  bool _isCreating = false;

  // Strategy preset state
  StrategyPreset? _selectedPreset;

  // Hidden config values (populated by preset or defaults)
  double _minVolume24h = kDefaultCustomEntry.minVolume24h;
  double _minLiquidity = kDefaultCustomEntry.minLiquidity;
  double _maxLiquidity = kDefaultCustomEntry.maxLiquidity;
  int _defaultBinRange = kDefaultCustomEntry.defaultBinRange;
  double _profitTargetPercent = kDefaultRiskConfig.profitTargetPercent;
  double _stopLossPercent = kDefaultRiskConfig.stopLossPercent;
  int _maxHoldTimeMinutes = kDefaultRiskConfig.maxHoldTimeMinutes;
  double _maxDailyLossSOL = kDefaultRiskConfig.maxDailyLossSOL;
  int _cooldownMinutes = kDefaultCustomEntry.cooldownMinutes;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Apply a strategy preset — fills all config fields from preset values.
  void _applyPreset(StrategyPreset preset) {
    setState(() {
      _selectedPreset = preset;
      _positionSize = preset.positionSizeSOL;
      _simulationBalanceSol = clampSimulationBalanceSOL(
        requested: _simulationBalanceSol,
        positionSizeSOL: preset.positionSizeSOL,
      );
      _entryThreshold = preset.entryScoreThreshold;
      _maxConcurrent = preset.maxConcurrentPositions;
      _minVolume24h = preset.minVolume24h;
      _minLiquidity = preset.minLiquidity;
      _maxLiquidity = preset.maxLiquidity;
      _defaultBinRange = preset.defaultBinRange;
      _profitTargetPercent = preset.profitTargetPercent;
      _stopLossPercent = preset.stopLossPercent;
      _maxHoldTimeMinutes = preset.maxHoldTimeMinutes;
      _maxDailyLossSOL = preset.maxDailyLossSOL;
      _cooldownMinutes = preset.cooldownMinutes;
    });
    HapticFeedback.selectionClick();
  }

  void _setPositionSize(double value) {
    setState(() {
      _positionSize = value;
      _simulationBalanceSol = clampSimulationBalanceSOL(
        requested: _simulationBalanceSol,
        positionSizeSOL: value,
      );
    });
  }

  void _setSimulationBalance(double value) {
    setState(() {
      final newBalance = normalizeSimulationBalanceSOL(value);
      // If position size is now too large for the bankroll, shrink it.
      if (_positionSize >= newBalance) {
        _positionSize = _round2((newBalance * 0.5).clamp(0.05, _positionSize));
      }
      // Same for daily loss — cap at bankroll.
      if (_maxDailyLossSOL > newBalance) {
        _maxDailyLossSOL = _round2(newBalance * 0.8);
      }
      _simulationBalanceSol = clampSimulationBalanceSOL(
        requested: newBalance,
        positionSizeSOL: _positionSize,
      );
    });
  }

  /// Clear preset selection — keeps current values for manual editing.
  void _clearPreset() {
    setState(() => _selectedPreset = null);
    HapticFeedback.selectionClick();
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  Future<void> _createBot() async {
    if (_isCreating) return;

    if (_mode == BotMode.live && !kLiveTradingEnabled) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(kLiveTradingDisabledReason)));
      return;
    }

    final name = _nameController.text.trim();
    final nameError = BotValidators.name(name);
    if (nameError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(nameError)));
      return;
    }

    // ⚠️ FINANCIAL SAFETY: Confirm live mode deployment
    if (_mode == BotMode.live) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final c = ctx.sage;
          final text = ctx.sageText;
          return AlertDialog(
            backgroundColor: c.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
            ),
            title: Text(
              '⚠️ Live Trading',
              style: text.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.redAccent,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This bot will trade with REAL funds.',
                  style: text.bodyMedium?.copyWith(color: c.textPrimary),
                ),
                SizedBox(height: 8.h),
                Text(
                  '• Position size: ${_positionSize.toStringAsFixed(1)} SOL\n'
                  '• Max concurrent: $_maxConcurrent positions\n'
                  '• Max daily loss: ${_maxDailyLossSOL.toStringAsFixed(1)} SOL\n'
                  '• Recommended deposit: ${((_positionSize + 0.07) * _maxConcurrent).toStringAsFixed(1)} SOL\n'
                  '  (${_positionSize.toStringAsFixed(1)} + fees per position × $_maxConcurrent)',
                  style: text.bodySmall?.copyWith(
                    color: c.textSecondary,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'You\'ll be prompted to fund the bot wallet after creation.',
                  style: text.bodySmall?.copyWith(
                    color: c.accent,
                    fontSize: 11.sp,
                  ),
                ),
                SizedBox(height: 12.h),
                Text(
                  'Are you sure you want to deploy?',
                  style: text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Cancel', style: TextStyle(color: c.textTertiary)),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text(
                  'Deploy Live',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
    }

    setState(() => _isCreating = true);

    try {
      final config = BotConfig(
        name: name,
        mode: _mode.name,
        config: {
          'strategyMode': _strategyMode == StrategyMode.ruleBased
              ? 'rule-based'
              : _strategyMode == StrategyMode.sageAi
              ? 'sage-ai'
              : 'both',
          'positionSizeSOL': _positionSize,
          'entryScoreThreshold': _entryThreshold,
          'maxConcurrentPositions': _maxConcurrent,
          'minVolume24h': _minVolume24h,
          'minLiquidity': _minLiquidity,
          'maxLiquidity': _maxLiquidity,
          'defaultBinRange': _defaultBinRange,
          'profitTargetPercent': _profitTargetPercent,
          'stopLossPercent': _stopLossPercent,
          'maxHoldTimeMinutes': _maxHoldTimeMinutes,
          'maxDailyLossSOL': _maxDailyLossSOL,
          'cooldownMinutes': _cooldownMinutes,
          'cronIntervalSeconds': 30,
          'simulationBalanceSOL': _simulationBalanceSol,
          if (_selectedPreset != null) 'strategyPresetId': _selectedPreset!.id,
        },
      );

      final notifier = ref.read(botListProvider.notifier);
      final bot = await notifier.createBot(config);

      if (mounted && bot.mode == BotMode.live) {
        // Live bot: show deposit sheet so user can fund the wallet immediately
        final recommended = (_positionSize + 0.07) * _maxConcurrent;
        await SageBottomSheet.show<bool>(
          context: context,
          title: 'Fund Your Bot',
          builder: (c, text) => DepositSheet(
            botId: bot.botId,
            recommendedSol: recommended,
            minSol: _positionSize + 0.07,
            c: c,
            text: text,
          ),
        );
      }

      if (mounted) {
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(bot);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create bot: $e')));
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sage;
    final text = context.sageText;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        border: Border(top: BorderSide(color: c.borderSubtle, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(28.w, 16.h, 28.w, 24.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: c.textTertiary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),

              SizedBox(height: 20.h),

              // Title
              Text(
                'Create Bot',
                style: text.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),

              SizedBox(height: 24.h),

              // ── Name ──
              SectionLabel(label: 'NAME', c: c, text: text),
              SizedBox(height: 8.h),
              BotInputField(
                controller: _nameController,
                hint: 'Bot name',
                c: c,
                text: text,
              ),

              SizedBox(height: 20.h),

              // ── Mode ──
              SectionLabel(label: 'MODE', c: c, text: text),
              SizedBox(height: 8.h),
              SegmentedPicker<BotMode>(
                value: _mode,
                options: const {
                  BotMode.simulation: 'Simulation',
                  BotMode.live: 'Live',
                },
                onChanged: (v) {
                  if (v == BotMode.live && !kLiveTradingEnabled) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(kLiveTradingDisabledReason)),
                    );
                    return;
                  }
                  setState(() => _mode = v);
                },
                c: c,
                text: text,
              ),
              if (!kLiveTradingEnabled)
                Padding(
                  padding: EdgeInsets.only(top: 6.h),
                  child: Text(
                    kLiveTradingDisabledReason,
                    style: text.bodySmall?.copyWith(
                      color: c.textTertiary,
                      fontSize: 11.sp,
                    ),
                  ),
                ),

              SizedBox(height: 20.h),

              // ── Strategy Mode ──
              SectionLabel(label: 'STRATEGY', c: c, text: text),
              SizedBox(height: 8.h),
              SegmentedPicker<StrategyMode>(
                value: _strategyMode,
                options: const {
                  StrategyMode.ruleBased: 'Rule-Based',
                  StrategyMode.sageAi: 'Sage AI',
                  StrategyMode.both: 'Hybrid',
                },
                onChanged: (v) => setState(() => _strategyMode = v),
                c: c,
                text: text,
              ),
              if (_strategyMode != StrategyMode.ruleBased)
                Padding(
                  padding: EdgeInsets.only(top: 6.h),
                  child: Text(
                    _strategyMode == StrategyMode.sageAi
                        ? 'ML model predictions only (XGBoost V3)'
                        : 'Rule-based score × ML confidence',
                    style: text.bodySmall?.copyWith(
                      color: c.accent,
                      fontSize: 11.sp,
                    ),
                  ),
                ),

              SizedBox(height: 20.h),

              // ── Strategy Preset ──
              SectionLabel(label: 'PRESET', c: c, text: text),
              SizedBox(height: 8.h),
              StrategyPresetSelector(
                selectedPreset: _selectedPreset,
                onPresetSelected: _applyPreset,
                onCustomSelected: _clearPreset,
                c: c,
                text: text,
              ),
              if (_selectedPreset?.description != null)
                Padding(
                  padding: EdgeInsets.only(top: 6.h),
                  child: Text(
                    _selectedPreset!.description!,
                    style: text.bodySmall?.copyWith(
                      color: c.textSecondary,
                      fontSize: 11.sp,
                    ),
                  ),
                ),

              SizedBox(height: 20.h),

              // ── Position Size ──
              SectionLabel(label: 'POSITION SIZE', c: c, text: text),
              SizedBox(height: 8.h),
              SliderRow(
                value: _positionSize,
                min: 0.1,
                max: 10.0,
                divisions: 99,
                unit: 'SOL',
                format: (v) => v.toStringAsFixed(1),
                onChanged: _setPositionSize,
                c: c,
                text: text,
              ),

              if (_mode == BotMode.simulation) ...[
                SizedBox(height: 20.h),
                SectionLabel(label: 'SIMULATION CAPITAL', c: c, text: text),
                SizedBox(height: 8.h),
                SliderRow(
                  value: _simulationBalanceSol,
                  min: minimumSimulationBalanceSOL(_positionSize),
                  max: kMaxSimulationBalanceSOL,
                  divisions:
                      ((kMaxSimulationBalanceSOL -
                                  minimumSimulationBalanceSOL(_positionSize)) *
                              10)
                          .round()
                          .clamp(1, 998),
                  unit: 'SOL',
                  format: (v) => v.toStringAsFixed(1),
                  onChanged: _setSimulationBalance,
                  c: c,
                  text: text,
                ),
                SizedBox(height: 6.h),
                Text(
                  'Virtual capital only. Uses real market data, no on-chain execution.',
                  style: text.bodySmall?.copyWith(
                    color: c.textSecondary,
                    fontSize: 11.sp,
                  ),
                ),
              ],

              SizedBox(height: 20.h),

              // ── Entry Threshold ──
              SectionLabel(label: 'ENTRY THRESHOLD', c: c, text: text),
              SizedBox(height: 8.h),
              SliderRow(
                value: _entryThreshold,
                min: 50,
                max: 300,
                divisions: 50,
                unit: '%',
                format: (v) => v.toStringAsFixed(0),
                onChanged: (v) => setState(() => _entryThreshold = v),
                c: c,
                text: text,
              ),

              SizedBox(height: 20.h),

              // ── Max Concurrent ──
              SectionLabel(label: 'MAX CONCURRENT', c: c, text: text),
              SizedBox(height: 8.h),
              SliderRow(
                value: _maxConcurrent.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                unit: 'bots',
                format: (v) => v.toStringAsFixed(0),
                onChanged: (v) => setState(() => _maxConcurrent = v.round()),
                c: c,
                text: text,
              ),

              SizedBox(height: 28.h),

              // ── Create button ──
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: _isCreating ? null : _createBot,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    decoration: BoxDecoration(
                      color: _isCreating
                          ? c.accent.withValues(alpha: 0.4)
                          : c.accent,
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Center(
                      child: _isCreating
                          ? SizedBox(
                              width: 20.w,
                              height: 20.w,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: c.textPrimary,
                              ),
                            )
                          : Text(
                              'Deploy Bot',
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
