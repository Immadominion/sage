import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sage/core/models/bot.dart';
import 'package:sage/core/config/live_trading_flags.dart';
import 'package:sage/core/config/simulation_defaults.dart';
import 'package:sage/core/repositories/bot_repository.dart';
import 'package:sage/core/services/auth_service.dart';
import 'package:sage/core/theme/app_colors.dart';
import 'package:sage/core/theme/app_theme.dart';

import 'package:sage/features/setup/models/risk_profile.dart';
import 'package:sage/features/setup/presentation/widgets/custom_strategy_step.dart';
import 'package:sage/features/setup/presentation/widgets/guardrails_step.dart';
import 'package:sage/features/setup/presentation/widgets/path_step.dart';
import 'package:sage/features/setup/presentation/widgets/review_fund_step.dart';
import 'package:sage/features/chat/models/chat_models.dart';
import 'package:sage/features/chat/presentation/widgets/setup_chat_step.dart';

/// Full-screen strategy creation flow — same design language as [SetupScreen]
/// but without wallet creation or setup-complete marking.
///
/// Three steps:
///   1. Choose path (Sage AI / Custom) + execution mode
///   2. Configure strategy parameters
///   3. Review & deploy
class CreateStrategyScreen extends ConsumerStatefulWidget {
  const CreateStrategyScreen({super.key});

  @override
  ConsumerState<CreateStrategyScreen> createState() =>
      _CreateStrategyScreenState();
}

class _CreateStrategyScreenState extends ConsumerState<CreateStrategyScreen> {
  int _step = 0;
  SetupPath? _path;
  RiskProfile _risk = RiskProfile.balanced;
  ExecutionMode _execMode = ExecutionMode.simulation;
  bool _showCustomize = false;
  bool _isActivating = false;
  bool _useAiChat = false;

  /// Tracks the bot created in Step 1 so retry doesn't create a duplicate.
  Bot? _createdBot;

  /// User-facing status message shown during the multi-step deploy process.
  String _deployStatus = '';

  final TextEditingController _nameController = TextEditingController();

  // ── Sage AI overrides ──
  double _positionSize = kDefaultRiskConfig.positionSizeSOL;
  double _simulationBalanceSol = kDefaultSimulationBalanceSOL;
  double _dailyLimit = kDefaultRiskConfig.maxDailyLossSOL;
  double _profitTarget = kDefaultRiskConfig.profitTargetPercent;
  double _stopLoss = kDefaultRiskConfig.stopLossPercent;

  // ── Custom strategy fields ──
  double _entryScore = kDefaultRiskConfig.entryScoreThreshold;
  double _minVolume = kDefaultCustomEntry.minVolume24h;
  double _minLiquidity = kDefaultCustomEntry.minLiquidity;
  double _maxLiquidity = kDefaultCustomEntry.maxLiquidity;
  int _maxConcurrent = kDefaultRiskConfig.maxConcurrentPositions;
  int _binRange = kDefaultCustomEntry.defaultBinRange;
  int _maxHoldMinutes = kDefaultRiskConfig.maxHoldTimeMinutes;
  int _cooldownMinutes = kDefaultCustomEntry.cooldownMinutes;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _selectPath(SetupPath path) {
    HapticFeedback.selectionClick();
    setState(() => _path = path);
  }

