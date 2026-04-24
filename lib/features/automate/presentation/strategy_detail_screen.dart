import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:aura/core/models/bot.dart';
import 'package:aura/core/config/live_trading_flags.dart';
import 'package:aura/core/models/bot_event.dart';
import 'package:aura/core/repositories/bot_repository.dart';
import 'package:aura/core/models/wallet.dart';
import 'package:aura/core/repositories/wallet_repository.dart';
import 'package:aura/core/services/event_service.dart';
import 'package:aura/core/theme/app_colors.dart';
import 'package:aura/core/theme/app_radii.dart';
import 'package:aura/core/theme/app_theme.dart';

import 'package:aura/features/automate/presentation/widgets/stat_chip.dart';
import 'package:aura/features/automate/presentation/widgets/live_position_card.dart';
import 'package:aura/features/automate/presentation/widgets/param_row.dart';
import 'package:aura/features/automate/presentation/widgets/pulsing_dot.dart';
import 'package:aura/features/automate/presentation/widgets/edit_config_sheet.dart';
import 'package:rive/rive.dart';
import 'package:aura/shared/widgets/mwa_button_tap_effect.dart';
import 'package:aura/shared/widgets/aura_bottom_sheet.dart';
import 'package:aura/shared/widgets/withdraw_sheet.dart';
import 'package:aura/shared/widgets/deposit_sheet.dart';

/// Bot Detail — Layer 2 of Automate mode.
///
/// Shows a live bot's state, recent actions, PnL, parameters,
/// and controls to start/stop/emergency-stop.
///

/// Extract a human-readable error from API responses / DioExceptions.
String _apiError(Object e) {
  if (e is DioException && e.response?.data is Map) {
    final msg = (e.response!.data as Map)['message'];
    if (msg is String && msg.isNotEmpty) return msg;
  }
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Connection timed out';
      case DioExceptionType.connectionError:
        return 'Cannot reach server';
      default:
        break;
    }
  }
  final s = e.toString();
  // Strip Dart exception class prefixes
  if (s.startsWith('Exception: ')) return s.substring(11);
  return s;
}

/// Convert raw engine lastError strings into user-friendly messages.
String _friendlyLastError(String error) {
  if (error.contains('insufficient_balance:')) {
    // Strip any prefix like "Auto-stopped: " before parsing
    final ibIdx = error.indexOf('insufficient_balance:');
    final payload = error.substring(ibIdx + 'insufficient_balance:'.length);
    final vals = payload.split(':');
    final balance = vals.isNotEmpty ? vals[0].trim() : '?';
    final required = vals.length > 1 ? vals[1].trim() : '?';
    final depositNeeded = vals.length > 2 ? vals[2].trim() : required;
    return 'Deposit at least $depositNeeded SOL to resume trading. '
        '(Current: $balance SOL, needs: $required SOL per position)';
  }
  return error;
}

void _showLiveTradingUnavailableSnackBar(BuildContext context) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(kLiveTradingDisabledReason)));
}

/// Fully wired to real data via [botDetailProvider].
class StrategyDetailScreen extends ConsumerStatefulWidget {
  final String botId;

  const StrategyDetailScreen({super.key, required this.botId});

  @override
  ConsumerState<StrategyDetailScreen> createState() =>
      _StrategyDetailScreenState();
}

