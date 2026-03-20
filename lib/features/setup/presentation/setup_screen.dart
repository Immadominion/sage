import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sage/core/models/bot.dart';
import 'package:sage/core/repositories/bot_repository.dart';
import 'package:sage/core/services/api_client.dart';
import 'package:sage/core/services/auth_service.dart';
import 'package:sage/core/theme/app_colors.dart';
import 'package:sage/core/theme/app_theme.dart';

import 'package:sage/core/config/env_config.dart';
import 'package:sage/core/repositories/wallet_repository.dart';
import 'package:sage/core/services/mwa_wallet_service.dart';
import 'package:sage/core/services/chat_persistence.dart';
import 'package:sage/features/setup/models/risk_profile.dart';
import 'package:sage/features/setup/presentation/widgets/custom_strategy_step.dart';
import 'package:sage/features/setup/presentation/widgets/guardrails_step.dart';
import 'package:sage/features/setup/presentation/widgets/path_step.dart';
import 'package:sage/features/setup/presentation/widgets/review_fund_step.dart';
import 'package:sage/features/chat/models/chat_models.dart';
import 'package:sage/features/chat/presentation/widgets/setup_chat_step.dart';

/// Setup Wizard — shown once after first wallet connection.
///
/// Three steps:
///   1. Choose path (Sage AI / Custom) + execution mode radio
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
  bool _useAiChat = false; // true = "Talk to Sage" instead of manual sliders
  Timer? _persistDebounce;
  final TextEditingController _nameController = TextEditingController();

  // ── Sage AI overrides ──
  late double _positionSize = 1.0;
  late double _dailyLimit = 3.0;
  late double _profitTarget = 8.0;
  late double _stopLoss = 6.0;

  // ── Custom strategy fields ──
  double _entryScore = 150;
  double _minVolume = 1000;
  double _minLiquidity = 100;
  double _maxLiquidity = 1000000;
  int _maxConcurrent = 5;
  int _binRange = 10;
  int _maxHoldMinutes = 240;
  int _cooldownMinutes = 79;

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
        _path = saved.path == 'sage-ai' ? SetupPath.sageAi : SetupPath.custom;
      }
      if (saved.execMode != null) {
        _execMode = saved.execMode == 'live'
            ? ExecutionMode.live
            : ExecutionMode.simulation;
      }
      _useAiChat = saved.useAiChat;

      // Restore strategy params
      if (saved.params != null) {
        _applyAiParams(saved.params!);
      }
    });
  }

  @override
  void dispose() {
    _persistDebounce?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  /// Save current setup state — debounced to avoid hammering the server.
  /// Local cache updates immediately; server sync waits 800ms of inactivity.
  void _persistSetupState() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      final persistence = ref.read(chatPersistenceProvider);
      final pathStr = _path == SetupPath.sageAi
          ? 'sage-ai'
          : _path == SetupPath.custom
          ? 'custom'
          : null;
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
    final cfg = riskConfigs[risk]!;
    setState(() {
      _risk = risk;
      _positionSize = cfg.positionSizeSOL;
      _dailyLimit = cfg.maxDailyLossSOL;
      _profitTarget = cfg.profitTargetPercent;
      _stopLoss = cfg.stopLossPercent;
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

  /// Apply AI-extracted strategy parameters to the setup state.
  void _applyAiParams(StrategyParams params) {
    setState(() {
      if (params.entryScoreThreshold != null)
        _entryScore = params.entryScoreThreshold!;
      if (params.minVolume24h != null) _minVolume = params.minVolume24h!;
      if (params.minLiquidity != null) _minLiquidity = params.minLiquidity!;
      if (params.maxLiquidity != null) _maxLiquidity = params.maxLiquidity!;
      if (params.positionSizeSOL != null)
        _positionSize = params.positionSizeSOL!;
      if (params.maxConcurrentPositions != null)
        _maxConcurrent = params.maxConcurrentPositions!;
      if (params.defaultBinRange != null) _binRange = params.defaultBinRange!;
      if (params.profitTargetPercent != null)
        _profitTarget = params.profitTargetPercent!;
      if (params.stopLossPercent != null) _stopLoss = params.stopLossPercent!;
      if (params.maxHoldTimeMinutes != null)
        _maxHoldMinutes = params.maxHoldTimeMinutes!;
      if (params.maxDailyLossSOL != null) _dailyLimit = params.maxDailyLossSOL!;
      if (params.cooldownMinutes != null)
        _cooldownMinutes = params.cooldownMinutes!;
    });
    _persistSetupState();
  }

  Future<void> _skip() async {
    HapticFeedback.selectionClick();
    await _markSetupComplete();
    if (mounted) {
      ref.invalidate(authStateProvider);
      context.go('/');
    }
  }

  /// Sign a transaction via MWA and submit to the backend.
  ///
  /// When [setupLiveBotId] is provided, always uses sign-only + submitSigned
  /// so the backend can trigger `finalizeLiveSession` after confirmation.
  /// Otherwise tries signAndSend first, falling back to sign + submit.
  Future<void> _signAndSubmitWithFallback(
    MwaWalletService mwa,
    WalletRepository walletRepo,
    Uint8List txBytes,
    String cluster, {
    String? setupLiveBotId,
  }) async {
    // For setup-live TXs, always route through backend so it can finalize
    // the session key creation automatically after on-chain confirmation.
    if (setupLiveBotId != null) {
      final signedTxs = await mwa.signTransactions([txBytes], cluster: cluster);
      if (signedTxs.isEmpty) {
        throw Exception('Transaction signing was cancelled');
      }
      final txBase64 = base64Encode(signedTxs.first);

      // Wait for foreground restoration after MWA session closes,
      // then retry submitSigned with exponential backoff.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await walletRepo.submitSigned(
            transactionBase64: txBase64,
            setupLiveBotId: setupLiveBotId,
          );
          return;
        } catch (e) {
          final isNetwork = e.toString().contains('SocketException') ||
              e.toString().contains('Connection refused') ||
              e.toString().contains('connection timeout');
          if (!isNetwork || attempt == 2) rethrow;
          debugPrint('[Setup] submitSigned attempt $attempt failed: $e');
          await Future<void>.delayed(
            Duration(milliseconds: 500 * (attempt + 1)),
          );
        }
      }
      return;
    }

    try {
      final signatures = await mwa.signAndSendTransactions([
        txBytes,
      ], cluster: cluster);
      if (signatures.isEmpty) {
        throw Exception('Transaction was rejected by wallet');
      }
    } catch (e) {
      final msg = e.toString();
      final isSimulationError =
          msg.contains('simulation') ||
          msg.contains('Simulation') ||
          msg.contains('Transaction failed') ||
          msg.contains('failed to send');

      if (!isSimulationError) rethrow;

      debugPrint('[Setup] signAndSend failed ($msg), trying sign + submit');

      final signedTxs = await mwa.signTransactions([txBytes], cluster: cluster);
      if (signedTxs.isEmpty) {
        throw Exception('Transaction signing was cancelled');
      }

      final txBase64 = base64Encode(signedTxs.first);

      // Foreground delay + retry (same MWA background issue).
      await Future<void>.delayed(const Duration(milliseconds: 500));
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await walletRepo.submitSigned(transactionBase64: txBase64);
          return;
        } catch (e) {
          final isNetwork = e.toString().contains('SocketException') ||
              e.toString().contains('Connection refused') ||
              e.toString().contains('connection timeout');
          if (!isNetwork || attempt == 2) rethrow;
          debugPrint('[Setup] submitSigned fallback attempt $attempt failed: $e');
          await Future<void>.delayed(
            Duration(milliseconds: 500 * (attempt + 1)),
          );
        }
      }
    }
  }

  Future<void> _activate(double? depositSol) async {
    if (_isActivating) return;
    setState(() => _isActivating = true);
    HapticFeedback.mediumImpact();

    try {
      final isSageAi = _path == SetupPath.sageAi;
      final strategyMode = isSageAi ? 'sage-ai' : 'rule-based';
      final riskCfg = riskConfigs[_risk]!;
      final isLive = _execMode == ExecutionMode.live;
      final modeName = isLive ? 'live' : 'simulation';

      final walletRepo = ref.read(walletRepositoryProvider);
      final mwa = ref.read(mwaWalletServiceProvider);

      // ── Create bot config ──
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
          'cooldownMinutes': isSageAi ? 79 : _cooldownMinutes,
          'cronIntervalSeconds': 30,
          'simulationBalanceSOL': 20.0,
          'minVolume24h': isSageAi ? 1000.0 : _minVolume,
          'minLiquidity': isSageAi ? 100.0 : _minLiquidity,
          'maxLiquidity': isSageAi ? 1000000.0 : _maxLiquidity,
          'defaultBinRange': isSageAi ? 10 : _binRange,
        },
      );

      await ref.read(botListProvider.notifier).createBot(config);

      // ── Live-mode: ONE MWA signature handles everything ──
      // Backend creates wallet (if needed) + registers agent + deposits
      // trading capital to session signer — all in a single transaction.
      bool liveSetupSucceeded = false;
      if (isLive) {
        final bots = ref.read(botListProvider).value ?? [];
        if (bots.isNotEmpty) {
          final createdBot = bots.last;
          try {
            final setupData = await walletRepo.setupLive(
              botId: createdBot.botId,
              depositSol: depositSol ?? 0,
              dailyLimitSol: _dailyLimit,
              perTxLimitSol: _positionSize,
              sessionMaxAmountSol: _dailyLimit * 30,
              sessionMaxPerTxSol: _positionSize * 2,
            );

            // If already finalized (409 retry), skip signing
            if (setupData['finalized'] != true) {
              final txBase64 = setupData['transaction'] as String;
              final txBytes = Uint8List.fromList(base64Decode(txBase64));
              final network =
                  (setupData['network'] as String?) ?? EnvConfig.solanaNetwork;

              // Single MWA signature — backend handles finalization
              await _signAndSubmitWithFallback(
                mwa,
                walletRepo,
                txBytes,
                network,
                setupLiveBotId: createdBot.botId,
              );
            }
            liveSetupSucceeded = true;
          } catch (e) {
            final msg = e.toString();
            if (msg.contains('409') || msg.contains('already')) {
              liveSetupSucceeded = true;
            } else {
              debugPrint('[Setup] setup-live failed: $e');
            }
          }
        }
      }

      // Auto-start the bot so user sees it running immediately.
      if (!isLive || liveSetupSucceeded) {
        try {
          final bots = ref.read(botListProvider).value ?? [];
          if (bots.isNotEmpty) {
            await ref.read(botRepositoryProvider).startBot(bots.last.botId);
            await ref.read(botListProvider.notifier).refresh();
          }
        } catch (_) {
          // Non-fatal: bot was created successfully, start can be retried.
        }
      }

      await _markSetupComplete();

      if (mounted) {
        HapticFeedback.heavyImpact();
        ref.invalidate(authStateProvider);
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActivating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyActivateError(e)),
            backgroundColor: context.sage.loss,
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
          onModeChanged: (m) {
            HapticFeedback.selectionClick();
            setState(() => _execMode = m);
            _persistSetupState();
          },
          onNext: _nextStep,
          onSkip: _skip,
          nameController: _nameController,
          c: c,
          text: text,
        );
        break;

      case 1: // step 1 — configure strategy
        if (_path == SetupPath.custom) {
          if (_useAiChat) {
            // "Talk to Sage" — AI chat for strategy configuration
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
              onTalkToSage: () {
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
              onPositionSizeChanged: (v) {
                setState(() => _positionSize = v);
                _persistSetupState();
              },
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
            onPositionSizeChanged: (v) {
              setState(() => _positionSize = v);
              _persistSetupState();
            },
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
        final isSageAi = _path == SetupPath.sageAi;
        final riskCfg = riskConfigs[_risk]!;
        stepWidget = ReviewFundStep(
          key: const ValueKey('review'),
          path: _path ?? SetupPath.sageAi,
          mode: _execMode,
          positionSizeSOL: _positionSize,
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
          onSkip: _skip,
          onActivate: _activate,
          isActivating: _isActivating,
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