  void _selectRisk(RiskProfile risk) {
    HapticFeedback.mediumImpact();
    final cfg = configForBankroll(risk, _simulationBalanceSol);
    setState(() {
      _risk = risk;
      _positionSize = cfg.positionSizeSOL;
      _simulationBalanceSol = clampSimulationBalanceSOL(
        requested: _simulationBalanceSol,
        positionSizeSOL: cfg.positionSizeSOL,
      );
      _dailyLimit = cfg.maxDailyLossSOL;
      _profitTarget = cfg.profitTargetPercent;
      _stopLoss = cfg.stopLossPercent;
      _maxConcurrent = cfg.maxConcurrentPositions;
    });
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
      if (_path == SetupPath.sageAi) {
        // Bankroll-relative: re-derive config from the new balance.
        final rawBalance = normalizeSimulationBalanceSOL(value);
        final cfg = configForBankroll(_risk, rawBalance);
        _positionSize = cfg.positionSizeSOL;
        _dailyLimit = cfg.maxDailyLossSOL;
        _maxConcurrent = cfg.maxConcurrentPositions;
        _simulationBalanceSol = clampSimulationBalanceSOL(
          requested: rawBalance,
          positionSizeSOL: cfg.positionSizeSOL,
        );
      } else {
        _simulationBalanceSol = clampSimulationBalanceSOL(
          requested: value,
          positionSizeSOL: _positionSize,
        );
      }
    });
  }

  void _nextStep() {
    if (_step == 0 && _path != null) {
      HapticFeedback.mediumImpact();
      setState(() => _step = 1);
    }
  }

  void _nextToReview() {
    HapticFeedback.mediumImpact();
    setState(() => _step = 2);
  }

  void _handleExecModeChanged(ExecutionMode mode) {
    if (mode == ExecutionMode.live && !kLiveTradingEnabled) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(kLiveTradingDisabledReason)));
      return;
    }

    HapticFeedback.selectionClick();
    setState(() => _execMode = mode);
  }

  void _applyAiParams(StrategyParams params) {
    setState(() {
      if (params.entryScoreThreshold != null) {
        _entryScore = params.entryScoreThreshold!;
      }
      if (params.minVolume24h != null) _minVolume = params.minVolume24h!;
      if (params.minLiquidity != null) _minLiquidity = params.minLiquidity!;
      if (params.maxLiquidity != null) _maxLiquidity = params.maxLiquidity!;
      if (params.positionSizeSOL != null) {
        _positionSize = params.positionSizeSOL!;
      }
      if (params.simulationBalanceSOL != null) {
        _simulationBalanceSol = params.simulationBalanceSOL!;
      }
      if (params.maxConcurrentPositions != null) {
        _maxConcurrent = params.maxConcurrentPositions!;
      }
      if (params.defaultBinRange != null) _binRange = params.defaultBinRange!;
      if (params.profitTargetPercent != null) {
        _profitTarget = params.profitTargetPercent!;
      }
      if (params.stopLossPercent != null) _stopLoss = params.stopLossPercent!;
      if (params.maxHoldTimeMinutes != null) {
        _maxHoldMinutes = params.maxHoldTimeMinutes!;
      }
      if (params.maxDailyLossSOL != null) _dailyLimit = params.maxDailyLossSOL!;
      if (params.cooldownMinutes != null) {
        _cooldownMinutes = params.cooldownMinutes!;
      }

      _simulationBalanceSol = clampSimulationBalanceSOL(
        requested: _simulationBalanceSol,
        positionSizeSOL: _positionSize,
      );
    });
  }

  /// Deploy — creates the bot and starts it.
  ///
  /// Live-mode wallet setup is disabled until per-bot wallet migration
  /// is complete (kLiveTradingEnabled == false).
  Future<void> _deploy(double? depositSol) async {
    if (_isActivating) return;
    setState(() {
      _isActivating = true;
      _deployStatus = 'Preparing…';
    });
    HapticFeedback.mediumImpact();

    void updateStatus(String status) {
      if (mounted) setState(() => _deployStatus = status);
    }

    try {
      final isSageAi = _path == SetupPath.sageAi;
      final strategyMode = isSageAi ? 'sage-ai' : 'rule-based';
      final riskCfg = riskConfigs[_risk]!;
      final isLive = _execMode == ExecutionMode.live;

      if (isLive && !kLiveTradingEnabled) {
        throw Exception(kLiveTradingDisabledReason);
      }

      final modeName = isLive ? 'live' : 'simulation';

      final config = BotConfig(
        name: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        mode: modeName,
        config: {
          'strategyMode': strategyMode,
          'positionSizeSOL': _positionSize,
          'entryScoreThreshold': isSageAi
              ? riskCfg.entryScoreThreshold
              : _entryScore,
          'maxConcurrentPositions': isSageAi
              ? riskCfg.maxConcurrentPositions
              : _maxConcurrent,
          'profitTargetPercent': _profitTarget,
          'stopLossPercent': _stopLoss,
          'maxHoldTimeMinutes': isSageAi
              ? riskCfg.maxHoldTimeMinutes
              : _maxHoldMinutes,
          'maxDailyLossSOL': _dailyLimit,
          'cooldownMinutes': isSageAi
              ? kDefaultCustomEntry.cooldownMinutes
              : _cooldownMinutes,
          'cronIntervalSeconds': 30,
          'simulationBalanceSOL': _simulationBalanceSol,
          'minVolume24h': isSageAi
              ? kDefaultCustomEntry.minVolume24h
              : _minVolume,
          'minLiquidity': isSageAi
              ? kDefaultCustomEntry.minLiquidity
              : _minLiquidity,
          'maxLiquidity': isSageAi
              ? kDefaultCustomEntry.maxLiquidity
              : _maxLiquidity,
          'defaultBinRange': isSageAi
              ? kDefaultCustomEntry.defaultBinRange
              : _binRange,
        },
      );

      // ── Step 1: Create the bot (skip if already created from a prior attempt) ──
      updateStatus('Creating bot…');
      if (_createdBot == null) {
        final repo = ref.read(botRepositoryProvider);
        _createdBot = await repo.createBot(config);
      }
      final createdBot = _createdBot!;
      if (createdBot.botId.isEmpty) throw Exception('Bot creation failed');

      // Ensure setup is marked complete (bot exists → setup is done).
      ref.read(authStateProvider.notifier).markSetupCompleted();

      // Navigate immediately — before refreshing the bot list.
      if (mounted) {
        HapticFeedback.heavyImpact();
        context.go('/strategy/${createdBot.botId}');
      }

      // Fire-and-forget: start bot + refresh list after navigation.
      unawaited(
        Future(() async {
          try {
            await ref.read(botRepositoryProvider).startBot(createdBot.botId);
          } catch (_) {
            // Non-fatal: bot created, start can be retried from detail screen.
          }
          ref.read(botListProvider.notifier).refresh();
        }),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isActivating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyError(e)),
            backgroundColor: context.sage.loss,
          ),
        );
      }
    }
  }

  String _friendlyError(Object error) {
    final msg = error.toString();
    if (msg.contains('already exists') && msg.contains('name')) {
      return 'A bot with that name already exists. Choose a different name.';
    }
    if (msg.contains('SocketException') ||
        msg.contains('Connection refused') ||
        msg.contains('connection timeout')) {
      return 'Cannot reach server. Check your internet connection.';
    }
    if (msg.contains('timeout') || msg.contains('Timeout')) {
      return 'Request timed out. Please try again.';
    }
    if (msg.contains('authorization cancelled') ||
        msg.contains('rejected by wallet')) {
      return 'Wallet authorization was cancelled. Tap Deploy to try again.';
    }
    if (msg.contains('Minimum deposit')) {
      // Surface the backend's deposit validation message directly
      final match = RegExp(r'Minimum deposit is [\d.]+ SOL').firstMatch(msg);
      if (match != null) return '${match.group(0)}. Increase your deposit.';
      return 'Deposit too low — increase amount and try again.';
    }
    if (msg.contains('wallet not found') || msg.contains('Bot not found')) {
      return 'Bot wallet not found. Please try again.';
    }
    if (msg.contains('MWA')) {
      return 'Could not connect to your wallet app.';
    }
    return 'Failed to deploy strategy. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sage;
    final text = context.sageText;

    Widget stepWidget;

    switch (_step) {
      case 0:
        stepWidget = PathStep(
          key: const ValueKey('path'),
          selected: _path,
          onSelect: _selectPath,
          mode: _execMode,
          onModeChanged: _handleExecModeChanged,
          onNext: _nextStep,
          onClose: () => context.pop(),
          nameController: _nameController,
          c: c,
          text: text,
        );
        break;

      case 1:
        if (_path == SetupPath.custom) {
          if (_useAiChat) {
            stepWidget = SetupChatStep(
              key: const ValueKey('setup-chat'),
              onBack: () {
                HapticFeedback.selectionClick();
                setState(() => _useAiChat = false);
              },
              onApplyParams: (params) {
                _applyAiParams(params);
                _nextToReview();
              },
              c: c,
              text: text,
            );
          } else {
            stepWidget = CustomStrategyStep(
              key: const ValueKey('custom'),
              onBack: () {
                HapticFeedback.selectionClick();
                setState(() => _step = 0);
              },
              onNext: _nextToReview,
              onTalkToSage: () {
                HapticFeedback.mediumImpact();
                setState(() => _useAiChat = true);
              },
              entryScoreThreshold: _entryScore,
              minVolume24h: _minVolume,
              minLiquidity: _minLiquidity,
              maxLiquidity: _maxLiquidity,
              positionSizeSOL: _positionSize,
              maxConcurrentPositions: _maxConcurrent,
              defaultBinRange: _binRange,
              profitTargetPercent: _profitTarget,
              stopLossPercent: _stopLoss,
              maxHoldTimeMinutes: _maxHoldMinutes,
              maxDailyLossSOL: _dailyLimit,
              cooldownMinutes: _cooldownMinutes,
              onEntryScoreChanged: (v) => setState(() => _entryScore = v),
              onMinVolumeChanged: (v) => setState(() => _minVolume = v),
              onMinLiquidityChanged: (v) => setState(() => _minLiquidity = v),
              onMaxLiquidityChanged: (v) => setState(() => _maxLiquidity = v),
              onPositionSizeChanged: _setPositionSize,
              onMaxPositionsChanged: (v) => setState(() => _maxConcurrent = v),
              onBinRangeChanged: (v) => setState(() => _binRange = v),
              onProfitTargetChanged: (v) => setState(() => _profitTarget = v),
              onStopLossChanged: (v) => setState(() => _stopLoss = v),
              onMaxHoldChanged: (v) => setState(() => _maxHoldMinutes = v),
              onDailyLimitChanged: (v) => setState(() => _dailyLimit = v),
              onCooldownChanged: (v) => setState(() => _cooldownMinutes = v),
              c: c,
              text: text,
            );
          }
        } else {
          stepWidget = GuardrailsStep(
            key: const ValueKey('guardrails'),
            risk: _risk,
            onSelectRisk: _selectRisk,
            showCustomize: _showCustomize,
            onToggleCustomize: () =>
                setState(() => _showCustomize = !_showCustomize),
            positionSize: _positionSize,
            dailyLimit: _dailyLimit,
            profitTarget: _profitTarget,
            stopLoss: _stopLoss,
            onPositionSizeChanged: _setPositionSize,
            onDailyLimitChanged: (v) => setState(() => _dailyLimit = v),
            onProfitTargetChanged: (v) => setState(() => _profitTarget = v),
            onStopLossChanged: (v) => setState(() => _stopLoss = v),
            onNext: _nextToReview,
            onBack: () {
              HapticFeedback.selectionClick();
              setState(() => _step = 0);
            },
            c: c,
            text: text,
          );
        }
        break;

      default:
        final isSageAi = _path == SetupPath.sageAi;
        final riskCfg = riskConfigs[_risk]!;
        stepWidget = ReviewFundStep(
          key: const ValueKey('review'),
          path: _path ?? SetupPath.sageAi,
          mode: _execMode,
          positionSizeSOL: _positionSize,
          simulationBalanceSOL: _simulationBalanceSol,
          onSimulationBalanceChanged: _setSimulationBalance,
          maxConcurrentPositions: isSageAi
              ? riskCfg.maxConcurrentPositions
              : _maxConcurrent,
          profitTargetPercent: _profitTarget,
          stopLossPercent: _stopLoss,
          maxDailyLossSOL: _dailyLimit,
          onBack: () {
            HapticFeedback.selectionClick();
            setState(() => _step = 1);
          },
          showFunding: _execMode == ExecutionMode.live,
          activateLabel: _execMode == ExecutionMode.live
              ? 'Deploy & Fund Bot'
              : 'Deploy Strategy',
          onActivate: _deploy,
          isActivating: _isActivating,
          statusMessage: _deployStatus,
          c: c,
          text: text,
        );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: c.background,
      ),
      child: Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.03, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: stepWidget,
          ),
        ),
      ),
    );
  }
}
