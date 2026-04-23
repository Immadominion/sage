import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura/core/models/bot.dart';
import 'package:aura/core/config/live_trading_flags.dart';
import 'package:aura/core/repositories/bot_repository.dart';
import 'package:aura/core/services/api_client.dart';
import 'package:aura/core/services/auth_service.dart';
import 'package:aura/core/theme/app_colors.dart';
import 'package:aura/core/theme/app_theme.dart';

import 'package:aura/core/config/simulation_defaults.dart';
import 'package:aura/core/services/chat_persistence.dart';
import 'package:aura/features/setup/models/risk_profile.dart';
import 'package:aura/features/setup/presentation/widgets/custom_strategy_step.dart';
import 'package:aura/features/setup/presentation/widgets/guardrails_step.dart';
import 'package:aura/features/setup/presentation/widgets/llm_config_step.dart';
import 'package:aura/features/setup/presentation/widgets/path_step.dart';
import 'package:aura/features/setup/presentation/widgets/review_fund_step.dart';
import 'package:aura/features/chat/models/chat_models.dart';
import 'package:aura/features/chat/presentation/widgets/setup_chat_step.dart';
import 'package:aura/shared/widgets/deposit_sheet.dart';
import 'package:aura/shared/widgets/aura_bottom_sheet.dart';
import 'package:aura/features/chat/providers/chat_provider.dart';

