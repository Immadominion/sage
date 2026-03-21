import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sage/core/models/bot.dart';
import 'package:sage/core/config/env_config.dart';
import 'package:sage/core/repositories/bot_repository.dart';
import 'package:sage/core/repositories/wallet_repository.dart';
import 'package:sage/core/services/auth_service.dart';
import 'package:sage/core/services/mwa_wallet_service.dart';
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
  double _positionSize = 1.0;
  double _dailyLimit = 3.0;
  double _profitTarget = 8.0;
  double _stopLoss = 6.0;

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
    final cfg = riskConfigs[risk]!;
    setState(() {
      _risk = risk;
      _positionSize = cfg.positionSizeSOL;
      _dailyLimit = cfg.maxDailyLossSOL;
      _profitTarget = cfg.profitTargetPercent;
      _stopLoss = cfg.stopLossPercent;
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
    });
  }

  /// Sign once via MWA, then submit from the backend.
  ///
  /// This avoids wallet-side simulation failures on partially-signed setup
  /// transactions and keeps the user flow to a single approval step.
  Future<void> _signAndSubmitSetupTransaction(
    MwaWalletService mwa,
    WalletRepository walletRepo,
    Uint8List txBytes,
    String cluster,
    String botId,
  ) async {
    final signedTxs = await mwa.signTransactions([txBytes], cluster: cluster);
    if (signedTxs.isEmpty) {
      throw Exception('Transaction signing was cancelled');
    }

    final txBase64 = base64Encode(signedTxs.first);

    // Update status — this step confirms on-chain and can take several seconds
    if (mounted) setState(() => _deployStatus = 'Confirming on-chain…');

    // Wait for foreground restoration after MWA session closes,
    // then retry submitSigned with exponential backoff.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await walletRepo.submitSigned(
          transactionBase64: txBase64,
          setupLiveBotId: botId,
        );
        return;
      } catch (e) {
        final msg = e.toString();
        final isRetryable =
            msg.contains('SocketException') ||
            msg.contains('Connection refused') ||
            msg.contains('connection timeout') ||
            msg.contains('503') ||
            msg.contains('Service Unavailable') ||
            msg.contains('429') ||
            msg.contains('Too Many Requests');
        if (!isRetryable || attempt == 4) rethrow;
        debugPrint('[CreateStrategy] submitSigned attempt $attempt failed: $e');
        await Future<void>.delayed(Duration(milliseconds: 1000 * (attempt + 1)));
      }
    }
  }

  /// Deploy — creates the bot and handles live-mode seal setup.
  ///
  /// For live mode, everything happens in a SINGLE transaction:
  /// wallet creation (if needed) + agent registration + deposit — all in
  /// one MWA signature. The user's [depositSol] goes directly to the
  /// session signer as trading capital.
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

    bool liveSetupSucceeded = false;
    try {
      final isSageAi = _path == SetupPath.sageAi;
      final strategyMode = isSageAi ? 'sage-ai' : 'rule-based';
      final riskCfg = riskConfigs[_risk]!;
      final isLive = _execMode == ExecutionMode.live;
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
          'cooldownMinutes': isSageAi ? 79 : _cooldownMinutes,
          'cronIntervalSeconds': 30,
          'simulationBalanceSOL': 20.0,
          'minVolume24h': isSageAi ? 1000.0 : _minVolume,
          'minLiquidity': isSageAi ? 100.0 : _minLiquidity,
          'maxLiquidity': isSageAi ? 1000000.0 : _maxLiquidity,
          'defaultBinRange': isSageAi ? 10 : _binRange,
        },
      );

      // ── Step 1: Create the bot (skip if already created from a prior attempt) ──
      updateStatus('Creating bot…');
      _createdBot ??= await ref.read(botListProvider.notifier).createBot(config);
      final createdBot = _createdBot!;
      if (createdBot.botId.isEmpty) throw Exception('Bot creation failed');

      // ── Step 2: Live-mode setup — ONE MWA signature ──
      // Backend handles: wallet creation (if needed) + agent registration
      // + deposit goes directly to session signer as trading capital.
      if (isLive) {
        try {
          final walletRepo = ref.read(walletRepositoryProvider);
          final mwa = ref.read(mwaWalletServiceProvider);

          updateStatus('Setting up Seal wallet…');
          final setupData = await walletRepo.setupLive(
            botId: createdBot.botId,
            depositSol: depositSol ?? 0,
            dailyLimitSol: _dailyLimit,
            perTxLimitSol: _positionSize,
            sessionMaxAmountSol: _dailyLimit * 30,
            sessionMaxPerTxSol: _positionSize * 2,
          );

          // If setup was already finalized (409 with finalized: true), skip signing
          if (setupData['finalized'] != true) {
            final txBase64 = setupData['transaction'] as String;
            final txBytes = Uint8List.fromList(base64Decode(txBase64));
            final network =
                (setupData['network'] as String?) ?? EnvConfig.solanaNetwork;

            // Single MWA signature — covers wallet creation, deposit, and agent setup
            updateStatus('Approve in wallet…');
            await _signAndSubmitSetupTransaction(
              mwa,
              ref.read(walletRepositoryProvider),
              txBytes,
              network,
              createdBot.botId,
            );
          }
          liveSetupSucceeded = true;
        } catch (e) {
          final msg = e.toString();
          final isAlreadyConfigured =
              msg.contains('409') || msg.contains('already has agent');
          if (isAlreadyConfigured) {
            liveSetupSucceeded = true;
          } else {
            // Live setup failed (user cancelled MWA, network error, etc.)
            // Bot was created but has no agent/session keys — DON'T auto-start.
            // STAY on this screen so user can tap Deploy again to retry.
            if (mounted) {
              setState(() => _isActivating = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${_friendlyError(e)} Tap Deploy to retry.',
                  ),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
            return;
          }
        }
      }

      // ── Step 3: Auto-start the bot ──
      if (!isLive || liveSetupSucceeded) {
        updateStatus('Starting bot…');
        try {
          await ref.read(botRepositoryProvider).startBot(createdBot.botId);
          await ref.read(botListProvider.notifier).refresh();
        } catch (_) {
          // Non-fatal: bot created, start can be retried from detail screen.
        }
      }

      // Refresh wallet balance so it shows immediately on the detail screen.
      ref.invalidate(walletBalanceProvider);
      // Schedule a second refresh 3s later to catch any RPC cache lag.
      Future.delayed(const Duration(seconds: 3), () {
        try {
          ref.invalidate(walletBalanceProvider);
        } catch (_) {}
      });

      // Ensure setup is marked complete (bot exists → setup is done).
      ref.read(authStateProvider.notifier).markSetupCompleted();

      if (mounted) {
        setState(() => _isActivating = false);
        HapticFeedback.heavyImpact();
        context.pop();
      }
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
    if (msg.contains('wallet not found') ||
        msg.contains('Seal wallet not found')) {
      return 'Seal wallet not set up. Create one in Settings first.';
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
          onModeChanged: (m) {
            HapticFeedback.selectionClick();
            setState(() => _execMode = m);
          },
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
              onPositionSizeChanged: (v) => setState(() => _positionSize = v),
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
            onPositionSizeChanged: (v) => setState(() => _positionSize = v),
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