class _StrategyDetailScreenState extends ConsumerState<StrategyDetailScreen> {
  bool _isPerformingAction = false;
  Timer? _pollTimer;
  bool _lowBalanceShown = false;

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        ref.invalidate(botDetailProvider(widget.botId));
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _deleteBot() async {
    // Check if this is a live bot — warn about fund recovery
    final botAsync = ref.read(botDetailProvider(widget.botId));
    final isLiveBot = botAsync.value?.mode == BotMode.live;

    // Confirm with bottom sheet — matches Aura design language
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.aura;
        final text = ctx.auraText;
        return Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24.r),
              topRight: Radius.circular(24.r),
            ),
            border: Border(top: BorderSide(color: c.borderSubtle)),
          ),
          padding: EdgeInsets.fromLTRB(
            24.w,
            20.h,
            24.w,
            MediaQuery.of(ctx).padding.bottom + 24.h,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: c.borderSubtle,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              SizedBox(height: 24.h),
              Text(
                'Delete Bot',
                style: text.titleLarge?.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                isLiveBot
                    ? 'This will permanently delete this bot and all its history.\n\nAny SOL remaining in the bot wallet will NOT be returned automatically. Use "Withdraw" from the menu first to recover your funds.\n\nThis action cannot be undone.'
                    : 'This will permanently delete this bot and all its history.\n\nThis action cannot be undone.',
                style: text.bodyMedium?.copyWith(color: c.textSecondary),
              ),
              SizedBox(height: 28.h),
              MWAButtonTapEffect(
                onTap: () => Navigator.pop(ctx, true),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                  decoration: BoxDecoration(
                    color: c.loss.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(color: c.loss.withValues(alpha: 0.35)),
                  ),
                  child: Center(
                    child: Text(
                      'Delete',
                      style: text.titleMedium?.copyWith(
                        color: c.loss,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              MWAButtonTapEffect(
                onTap: () => Navigator.pop(ctx, false),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(color: c.borderSubtle),
                  ),
                  child: Center(
                    child: Text(
                      'Cancel',
                      style: text.titleMedium?.copyWith(color: c.textSecondary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true || _isPerformingAction) return;

    setState(() => _isPerformingAction = true);
    try {
      await ref.read(botListProvider.notifier).deleteBot(widget.botId);
      HapticFeedback.mediumImpact();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bot deleted')));
        // Use go('/') — context.pop() may have nothing to pop to if the user
        // arrived here via context.go() (e.g. from setup screen).
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: ${_apiError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPerformingAction = false);
    }
  }

  void _showEditConfig(Bot bot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EditConfigSheet(
        bot: bot,
        onSave: (config) async {
          try {
            await ref
                .read(botListProvider.notifier)
                .updateConfig(widget.botId, config);
            ref.invalidate(botDetailProvider(widget.botId));
            HapticFeedback.mediumImpact();
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Config updated')));
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
            }
          }
        },
      ),
    );
  }

  Future<void> _startBot() async {
    if (_isPerformingAction) return;
    setState(() => _isPerformingAction = true);
    try {
      final repo = ref.read(botRepositoryProvider);
      final botData = ref.read(botDetailProvider(widget.botId)).value;

      if (botData?.mode == BotMode.live && !kLiveTradingEnabled) {
        _showLiveTradingUnavailableSnackBar(context);
        return;
      }

      // Try starting directly — the backend knows if setup is valid
      await repo.startBot(widget.botId);
      HapticFeedback.mediumImpact();
      ref.invalidate(botDetailProvider(widget.botId));
      ref.read(botListProvider.notifier).refresh();
    } catch (e) {
      final msg = _apiError(e).toLowerCase();
      if (msg.contains('already running')) {
        // Backend state is authoritative; reconcile stale UI state.
        ref.invalidate(botDetailProvider(widget.botId));
        ref.read(botListProvider.notifier).refresh();
        HapticFeedback.selectionClick();
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start: ${_apiError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPerformingAction = false);
    }
  }

  Future<void> _stopBot() async {
    if (_isPerformingAction) return;
    setState(() => _isPerformingAction = true);
    try {
      final repo = ref.read(botRepositoryProvider);
      await repo.stopBot(widget.botId);
      HapticFeedback.mediumImpact();
      ref.invalidate(botDetailProvider(widget.botId));
      ref.read(botListProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to stop: ${_apiError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPerformingAction = false);
    }
  }

  /// Bottom sheet with stop options — replaces the old separate
  /// Emergency Stop button.
  Future<void> _showStopSheet(Bot bot) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.aura;
        final text = ctx.auraText;
        final hasPositions = bot.livePositions.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24.r),
              topRight: Radius.circular(24.r),
            ),
            border: Border(top: BorderSide(color: c.borderSubtle)),
          ),
          padding: EdgeInsets.fromLTRB(
            24.w,
            20.h,
            24.w,
            MediaQuery.of(ctx).padding.bottom + 24.h,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: c.borderSubtle,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              SizedBox(height: 24.h),
              Text(
                'Stop Bot',
                style: text.titleLarge?.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'Choose how to stop this bot.',
                style: text.bodyMedium?.copyWith(color: c.textSecondary),
              ),
              SizedBox(height: 24.h),

              // Option 1 — Stop scanning only
              MWAButtonTapEffect(
                onTap: () => Navigator.pop(ctx, 'stop'),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    vertical: 14.h,
                    horizontal: 16.w,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(color: c.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        PhosphorIconsBold.pause,
                        size: 20.sp,
                        color: c.textSecondary,
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stop Scanning',
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: c.textPrimary,
                              ),
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              'Engine stops. Open positions remain active.',
                              style: text.bodySmall?.copyWith(
                                color: c.textTertiary,
                                fontSize: 12.sp,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 10.h),

              // Option 2 — Close all positions & stop
              MWAButtonTapEffect(
                onTap: () => Navigator.pop(ctx, 'emergency'),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    vertical: 14.h,
                    horizontal: 16.w,
                  ),
                  decoration: BoxDecoration(
                    color: c.loss.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(color: c.loss.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(PhosphorIconsBold.stop, size: 20.sp, color: c.loss),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Close All & Stop',
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: c.loss,
                              ),
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              hasPositions
                                  ? 'Close ${bot.livePositions.length} '
                                        'position${bot.livePositions.length != 1 ? 's' : ''} '
                                        'at market price, then stop.'
                                  : 'Close all positions at market price, then stop.',
                              style: text.bodySmall?.copyWith(
                                color: c.loss.withValues(alpha: 0.7),
                                fontSize: 12.sp,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16.h),

              // Cancel
              MWAButtonTapEffect(
                onTap: () => Navigator.pop(ctx),
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    child: Text(
                      'Cancel',
                      style: text.bodyMedium?.copyWith(color: c.textTertiary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result == null || _isPerformingAction) return;

    if (result == 'stop') {
      await _stopBot();
    } else if (result == 'emergency') {
      await _performEmergencyStop();
    }
  }

  Future<void> _performEmergencyStop() async {
    if (_isPerformingAction) return;
    setState(() => _isPerformingAction = true);
    try {
      final repo = ref.read(botRepositoryProvider);
      await repo.emergencyStop(widget.botId);
      HapticFeedback.heavyImpact();
      ref.invalidate(botDetailProvider(widget.botId));
      ref.read(botListProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Emergency stop failed: ${_apiError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPerformingAction = false);
    }
  }

  /// Show a bottom sheet to fund the bot wallet (live bots only).
  Future<void> _showFundSheet(Bot bot) async {
    if (bot.mode != BotMode.live) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Simulation bots don\'t need real funding'),
        ),
      );
      return;
    }

    if (!kLiveTradingEnabled) {
      _showLiveTradingUnavailableSnackBar(context);
      return;
    }

    // Include rent+fees overhead per position (~0.07 SOL) in recommendation
    final recommended =
        (bot.positionSizeSOL + 0.07) * bot.maxConcurrentPositions;

    final success = await AuraBottomSheet.show<bool>(
      context: context,
      title: 'Fund Wallet',
      builder: (c, text) => DepositSheet(
        botId: widget.botId,
        recommendedSol: recommended,
        minSol: bot.positionSizeSOL + 0.07,
        c: c,
        text: text,
      ),
    );

    if (success == true && mounted) {
      ref.invalidate(walletBalanceProvider(widget.botId));
      ref.invalidate(botDetailProvider(widget.botId));
    }
  }

  /// Show withdraw bottom sheet — pull SOL from Aura wallet back to user.
  Future<void> _showWithdrawSheet() async {
    if (!kLiveTradingEnabled) {
      _showLiveTradingUnavailableSnackBar(context);
      return;
    }

    final walletRepo = ref.read(walletRepositoryProvider);

    // Get current balance for this bot's wallet
    double balance;
    try {
      final wb = await walletRepo.getBalance(widget.botId);
      balance = wb.balanceSOL;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load wallet balance')),
        );
      }
      return;
    }

    if (balance <= 0.003) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No funds available to withdraw')),
        );
      }
      return;
    }

    if (!mounted) return;
    final success = await AuraBottomSheet.show<bool>(
      context: context,
      title: 'Withdraw',
      builder: (c, text) => WithdrawSheet(
        botId: widget.botId,
        availableBalanceSol: balance,
        c: c,
        text: text,
      ),
    );

    if (success == true && mounted) {
      ref.invalidate(walletBalanceProvider(widget.botId));
      ref.invalidate(botDetailProvider(widget.botId));
    }
  }

  /// Convert simulation bot to live mode, then prompt to fund.
  Future<void> _convertToLive() async {
    final botAsync = ref.read(botDetailProvider(widget.botId));
    final bot = botAsync.value;
    if (bot == null) return;

    if (bot.engineRunning) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stop the bot before going live')),
        );
      }
      return;
    }

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final c = ctx.aura;
        final text = ctx.auraText;
        return AlertDialog(
          backgroundColor: c.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
            side: BorderSide(color: c.accent.withValues(alpha: 0.5)),
          ),
          title: Text(
            '⚡ Go Live',
            style: text.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: c.accent,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Convert "${bot.name}" to live trading with REAL funds.',
                style: text.bodyMedium?.copyWith(color: c.textPrimary),
              ),
              SizedBox(height: 8.h),
              Text(
                '• Simulation stats will be reset\n'
                '• A dedicated wallet will be created\n'
                '• You\'ll need to deposit SOL to trade',
                style: text.bodySmall?.copyWith(
                  color: c.textSecondary,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 12.h),
              Text(
                'This cannot be undone.',
                style: text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.redAccent,
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
              child: Text(
                'Go Live',
                style: TextStyle(color: c.accent, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    try {
      final repo = ref.read(botRepositoryProvider);
      final updated = await repo.convertToLive(widget.botId);

      // Refresh detail + list
      ref.invalidate(botDetailProvider(widget.botId));
      ref.read(botListProvider.notifier).refresh();

      if (!mounted) return;

      // Show deposit sheet so user can fund the new live wallet
      final recommended =
          (updated.positionSizeSOL + 0.07) * updated.maxConcurrentPositions;
      await AuraBottomSheet.show<bool>(
        context: context,
        title: 'Fund Your Bot',
        builder: (c, text) => DepositSheet(
          botId: widget.botId,
          recommendedSol: recommended,
          minSol: updated.positionSizeSOL + 0.07,
          c: c,
          text: text,
        ),
      );

      if (mounted) {
        ref.invalidate(walletBalanceProvider(widget.botId));
        ref.invalidate(botDetailProvider(widget.botId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to convert: ${_apiError(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.aura;
    final text = context.auraText;
    final botAsync = ref.watch(botDetailProvider(widget.botId));

    // Listen to SSE events — auto-refresh when this bot's state changes
    ref.listen<AsyncValue<BotEvent>>(botEventStreamProvider, (_, next) {
      next.whenData((event) {
        if (event.botId != widget.botId) return;

        if (event.isBotStarted ||
            event.isBotStopped ||
            event.isBotError ||
            event.isPositionOpened ||
            event.isPositionClosed ||
            event.isScanCompleted) {
          ref.invalidate(botDetailProvider(widget.botId));
          ref.read(botListProvider.notifier).refresh();
        }

        // Start/stop polling alongside engine lifecycle
        if (event.isBotStarted) {
          _startPolling();
          _lowBalanceShown = false;
        } else if (event.isBotStopped) {
          _stopPolling();
        }

        // Insufficient balance toast — only show once per engine run
        if (event.isBotError && !_lowBalanceShown) {
          final errMsg = event.data?['error'] as String? ?? '';
          if (errMsg.contains('insufficient_balance') && mounted) {
            _lowBalanceShown = true;
            // Parse deposit amount from error format insufficient_balance:<bal>:<req>:<needed>
            final parts = errMsg.split(':');
            final balIdx = parts.indexOf('insufficient_balance');
            final needed = parts.length > balIdx + 3 ? parts[balIdx + 3] : '?';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Low balance — deposit at least $needed SOL to open more positions.',
                ),
                duration: const Duration(seconds: 8),
                action: SnackBarAction(
                  label: 'Fund',
                  onPressed: () {
                    final bot = ref.read(botDetailProvider(widget.botId)).value;
                    if (bot != null) _showFundSheet(bot);
                  },
                ),
              ),
            );
          }
        }
      });
    });

    // Start/stop polling based on current bot state
    final currentBot = botAsync.whenOrNull(data: (b) => b);
    if (currentBot != null && currentBot.engineRunning && _pollTimer == null) {
      _startPolling();
    } else if (currentBot != null &&
        !currentBot.engineRunning &&
        _pollTimer != null) {
      _stopPolling();
    }

    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/');
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: c.background,
          body: botAsync.when(
            skipLoadingOnReload: true,
            loading: () =>
                Center(child: CircularProgressIndicator(color: c.accent)),
            error: (err, _) => _buildError(c, text, err),
            data: (bot) => _buildBody(context, c, text, bot),
          ),
        ),
      ),
    );
  }

  Widget _buildError(AuraColors c, TextTheme text, Object err) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(botDetailProvider(widget.botId));
        await Future.delayed(const Duration(milliseconds: 400));
      },
      color: c.accent,
      backgroundColor: c.surface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background texture — same treatment as connect wallet screen
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.10,
                child: Image.asset(
                  'assets/images/bg-texture.png',
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),

          // Scrollable content — required for RefreshIndicator to trigger
          ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.82,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 404 Rive animation
                    SizedBox(width: 300.w, height: 400.w, child: _ErrorRive()),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AuraColors c,
    TextTheme text,
    Bot bot,
  ) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    // Status indicators
    final isRunning = bot.engineRunning;
    final statusColor = isRunning
        ? c.profit
        : bot.status == BotStatus.error
        ? c.loss
        : c.textTertiary;
    final statusLabel = isRunning
        ? 'Running'
        : bot.status == BotStatus.error
        ? 'Error'
        : bot.status == BotStatus.stopping
        ? 'Stopping'
        : bot.status == BotStatus.starting
        ? 'Starting'
        : 'Stopped';
    final isTransitioning =
        bot.status == BotStatus.starting || bot.status == BotStatus.stopping;

    // PnL
    final pnl = bot.performanceSummary?.totalPnlSol ?? bot.totalPnlSOL;
    final pnlColor = pnl > 0
        ? c.profit
        : pnl < 0
        ? c.loss
        : c.textSecondary;
    final pnlStr = pnl > 0
        ? '+${pnl.toStringAsFixed(4)} SOL'
        : pnl < 0
        ? '${pnl.toStringAsFixed(4)} SOL'
        : '0.0000 SOL';

    // Strategy mode label
    final strategyLabel = bot.strategyMode == StrategyMode.ruleBased
        ? 'Rule-Based'
        : bot.strategyMode == StrategyMode.auraAi
        ? 'Aura AI'
        : 'Hybrid';

    // Engine stats
    final stats = bot.engineStats;
    final totalScans = stats?.totalScans ?? 0;
    final posOpened = stats?.positionsOpened ?? 0;
    final posClosed = stats?.positionsClosed ?? 0;
    final waitingForMlEntry =
        bot.engineRunning &&
        bot.strategyMode == StrategyMode.auraAi &&
        posOpened == 0 &&
        totalScans > 0 &&
        bot.lastError == null;
    final mlThresholdLabel = bot.mlThreshold != null
        ? bot.mlThreshold!.toStringAsFixed(4)
        : 'model default';

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(botDetailProvider(widget.botId));
        // Give the provider time to re-fetch so the indicator doesn't
        // vanish instantly.
        await Future.delayed(const Duration(milliseconds: 500));
      },
      color: c.accent,
      backgroundColor: c.surface,
      child: Column(
        children: [
          // ── Top bar — profile-style circular icons ──
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, topPad + 12.h, 20.w, 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    if (Navigator.of(context).canPop()) {
                      context.pop();
                    } else {
                      context.go('/');
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.surface,
                      border: Border.all(color: c.borderSubtle, width: 1),
                    ),
                    child: Icon(
                      PhosphorIconsBold.arrowLeft,
                      size: 20.sp,
                      color: c.textSecondary,
                    ),
                  ),
                ),
                const Spacer(),
                // Play / Stop action icon
                if (_isPerformingAction)
                  SizedBox(
                    width: 36.w,
                    height: 36.w,
                    child: Padding(
                      padding: EdgeInsets.all(8.w),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.accent,
                      ),
                    ),
                  )
                else if (!isTransitioning) ...[
                  if (!isRunning)
                    MWAButtonTapEffect(
                      onTap: _startBot,
                      child: Container(
                        padding: EdgeInsets.all(8.w),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.profit.withValues(alpha: 0.15),
                          border: Border.all(
                            color: c.profit.withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          PhosphorIconsBold.play,
                          size: 20.sp,
                          color: c.profit,
                        ),
                      ),
                    ),
                  if (isRunning)
                    MWAButtonTapEffect(
                      onTap: () => _showStopSheet(bot),
                      child: Container(
                        padding: EdgeInsets.all(8.w),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.loss.withValues(alpha: 0.12),
                          border: Border.all(
                            color: c.loss.withValues(alpha: 0.35),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          PhosphorIconsBold.stop,
                          size: 20.sp,
                          color: c.loss,
                        ),
                      ),
                    ),
                ],
                SizedBox(width: 8.w),
                // More menu (edit / delete)
                PopupMenuButton<String>(
                  icon: Icon(
                    PhosphorIconsBold.dotsThreeVertical,
                    size: 22.sp,
                    color: c.textSecondary,
                  ),
                  color: c.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    side: BorderSide(color: c.borderSubtle),
                  ),
                  onSelected: (value) {
                    if (value == 'edit') {
                      final botAsync = ref.read(
                        botDetailProvider(widget.botId),
                      );
                      botAsync.whenData((bot) {
                        if (bot.engineRunning) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Stop the bot before editing config',
                              ),
                            ),
                          );
                        } else {
                          _showEditConfig(bot);
                        }
                      });
                    } else if (value == 'fund') {
                      final botAsync = ref.read(
                        botDetailProvider(widget.botId),
                      );
                      botAsync.whenData((bot) => _showFundSheet(bot));
                    } else if (value == 'withdraw') {
                      _showWithdrawSheet();
                    } else if (value == 'go_live') {
                      _convertToLive();
                    } else if (value == 'delete') {
                      _deleteBot();
                    }
                  },
                  itemBuilder: (ctx) {
                    final botData = ref.read(botDetailProvider(widget.botId));
                    final isLiveBot = botData.value?.mode == BotMode.live;

                    return [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(
                              PhosphorIconsBold.pencilSimple,
                              size: 18.sp,
                              color: c.textSecondary,
                            ),
                            SizedBox(width: 8.w),
                            Text(
                              'Edit',
                              style: TextStyle(color: c.textPrimary),
                            ),
                          ],
                        ),
                      ),
                      if (isLiveBot && kLiveTradingEnabled)
                        PopupMenuItem(
                          value: 'fund',
                          child: Row(
                            children: [
                              Icon(
                                PhosphorIconsBold.wallet,
                                size: 18.sp,
                                color: c.accent,
                              ),
                              SizedBox(width: 8.w),
                              Text(
                                'Fund Wallet',
                                style: TextStyle(color: c.accent),
                              ),
                            ],
                          ),
                        ),
                      if (isLiveBot && kLiveTradingEnabled)
                        PopupMenuItem(
                          value: 'withdraw',
                          child: Row(
                            children: [
                              Icon(
                                PhosphorIconsBold.arrowUp,
                                size: 18.sp,
                                color: c.textSecondary,
                              ),
                              SizedBox(width: 8.w),
                              Text(
                                'Withdraw',
                                style: TextStyle(color: c.textPrimary),
                              ),
                            ],
                          ),
                        ),
                      if (!isLiveBot && kLiveTradingEnabled)
                        PopupMenuItem(
                          value: 'go_live',
                          child: Row(
                            children: [
                              Icon(
                                PhosphorIconsBold.lightning,
                                size: 18.sp,
                                color: c.accent,
                              ),
                              SizedBox(width: 8.w),
                              Text(
                                'Go Live',
                                style: TextStyle(color: c.accent),
                              ),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              PhosphorIconsBold.trash,
                              size: 18.sp,
                              color: c.loss,
                            ),
                            SizedBox(width: 8.w),
                            Text('Delete', style: TextStyle(color: c.loss)),
                          ],
                        ),
                      ),
                    ];
                  },
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms),

          // ── Content ──
          Expanded(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(28.w, 24.h, 28.w, bottomPad + 24.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status indicator + mode badge
                  Row(
                    children: [
                      if (isRunning)
                        PulsingDot(color: statusColor, size: 8)
                      else
                        Container(
                          width: 8.w,
                          height: 8.w,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      SizedBox(width: 10.w),
                      Text(
                        statusLabel,
                        style: text.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.w,
                          vertical: 4.h,
                        ),
                        decoration: BoxDecoration(
                          color: c.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Text(
                          strategyLabel,
                          style: text.labelSmall?.copyWith(
                            color: c.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.sp,
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 12.h),

                  // Bot name
                  Text(
                    bot.name,
                    style: text.displayMedium?.copyWith(letterSpacing: -0.8),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    '${bot.mode.name} · ${bot.positionSizeSOL.toStringAsFixed(1)} SOL per position',
                    style: text.titleMedium?.copyWith(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color: c.textSecondary,
                    ),
                  ),

                  // ── Setup Required Banner ──
                  // Shown when a live bot has no agent/session keys —
                  // the signing step was interrupted during creation.
                  if (bot.mode == BotMode.live &&
                      !kLiveTradingEnabled &&
                      !isRunning) ...[
                    SizedBox(height: 16.h),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: 12.w,
                        vertical: 10.h,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: c.borderSubtle),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            PhosphorIconsBold.info,
                            size: 18.sp,
                            color: c.textSecondary,
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: Text(
                              kLiveTradingDisabledReason,
                              style: text.bodySmall?.copyWith(
                                color: c.textSecondary,
                                fontSize: 12.sp,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  SizedBox(height: 28.h),

                  // ── P&L — inline metric on dark canvas ──
                  Text(
                    'NET P&L',
                    style: text.titleSmall?.copyWith(
                      fontSize: 10.sp,
                      letterSpacing: 1.5,
                      color: c.textTertiary,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    pnlStr,
                    style: text.displayMedium?.copyWith(
                      letterSpacing: -0.5,
                      color: pnlColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    '${bot.totalTrades} trades · ${bot.winRate.toStringAsFixed(0)}% win rate',
                    style: text.bodySmall?.copyWith(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                      color: c.textSecondary,
                    ),
                  ),

                  // ── PnL sparkline placeholder (audit §5.7) ──
                  // Deferred: backend doesn't expose a daily PnL series yet.
                  // When `/bot/:id/pnl-history` lands, drop a sparkline here
                  // (single line, semantic colour, ~24 px tall).
                  SizedBox(height: 28.h),

                  // ── Strategy Shape mini-card (audit §5.7) ──
                  // Symbolic preview of this bot's bin distribution — lets
                  // the operator see the configured shape at a glance.
                  Text(
                    'STRATEGY SHAPE',
                    style: text.titleSmall?.copyWith(
                      fontSize: 10.sp,
                      letterSpacing: 1.5,
                      color: c.textTertiary,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  _StrategyShapeCard(
                    binRange: bot.defaultBinRange,
                    c: c,
                    text: text,
                  ),

                  SizedBox(height: 28.h),

                  // ── Engine Stats (if running) ──
                  if (stats != null) ...[
                    Text(
                      'ENGINE',
                      style: text.titleSmall?.copyWith(
                        fontSize: 10.sp,
                        color: c.textTertiary,
                      ),
                    ),
                    SizedBox(height: 14.h),
                    Row(
                      children: [
                        StatChip(
                          label: 'Scans',
                          value: '$totalScans',
                          c: c,
                          text: text,
                        ),
                        SizedBox(width: 24.w),
                        StatChip(
                          label: 'Opened',
                          value: '$posOpened',
                          c: c,
                          text: text,
                        ),
                        SizedBox(width: 24.w),
                        StatChip(
                          label: 'Closed',
                          value: '$posClosed',
                          c: c,
                          text: text,
                        ),
                        SizedBox(width: 24.w),
                        StatChip(
                          label: 'Active',
                          value: '${bot.activePositionCount}',
                          c: c,
                          text: text,
                        ),
                      ],
                    ),
                    SizedBox(height: 28.h),
                  ],

                  // ── Live Positions ──
                  if (bot.livePositions.isNotEmpty) ...[
                    Text(
                      'ACTIVE POSITIONS',
                      style: text.titleSmall?.copyWith(
                        fontSize: 10.sp,
                        color: c.textTertiary,
                      ),
                    ),
                    SizedBox(height: 14.h),
                    ...bot.livePositions.map(
                      (pos) => GestureDetector(
                        onTap: () => context.push('/position/${pos.id}'),
                        child: LivePositionCard(
                          position: pos,
                          c: c,
                          text: text,
                        ),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    GestureDetector(
                      onTap: () => context.push('/history'),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'View Position History',
                            style: text.bodySmall?.copyWith(
                              color: c.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 4.w),
                          Icon(
                            PhosphorIconsBold.arrowRight,
                            size: 14.sp,
                            color: c.accent,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 10.h),
                    GestureDetector(
                      onTap: () => context.push('/decisions/${bot.botId}'),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'View Decision Log',
                            style: text.bodySmall?.copyWith(
                              color: c.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 4.w),
                          Icon(
                            PhosphorIconsBold.arrowRight,
                            size: 14.sp,
                            color: c.accent,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 24.h),
                  ],

                  // ── Wallet (elevated above PARAMETERS — live mode only) ──
                  // Previously this lived at the bottom of the page so users
                  // had to scroll past every param + position before they
                  // could see how much they had. With the Smart Wallet
                  // (Jupiter-powered) it's now the primary call-to-action.
                  if (bot.mode == BotMode.live && kLiveTradingEnabled) ...[
                    _WalletSection(
                      bot: bot,
                      onDeposit: () => _showFundSheet(bot),
                      onWithdraw: () => _showWithdrawSheet(),
                    ),
                    SizedBox(height: 28.h),
                  ] else if (bot.mode == BotMode.live) ...[
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(14.w),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: c.borderSubtle),
                      ),
                      child: Text(
                        'Live wallet details will appear here when live trading is enabled.',
                        style: text.bodySmall?.copyWith(
                          color: c.textSecondary,
                          fontSize: 12.sp,
                          height: 1.5,
                        ),
                      ),
                    ),
                    SizedBox(height: 28.h),
                  ],

                  // ── Parameters ──
                  Text(
                    'PARAMETERS',
                    style: text.titleSmall?.copyWith(
                      fontSize: 10.sp,
                      color: c.textTertiary,
                    ),
                  ),
                  SizedBox(height: 14.h),
                  ParamRow(
                    label: 'Entry Threshold',
                    value: '${bot.entryScoreThreshold.toStringAsFixed(0)}%',
                  ),
                  if (bot.strategyMode == StrategyMode.auraAi ||
                      bot.strategyMode == StrategyMode.both) ...[
                    Divider(height: 1, color: c.borderSubtle),
                    ParamRow(label: 'ML Threshold', value: mlThresholdLabel),
                  ],
                  Divider(height: 1, color: c.borderSubtle),
                  ParamRow(
                    label: 'Position Size',
                    value: '${bot.positionSizeSOL.toStringAsFixed(1)} SOL',
                  ),
                  Divider(height: 1, color: c.borderSubtle),
                  ParamRow(
                    label: 'Max Concurrent',
                    value: '${bot.maxConcurrentPositions}',
                  ),
                  Divider(height: 1, color: c.borderSubtle),
                  ParamRow(
                    label: 'Cooldown',
                    value: '${bot.cooldownMinutes} min',
                  ),
                  Divider(height: 1, color: c.borderSubtle),
                  ParamRow(
                    label: 'Stop Loss',
                    value: '-${bot.stopLossPercent.toStringAsFixed(1)}%',
                  ),
                  Divider(height: 1, color: c.borderSubtle),
                  ParamRow(
                    label: 'Profit Target',
                    value: '+${bot.profitTargetPercent.toStringAsFixed(1)}%',
                  ),
                  Divider(height: 1, color: c.borderSubtle),
                  ParamRow(
                    label: 'Max Hold Time',
                    value: '${bot.maxHoldTimeMinutes} min',
                  ),
                  Divider(height: 1, color: c.borderSubtle),
                  ParamRow(
                    label: 'Scan Interval',
                    value: '${bot.cronIntervalSeconds}s',
                  ),

                  if (waitingForMlEntry) ...[
                    SizedBox(height: 24.h),
                    Text(
                      'LATEST NOTE',
                      style: text.titleSmall?.copyWith(
                        fontSize: 10.sp,
                        color: c.textSecondary,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12.w),
                      child: Text(
                        'Aura AI is scanning normally, but no pool has cleared the $mlThresholdLabel ML threshold yet. The bot will stay in cash until a stronger setup appears.',
                        style: text.bodySmall?.copyWith(
                          color: c.textSecondary,
                          fontSize: 12.sp,
                        ),
                      ),
                    ),
                  ],

                  if (bot.lastError != null &&
                      bot.status != BotStatus.running) ...[
                    SizedBox(height: 24.h),
                    Text(
                      'LATEST NOTE',
                      style: text.titleSmall?.copyWith(
                        fontSize: 10.sp,
                        color: c.textSecondary,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12.w),
                      child: Text(
                        _friendlyLastError(bot.lastError!),
                        style: text.bodySmall?.copyWith(
                          color: c.textSecondary,
                          fontSize: 12.sp,
                        ),
                      ),
                    ),
                    if (bot.lastError!.contains('insufficient_balance'))
                      Padding(
                        padding: EdgeInsets.only(top: 4.h),
                        child: Text(
                          'After funding, tap Start to resume.',
                          style: text.bodySmall?.copyWith(
                            color: c.textSecondary,
                            fontSize: 11.sp,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],

                  // ── Bot Wallet now rendered ABOVE Parameters; see top of column. ──
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Smart Wallet panel (Jupiter-powered)
// Shows SOL + every SPL token in the bot wallet with USD values, plus
// a "Sweep stranded tokens" CTA when there's value beyond native SOL.
// ═══════════════════════════════════════════════════════════════

class _WalletSection extends ConsumerWidget {
  final Bot bot;
  final VoidCallback onDeposit;
  final VoidCallback onWithdraw;

  const _WalletSection({
    required this.bot,
    required this.onDeposit,
    required this.onWithdraw,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.aura;
    final text = context.auraText;
    final addr = bot.walletAddress ?? '';
    final shortAddr = addr.length > 8
        ? '${addr.substring(0, 4)}...${addr.substring(addr.length - 4)}'
        : addr;
    final portfolioAsync = ref.watch(walletPortfolioProvider(bot.botId));

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(context.auraRadii.lg),
        border: Border.all(color: c.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'SMART WALLET',
                style: text.titleSmall?.copyWith(
                  color: c.textTertiary,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.sp,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () =>
                    ref.invalidate(walletPortfolioProvider(bot.botId)),
                child: Icon(
                  PhosphorIconsBold.arrowClockwise,
                  size: 14.sp,
                  color: c.textTertiary,
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          if (addr.isNotEmpty)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: addr));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Wallet address copied')),
                );
              },
              child: Row(
                children: [
                  Icon(PhosphorIconsBold.wallet,
                      size: 14.sp, color: c.textTertiary),
                  SizedBox(width: 8.w),
                  Text(
                    shortAddr,
                    style: text.bodySmall?.copyWith(
                      color: c.textSecondary,
                      fontSize: 12.sp,
                    ),
                  ),
                  SizedBox(width: 4.w),
                  Icon(PhosphorIconsBold.copy,
                      size: 12.sp, color: c.textTertiary),
                ],
              ),
            ),
          SizedBox(height: 14.h),
          portfolioAsync.when(
            skipLoadingOnReload: true,
            loading: () => Padding(
              padding: EdgeInsets.symmetric(vertical: 18.h),
              child: Center(
                child: SizedBox(
                  width: 18.sp,
                  height: 18.sp,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.accent,
                  ),
                ),
              ),
            ),
            error: (_, _) => GestureDetector(
              onTap: () =>
                  ref.invalidate(walletPortfolioProvider(bot.botId)),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 14.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(PhosphorIconsBold.arrowClockwise,
                        size: 14.sp, color: c.textTertiary),
                    SizedBox(width: 6.w),
                    Text(
                      'Tap to retry',
                      style: text.bodySmall?.copyWith(
                        color: c.textTertiary,
                        fontSize: 12.sp,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            data: (portfolio) =>
                _buildPortfolioBody(context, ref, portfolio, c, text),
          ),
          SizedBox(height: 14.h),
          // Deposit / Withdraw buttons (always visible).
          Row(
            children: [
              Expanded(
                child: MWAButtonTapEffect(
                  onTap: onDeposit,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 10.h),
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10.r),
                      border:
                          Border.all(color: c.accent.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(PhosphorIconsBold.arrowDown,
                            size: 14.sp, color: c.accent),
                        SizedBox(width: 6.w),
                        Text(
                          'Deposit',
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: c.accent,
                            fontSize: 13.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: MWAButtonTapEffect(
                  onTap: onWithdraw,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 10.h),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: c.borderSubtle),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(PhosphorIconsBold.arrowUp,
                            size: 14.sp, color: c.textSecondary),
                        SizedBox(width: 6.w),
                        Text(
                          'Withdraw',
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                            fontSize: 13.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioBody(
    BuildContext context,
    WidgetRef ref,
    WalletPortfolio portfolio,
    AuraColors c,
    TextTheme text,
  ) {
    final usd = portfolio.totalUsdValue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Total value (the headline number).
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '\$${usd.toStringAsFixed(2)}',
              style: text.headlineSmall?.copyWith(
                fontSize: 26.sp,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            SizedBox(width: 8.w),
            Text(
              'total value',
              style: text.bodySmall?.copyWith(
                color: c.textTertiary,
                fontSize: 12.sp,
              ),
            ),
          ],
        ),
        SizedBox(height: 4.h),
        // SOL row (always shown).
        Padding(
          padding: EdgeInsets.symmetric(vertical: 6.h),
          child: Row(
            children: [
              Container(
                width: 24.w,
                height: 24.w,
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                alignment: Alignment.center,
                child: Text(
                  'S',
                  style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: c.accent,
                    fontSize: 11.sp,
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  'SOL',
                  style: text.titleSmall?.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.sp,
                  ),
                ),
              ),
              Text(
                '${portfolio.sol.amount.toStringAsFixed(4)} SOL',
                style: text.bodySmall?.copyWith(
                  color: c.textPrimary,
                  fontSize: 12.sp,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              SizedBox(width: 8.w),
              SizedBox(
                width: 64.w,
                child: Text(
                  '\$${portfolio.sol.usdValue.toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  style: text.bodySmall?.copyWith(
                    color: c.textSecondary,
                    fontSize: 12.sp,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Token rows.
        ...portfolio.tokens.take(8).map(
              (t) => Padding(
                padding: EdgeInsets.symmetric(vertical: 6.h),
                child: Row(
                  children: [
                    Container(
                      width: 24.w,
                      height: 24.w,
                      decoration: BoxDecoration(
                        color: c.surfaceElevated,
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        t.symbol.isNotEmpty
                            ? t.symbol.substring(0, 1).toUpperCase()
                            : '?',
                        style: text.bodySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: c.textSecondary,
                          fontSize: 11.sp,
                        ),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              t.symbol.isNotEmpty ? t.symbol : 'Unknown',
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall?.copyWith(
                                color: c.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.sp,
                              ),
                            ),
                          ),
                          if (t.isVerified) ...[
                            SizedBox(width: 4.w),
                            Icon(
                              PhosphorIconsBold.sealCheck,
                              size: 12.sp,
                              color: c.accent,
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      _fmtAmount(t.amount),
                      style: text.bodySmall?.copyWith(
                        color: c.textPrimary,
                        fontSize: 12.sp,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    SizedBox(width: 8.w),
                    SizedBox(
                      width: 64.w,
                      child: Text(
                        t.usdPrice == null
                            ? '—'
                            : '\$${t.usdValue.toStringAsFixed(2)}',
                        textAlign: TextAlign.right,
                        style: text.bodySmall?.copyWith(
                          color: t.swappable
                              ? c.textSecondary
                              : c.textTertiary,
                          fontSize: 12.sp,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        if (portfolio.tokens.length > 8)
          Padding(
            padding: EdgeInsets.only(top: 4.h),
            child: Text(
              '+${portfolio.tokens.length - 8} more',
              style: text.bodySmall?.copyWith(
                color: c.textTertiary,
                fontSize: 11.sp,
              ),
            ),
          ),
        // Sweep CTA — only when there are stranded swappable tokens.
        if (portfolio.hasSweepableTokens) ...[
          SizedBox(height: 12.h),
          MWAButtonTapEffect(
            onTap: () => _confirmSweep(context, ref, portfolio),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 14.w),
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: c.accent.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(PhosphorIconsBold.lightning,
                      size: 16.sp, color: c.accent),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sweep \$${portfolio.sweepableUsdValue.toStringAsFixed(2)} of stranded tokens',
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: c.accent,
                            fontSize: 13.sp,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          'Auto-swap to SOL via Jupiter, then withdraw to your wallet',
                          style: text.bodySmall?.copyWith(
                            color: c.textSecondary,
                            fontSize: 11.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(PhosphorIconsBold.arrowRight,
                      size: 14.sp, color: c.accent),
                ],
              ),
            ),
          ),
        ],
        if (!portfolio.jupiterEnabled)
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: Text(
              'USD prices unavailable — Smart Wallet routing offline',
              style: text.bodySmall?.copyWith(
                color: c.textTertiary,
                fontSize: 10.5.sp,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  static String _fmtAmount(double v) {
    if (v >= 1000) return v.toStringAsFixed(2);
    if (v >= 1) return v.toStringAsFixed(4);
    if (v >= 0.0001) return v.toStringAsFixed(6);
    return v.toStringAsExponential(2);
  }

  Future<void> _confirmSweep(
    BuildContext context,
    WidgetRef ref,
    WalletPortfolio portfolio,
  ) async {
    final c = context.aura;
    final text = context.auraText;
    final swappable = portfolio.tokens.where((t) => t.swappable).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: BorderSide(color: c.accent.withValues(alpha: 0.3)),
        ),
        title: Text(
          'Sweep stranded tokens',
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'These tokens will be swapped to SOL via Jupiter and then transferred to your connected wallet:',
              style: text.bodyMedium?.copyWith(color: c.textSecondary),
            ),
            SizedBox(height: 12.h),
            ...swappable.take(6).map(
                  (t) => Padding(
                    padding: EdgeInsets.symmetric(vertical: 4.h),
                    child: Row(
                      children: [
                        Text(
                          '${_fmtAmount(t.amount)} ${t.symbol}',
                          style: text.bodySmall?.copyWith(
                            color: c.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '\$${t.usdValue.toStringAsFixed(2)}',
                          style: text.bodySmall?.copyWith(
                            color: c.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            if (swappable.length > 6)
              Text(
                '+${swappable.length - 6} more',
                style: text.bodySmall?.copyWith(color: c.textTertiary),
              ),
            SizedBox(height: 12.h),
            Text(
              'Estimated value: \$${portfolio.sweepableUsdValue.toStringAsFixed(2)}',
              style: text.bodyMedium?.copyWith(
                color: c.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Swap routes use Jupiter\'s real-time aggregator. Slippage is auto-managed (RTSE).',
              style: text.bodySmall?.copyWith(
                color: c.textTertiary,
                fontSize: 11.sp,
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
            child: Text(
              'Sweep & Withdraw',
              style: TextStyle(
                color: c.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sweeping tokens via Jupiter…'),
        duration: Duration(seconds: 4),
      ),
    );

    try {
      final repo = ref.read(walletRepositoryProvider);
      final result = await repo.sweepWallet(bot.botId);
      if (!context.mounted) return;

      ref.invalidate(walletPortfolioProvider(bot.botId));
      ref.invalidate(walletBalanceProvider(bot.botId));
      ref.invalidate(aggregateBalancesProvider);

      final swept = result.totalSwappedSOL;
      final withdrawn = result.withdraw?.amountSOL ?? 0;
      final failed = result.outcomes.where((o) => !o.success).toList();
      final summary = withdrawn > 0
          ? 'Swept ${result.swappedTokenCount} tokens → ${swept.toStringAsFixed(4)} SOL · withdrew ${withdrawn.toStringAsFixed(4)} SOL'
          : 'Swept ${result.swappedTokenCount} tokens → ${swept.toStringAsFixed(4)} SOL';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed.isEmpty
                ? summary
                : '$summary · ${failed.length} skipped',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
      HapticFeedback.heavyImpact();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sweep failed: ${e.toString().split('\n').first}')),
      );
    }
  }
}

// ══════════════════════════════════════════════════════════════════
// Phase 11 (audit §5.7) — Strategy Shape mini-card
// ══════════════════════════════════════════════════════════════════

class _StrategyShapeCard extends StatelessWidget {
  final int binRange;
  final AuraColors c;
  final TextTheme text;

  const _StrategyShapeCard({
    required this.binRange,
    required this.c,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 14.h),
      decoration: ShapeDecoration(
        color: c.surface,
        shape: ContinuousRectangleBorder(
          borderRadius: BorderRadius.circular(context.auraRadii.lg),
          side: BorderSide(color: c.borderSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Bin range ±$binRange',
                style: text.titleMedium?.copyWith(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                'Concentrated liquidity',
                style: text.labelSmall?.copyWith(
                  fontSize: 11.sp,
                  color: c.textTertiary,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          SizedBox(
            height: 48.h,
            child: CustomPaint(
              size: Size.infinite,
              painter: _StrategyShapePainter(
                binRange: binRange,
                shadeColor: c.accent.withValues(alpha: 0.18),
                binColor: c.borderSubtle,
                centerColor: c.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StrategyShapePainter extends CustomPainter {
  final int binRange;
  final Color shadeColor;
  final Color binColor;
  final Color centerColor;

  _StrategyShapePainter({
    required this.binRange,
    required this.shadeColor,
    required this.binColor,
    required this.centerColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final windowBins = binRange.clamp(2, 60);
    final totalBins = (windowBins * 2 + windowBins).clamp(8, 120);
    final binW = size.width / totalBins;
    final centerX = size.width / 2;
    final midY = size.height / 2;
    final maxBarH = size.height * 0.85;

    final shadeRect = Rect.fromLTWH(
      centerX - windowBins * binW,
      0,
      windowBins * 2 * binW,
      size.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(shadeRect, const Radius.circular(4)),
      Paint()..color = shadeColor,
    );

    final binPaint = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < totalBins; i++) {
      final x = (i + 0.5) * binW;
      final binIndex = i - totalBins ~/ 2;
      final inside = binIndex.abs() <= windowBins;
      final h = inside
          ? maxBarH * (1 - binIndex.abs() / (windowBins + 1))
          : maxBarH * 0.18;
      binPaint.color = inside ? centerColor.withValues(alpha: 0.55) : binColor;
      canvas.drawLine(
        Offset(x, midY - h / 2),
        Offset(x, midY + h / 2),
        binPaint,
      );
    }

    canvas.drawLine(
      Offset(centerX, 0),
      Offset(centerX, size.height),
      Paint()
        ..color = centerColor
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _StrategyShapePainter old) =>
      old.binRange != binRange || old.centerColor != centerColor;
}

// ──────────────────────────────────────────────────────────────────────────────
// 404 Rive animation — used by _buildError
// ──────────────────────────────────────────────────────────────────────────────

class _ErrorRive extends StatefulWidget {
  const _ErrorRive();

  @override
  State<_ErrorRive> createState() => _ErrorRiveState();
}

class _ErrorRiveState extends State<_ErrorRive> {
  late final FileLoader _loader;

  @override
  void initState() {
    super.initState();
    _loader = FileLoader.fromAsset(
      'assets/animation/rive/404-error.riv',
      riveFactory: Factory.rive,
    );
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RiveWidgetBuilder(
      fileLoader: _loader,
      builder: (context, state) => switch (state) {
        RiveLoading() => const SizedBox.expand(),
        RiveFailed() => const SizedBox.expand(),
        RiveLoaded() => RiveWidget(
          controller: state.controller,
          fit: Fit.cover,
        ),
      },
    );
  }
}