/// Setup Wizard — shown once after first wallet connection.
///
/// Three steps:
///   1. Choose path (Aura AI / Custom) + execution mode radio
///   2. Configure strategy parameters
///   3. Review, fund wallet (live mode), accept disclaimers & activate
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  int _step = 0; // 0 = path + mode, 1 = config, 2 = review + fund + activate
  SetupPath? _path;
  RiskProfile _risk = RiskProfile.balanced;
  ExecutionMode _execMode = ExecutionMode.simulation;
  bool _showCustomize = false;
  bool _isActivating = false;
  String _deployStatus = '';
  bool _useAiChat = false; // true = "Talk to Aura" instead of manual sliders
  Timer? _persistDebounce;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _llmApiKeyController = TextEditingController();
  final TextEditingController _llmModelController = TextEditingController();
  final TextEditingController _llmDailyCapController = TextEditingController();

  // ── Aura AI overrides ──
  late double _positionSize = kDefaultRiskConfig.positionSizeSOL;
  late double _simulationBalanceSol = kDefaultSimulationBalanceSOL;
  late double _dailyLimit = kDefaultRiskConfig.maxDailyLossSOL;
  late double _profitTarget = kDefaultRiskConfig.profitTargetPercent;
  late double _stopLoss = kDefaultRiskConfig.stopLossPercent;

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
  void initState() {
    super.initState();
    _restoreSetupState();
  }

  /// Restore saved setup wizard state from SharedPreferences.
  Future<void> _restoreSetupState() async {
    final persistence = ref.read(chatPersistenceProvider);
    final saved = await persistence.loadSetupState();
    if (saved == null || !mounted) return;

    setState(() {
      _step = saved.step;

      if (saved.path != null) {
        _path = switch (saved.path) {
          'aura-ai' => SetupPath.auraAi,
          'llm' => SetupPath.llm,
          _ => SetupPath.custom,
        };
      }
      if (saved.execMode != null) {
        _execMode = saved.execMode == 'live' && kLiveTradingEnabled
            ? ExecutionMode.live
            : ExecutionMode.simulation;
      }
      _useAiChat = saved.useAiChat;

      // Restore strategy params
      if (saved.params != null) {
        _applyAiParams(saved.params!);
      }

      _simulationBalanceSol = clampSimulationBalanceSOL(
        requested:
            saved.params?.simulationBalanceSOL ?? kDefaultSimulationBalanceSOL,
        positionSizeSOL: _positionSize,
      );
    });
  }

  @override
  void dispose() {
    _persistDebounce?.cancel();
    _nameController.dispose();
    _llmApiKeyController.dispose();
    _llmModelController.dispose();
    _llmDailyCapController.dispose();
    super.dispose();
  }

  /// Save current setup state — debounced to avoid hammering the server.
  /// Local cache updates immediately; server sync waits 800ms of inactivity.
  void _persistSetupState() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      final persistence = ref.read(chatPersistenceProvider);
      final pathStr = switch (_path) {
        SetupPath.auraAi => 'aura-ai',
        SetupPath.custom => 'custom',
        SetupPath.llm => 'llm',
        null => null,
      };
      final modeStr = _execMode == ExecutionMode.live ? 'live' : 'simulation';

      persistence.saveSetupState(
        step: _step,
        path: pathStr,
        execMode: modeStr,
        useAiChat: _useAiChat,
        params: StrategyParams(
          entryScoreThreshold: _entryScore,
          minVolume24h: _minVolume,
          minLiquidity: _minLiquidity,
          maxLiquidity: _maxLiquidity,
          positionSizeSOL: _positionSize,
          simulationBalanceSOL: _simulationBalanceSol,
          maxConcurrentPositions: _maxConcurrent,
          defaultBinRange: _binRange,
          profitTargetPercent: _profitTarget,
          stopLossPercent: _stopLoss,
          maxHoldTimeMinutes: _maxHoldMinutes,
          maxDailyLossSOL: _dailyLimit,
          cooldownMinutes: _cooldownMinutes,
        ),
      );
    });
  }

  void _selectPath(SetupPath path) {
    HapticFeedback.selectionClick();
    setState(() => _path = path);
    _persistSetupState();
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
    _persistSetupState();
  }

  void _setPositionSize(double value) {
    setState(() {
      _positionSize = value;
      _simulationBalanceSol = clampSimulationBalanceSOL(
        requested: _simulationBalanceSol,
        positionSizeSOL: value,
      );
    });
    _persistSetupState();
  }

  void _setSimulationBalance(double value) {
    setState(() {
      if (_path == SetupPath.auraAi || _path == SetupPath.llm) {
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
    _persistSetupState();
  }

  void _nextStep() {
    if (_step == 0 && _path != null) {
      HapticFeedback.mediumImpact();
      setState(() => _step = 1);
      _persistSetupState();
    }
  }

  void _nextToReview() {
    HapticFeedback.mediumImpact();
    setState(() => _step = 2);
    _persistSetupState();
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
    _persistSetupState();
  }

  /// Apply AI-extracted strategy parameters to the setup state.
  void _applyAiParams(StrategyParams params) {
    setState(() {
      if (params.entryScoreThreshold != null) {
        _entryScore = params.entryScoreThreshold!;
      }
      if (params.minVolume24h != null) {
        _minVolume = params.minVolume24h!;
      }
      if (params.minLiquidity != null) {
        _minLiquidity = params.minLiquidity!;
      }
      if (params.maxLiquidity != null) {
        _maxLiquidity = params.maxLiquidity!;
      }
      if (params.positionSizeSOL != null) {
        _positionSize = params.positionSizeSOL!;
      }
      if (params.simulationBalanceSOL != null) {
        _simulationBalanceSol = params.simulationBalanceSOL!;
      }
      if (params.maxConcurrentPositions != null) {
        _maxConcurrent = params.maxConcurrentPositions!;
      }
      if (params.defaultBinRange != null) {
        _binRange = params.defaultBinRange!;
      }
      if (params.profitTargetPercent != null) {
        _profitTarget = params.profitTargetPercent!;
      }
      if (params.stopLossPercent != null) {
        _stopLoss = params.stopLossPercent!;
      }
      if (params.maxHoldTimeMinutes != null) {
        _maxHoldMinutes = params.maxHoldTimeMinutes!;
      }
      if (params.maxDailyLossSOL != null) {
        _dailyLimit = params.maxDailyLossSOL!;
      }
      if (params.cooldownMinutes != null) {
        _cooldownMinutes = params.cooldownMinutes!;
      }

      _simulationBalanceSol = clampSimulationBalanceSOL(
        requested: _simulationBalanceSol,
        positionSizeSOL: _positionSize,
      );
    });
    _persistSetupState();
  }

  Future<void> _skip() async {
    HapticFeedback.selectionClick();
    await _markSetupComplete();
    if (mounted) {
      ref.read(authStateProvider.notifier).markSetupCompleted();
      context.go('/');
    }
  }

  /// Create a bot and start it. Live on-chain setup is gated behind
  /// kLiveTradingEnabled — currently disabled.
  Future<void> _activate(double? depositSol) async {
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
      final isAuraAi = _path == SetupPath.auraAi;
      final isLlm = _path == SetupPath.llm;
      final strategyMode = isAuraAi
          ? 'aura-ai'
          : isLlm
          ? 'llm'
          : 'rule-based';
      final riskCfg = riskConfigs[_risk]!;
      final isLive = _execMode == ExecutionMode.live;

      if (isLive && !kLiveTradingEnabled) {
        throw Exception(kLiveTradingDisabledReason);
      }

      final modeName = isLive ? 'live' : 'simulation';

      // LLM mode uses the conservative/balanced/aggressive risk profile for
      // sizing — same as Aura AI — and adds the per-bot Anthropic key fields.
      final useRiskCfg = isAuraAi || isLlm;
      final llmDailyCap = double.tryParse(_llmDailyCapController.text.trim());

      final config = BotConfig(
        name: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        mode: modeName,
        config: {
          'strategyMode': strategyMode,
          'positionSizeSOL': _positionSize,
          'entryScoreThreshold': useRiskCfg
              ? riskCfg.entryScoreThreshold
              : _entryScore,
          'maxConcurrentPositions': useRiskCfg
              ? riskCfg.maxConcurrentPositions
              : _maxConcurrent,
          'profitTargetPercent': _profitTarget,
          'stopLossPercent': _stopLoss,
          'maxHoldTimeMinutes': useRiskCfg
              ? riskCfg.maxHoldTimeMinutes
              : _maxHoldMinutes,
          'maxDailyLossSOL': _dailyLimit,
          'cooldownMinutes': useRiskCfg
              ? kDefaultCustomEntry.cooldownMinutes
              : _cooldownMinutes,
          'cronIntervalSeconds': 30,
          'simulationBalanceSOL': _simulationBalanceSol,
          'minVolume24h': useRiskCfg
              ? kDefaultCustomEntry.minVolume24h
              : _minVolume,
          'minLiquidity': useRiskCfg
              ? kDefaultCustomEntry.minLiquidity
              : _minLiquidity,
          'maxLiquidity': useRiskCfg
              ? kDefaultCustomEntry.maxLiquidity
              : _maxLiquidity,
          'defaultBinRange': useRiskCfg
              ? kDefaultCustomEntry.defaultBinRange
              : _binRange,
          if (isLlm) 'llmApiKey': _llmApiKeyController.text.trim(),
          if (isLlm && _llmModelController.text.trim().isNotEmpty)
            'llmModel': _llmModelController.text.trim(),
          if (isLlm && llmDailyCap != null && llmDailyCap > 0)
            'llmMaxUsdPerDay': llmDailyCap,
        },
      );

      updateStatus('Creating bot…');
      // Create via repo directly — NOT through the notifier — so the
      // botListProvider doesn't update and trigger the router redirect
      // before we can navigate away from /setup.
      final repo = ref.read(botRepositoryProvider);
      final createdBot = await repo.createBot(config);

      // Mark setup complete BEFORE any state change that might trigger
      // the router redirect.
      await _markSetupComplete();
      ref.read(authStateProvider.notifier).markSetupCompleted();

      // ── For live bots, show deposit sheet BEFORE navigation ──
      if (isLive && mounted) {
        updateStatus('Fund your bot…');
        final recommended =
            (_positionSize + 0.07) *
            (useRiskCfg ? riskCfg.maxConcurrentPositions : _maxConcurrent);
        await AuraBottomSheet.show<bool>(
          context: context,
          title: 'Fund Your Bot',
          builder: (c, text) => DepositSheet(
            botId: createdBot.botId,
            recommendedSol: recommended,
            minSol: _positionSize + 0.07,
            c: c,
            text: text,
          ),
        );
      }

      updateStatus('Starting bot…');
      await repo.startBot(createdBot.botId);
      await ref.read(botListProvider.notifier).refresh();
      ref.invalidate(botDetailProvider(createdBot.botId));

      // First bot → navigate to Home so user sees their dashboard.
      if (mounted) {
        HapticFeedback.heavyImpact();
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActivating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyActivateError(e)),
            backgroundColor: context.aura.loss,
          ),
        );
      }
    }
  }

  /// Convert raw activate errors into user-friendly messages.
  String _friendlyActivateError(Object error) {
    final msg = error.toString();

    // MWA-specific errors
    if (msg.contains('cancelled') || msg.contains('cancel')) {
      return 'Wallet authorization was cancelled. Try again.';
    }
    if (msg.contains('MWA is only available on Android')) {
      return 'Wallet connection requires Android.';
    }
    if (msg.contains('rejected')) {
      return 'Transaction was rejected by your wallet.';
    }

    // Transaction simulation errors (Phantom can fail to simulate
    // partially-signed or devnet TXs)
    if (msg.contains('simulation') || msg.contains('Simulation')) {
      return 'Transaction simulation failed. '
          'Make sure your wallet app is set to the correct network.';
    }
    if (msg.contains('blockhash') || msg.contains('Blockhash')) {
      return 'Transaction expired. Please try again.';
    }

    // Network errors
    if (msg.contains('SocketException') ||
        msg.contains('Connection refused') ||
        msg.contains('connection timeout') ||
        msg.contains('Backend unreachable')) {
      return 'Cannot reach server. Check your internet connection.';
    }
    if (msg.contains('timeout') || msg.contains('Timeout')) {
      return 'Request timed out. Please try again.';
    }

    // Generic fallback
    return 'Activation failed. Please try again.';
  }

  Future<void> _markSetupComplete() async {
    // Persist server-side (survives reinstalls / cross-device).
    final modeName = _execMode == ExecutionMode.simulation
        ? 'simulation'
        : 'live';
    await ref
        .read(apiClientProvider)
        .post('/auth/setup-complete', data: {'execMode': modeName});
    // Local cache for fast startup before auth state resolves.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setup_completed', true);

    // Clear saved setup wizard state — no longer needed.
    await ref.read(chatPersistenceProvider).clearSetupState();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.aura;
    final text = context.auraText;

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
          onSkip: _skip,
          nameController: _nameController,
          c: c,
          text: text,
        );
        break;

      case 1: // step 1 — configure strategy
        if (_path == SetupPath.llm) {
          stepWidget = LlmConfigStep(
            key: const ValueKey('llm'),
            apiKeyController: _llmApiKeyController,
            modelController: _llmModelController,
            dailyCapController: _llmDailyCapController,
            risk: _risk,
            onSelectRisk: _selectRisk,
            onNext: _nextToReview,
            onBack: () {
              HapticFeedback.selectionClick();
              setState(() => _step = 0);
            },
            c: c,
            text: text,
          );
        } else if (_path == SetupPath.custom) {
          if (_useAiChat) {
            // Tell the AI chat the current bankroll so it can suggest
            // capital-coherent strategies.
            ref
                .read(setupChatProvider.notifier)
                .setSimulationBalance(_simulationBalanceSol);
            // "Talk to Aura" — AI chat for strategy configuration
            stepWidget = SetupChatStep(
              key: const ValueKey('setup-chat'),
              onBack: () {
                HapticFeedback.selectionClick();
                setState(() => _useAiChat = false);
                _persistSetupState();
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
              onTalkToAura: () {
                HapticFeedback.mediumImpact();
                setState(() => _useAiChat = true);
                _persistSetupState();
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
              onEntryScoreChanged: (v) {
                setState(() => _entryScore = v);
                _persistSetupState();
              },
              onMinVolumeChanged: (v) {
                setState(() => _minVolume = v);
                _persistSetupState();
              },
              onMinLiquidityChanged: (v) {
                setState(() => _minLiquidity = v);
                _persistSetupState();
              },
              onMaxLiquidityChanged: (v) {
                setState(() => _maxLiquidity = v);
                _persistSetupState();
              },
              onPositionSizeChanged: _setPositionSize,
              onMaxPositionsChanged: (v) {
                setState(() => _maxConcurrent = v);
                _persistSetupState();
              },
              onBinRangeChanged: (v) {
                setState(() => _binRange = v);
                _persistSetupState();
              },
              onProfitTargetChanged: (v) {
                setState(() => _profitTarget = v);
                _persistSetupState();
              },
              onStopLossChanged: (v) {
                setState(() => _stopLoss = v);
                _persistSetupState();
              },
              onMaxHoldChanged: (v) {
                setState(() => _maxHoldMinutes = v);
                _persistSetupState();
              },
              onDailyLimitChanged: (v) {
                setState(() => _dailyLimit = v);
                _persistSetupState();
              },
              onCooldownChanged: (v) {
                setState(() => _cooldownMinutes = v);
                _persistSetupState();
              },
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
            onDailyLimitChanged: (v) {
              setState(() => _dailyLimit = v);
              _persistSetupState();
            },
            onProfitTargetChanged: (v) {
              setState(() => _profitTarget = v);
              _persistSetupState();
            },
            onStopLossChanged: (v) {
              setState(() => _stopLoss = v);
              _persistSetupState();
            },
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

      default: // step 2 — review, fund & activate
        final useRiskCfg = _path == SetupPath.auraAi || _path == SetupPath.llm;
        final riskCfg = riskConfigs[_risk]!;
        stepWidget = ReviewFundStep(
          key: const ValueKey('review'),
          path: _path ?? SetupPath.auraAi,
          mode: _execMode,
          positionSizeSOL: _positionSize,
          simulationBalanceSOL: _simulationBalanceSol,
          onSimulationBalanceChanged: _setSimulationBalance,
          maxConcurrentPositions: useRiskCfg
              ? riskCfg.maxConcurrentPositions
              : _maxConcurrent,
          profitTargetPercent: _profitTarget,
          stopLossPercent: _stopLoss,
          maxDailyLossSOL: _dailyLimit,
          onBack: () {
            HapticFeedback.selectionClick();
            setState(() => _step = 1);
          },
          onSkip: _skip,
          onActivate: _activate,
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
      child: PopScope(
        // NEVER let the OS pop /setup — there is nothing behind it but app
        // exit. At step > 0 we step backwards through the wizard. At step 0
        // we just nudge with haptic so users know the gesture registered.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_step > 0) {
            HapticFeedback.selectionClick();
            setState(() => _step -= 1);
            _persistSetupState();
          } else {
            HapticFeedback.lightImpact();
          }
        },
        child: Scaffold(
          backgroundColor: c.background,
          body: GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity == null || _step == 0) return;
              // Swipe right → go back
              if (details.primaryVelocity! > 8) {
                HapticFeedback.selectionClick();
                setState(() => _step -= 1);
                _persistSetupState();
              }
            },
            behavior: HitTestBehavior.translucent,
            child: SafeArea(
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
        ),
      ),
    );
  }
}
