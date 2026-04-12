import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';

import 'package:sage/core/config/env_config.dart';
import 'package:sage/core/config/live_trading_flags.dart';
import 'package:sage/core/repositories/bot_repository.dart';
import 'package:sage/core/services/auth_service.dart';
import 'package:sage/core/services/domain_resolver.dart';
import 'package:sage/core/theme/app_colors.dart';
import 'package:sage/core/theme/app_theme.dart';

import 'package:sage/core/models/bot.dart';
import 'package:sage/core/models/bot_event.dart';
import 'package:sage/core/services/notification_service.dart';
import 'package:sage/core/services/event_service.dart';

import 'package:sage/features/wallet/presentation/widgets/settings_info_row.dart';
import 'package:sage/features/wallet/presentation/widgets/support_link.dart';
import 'package:sage/features/wallet/presentation/widgets/stat_item.dart';
import 'package:sage/features/wallet/presentation/widgets/setting_tile.dart';
import 'package:sage/shared/widgets/mwa_button_tap_effect.dart';
import 'package:sage/shared/widgets/sage_bottom_sheet.dart';
import 'package:sage/shared/widgets/deposit_sheet.dart';
import 'package:sage/shared/widgets/withdraw_sheet.dart';
import 'package:sage/shared/widgets/smart_withdraw_sheet.dart';
import 'package:sage/core/repositories/wallet_repository.dart';

/// Profile — wallet identity, portfolio summary, settings entry.
///
/// Refactored to match the "Sage Capital Allocator" aesthetic.
/// Card-based identity, compact portfolio, and setting entry points.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settingsAnim;
  bool _settingsOpen = false;

  @override
  void initState() {
    super.initState();
    _settingsAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _settingsAnim.dispose();
    super.dispose();
  }

  void _toggleSettings() {
    setState(() => _settingsOpen = !_settingsOpen);
    if (_settingsOpen) {
      _settingsAnim.forward();
    } else {
      _settingsAnim.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final c = context.sage;
    final text = context.sageText;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    // Real data from providers
    final connectedWallet = ref.watch(connectedWalletAddressProvider);
    final botsAsync = ref.watch(botListProvider);
    final bots = botsAsync.value ?? [];

    // Listen to SSE events — auto-refresh portfolio stats on bot state changes
    ref.listen<AsyncValue<BotEvent>>(botEventStreamProvider, (_, next) {
      next.whenData((event) {
        if (event.isBotStarted ||
            event.isBotStopped ||
            event.isBotError ||
            event.isPositionOpened ||
            event.isPositionClosed) {
          ref.read(botListProvider.notifier).refresh();
        }
      });
    });
    final walletAddr = connectedWallet ?? '—';
    final shortAddr = walletAddr.length > 8
        ? '${walletAddr.substring(0, 4)}...${walletAddr.substring(walletAddr.length - 4)}'
        : walletAddr;
    final avatarSeed = walletAddr == '—' ? 'sage_guest' : walletAddr;

    // Resolve AllDomains ANS name (e.g. miester.abc)
    final domainAsync = walletAddr != '—'
        ? ref.watch(domainNameProvider(walletAddr))
        : const AsyncValue<String?>.data(null);
    final domainName = domainAsync.when(
      data: (d) => d,
      loading: () => null,
      error: (_, _) => null,
    );

    // Aggregated stats
    final totalBots = bots.length;
    final avgWinRate = bots.isEmpty
        ? 0.0
        : bots.fold<double>(0, (s, b) => s + b.winRate) / bots.length;
    final totalTrades = bots.fold<int>(
      0,
      (s, b) => s + (b.engineStats?.positionsOpened ?? b.totalTrades),
    );
    final totalDeployed = bots.fold<double>(
      0,
      (s, b) => s + b.currentBalanceSol,
    );
    final totalPnl = bots.fold<double>(
      0,
      (s, b) => s + (b.performanceSummary?.totalPnlSol ?? b.totalPnlSOL),
    );
    final runningBots = bots.where((b) => b.engineRunning).length;

    // Separate live vs simulation balances
    final liveBotsList = bots.where((b) => b.mode == BotMode.live).toList();
    final simBotsList = bots.where((b) => b.mode == BotMode.simulation).toList();
    final liveBalance = liveBotsList.fold<double>(
      0, (s, b) => s + b.currentBalanceSol);
    final simBalance = simBotsList.fold<double>(
      0, (s, b) => s + b.currentBalanceSol);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: c.background,
        body: Stack(
          children: [
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, bottomPad + 32.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              Padding(
                padding: EdgeInsets.only(top: topPad + 12.h, bottom: 24.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => context.pop(),
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
                    Text(
                      'IDENTITY',
                      style: text.labelMedium?.copyWith(
                        letterSpacing: 1.2,
                        color: c.textTertiary,
                      ),
                    ),
                    GestureDetector(
                      onTap: _toggleSettings,
                      child: Container(
                        padding: EdgeInsets.all(8.w),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.surface,
                          border: Border.all(color: c.borderSubtle, width: 1),
                        ),
                        child: AnimatedBuilder(
                          animation: _settingsAnim,
                          builder: (context, child) {
                            return Transform.rotate(
                              angle: _settingsAnim.value * math.pi / 4,
                              child: Icon(
                                _settingsOpen
                                    ? PhosphorIconsBold.x
                                    : PhosphorIconsBold.gear,
                                size: 20.sp,
                                color: c.textSecondary,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Identity Card ──
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(24.w),
                decoration: BoxDecoration(
                  // Use surface color with an overlay for slight differentiation
                  // that works in both light and dark modes
                  color: c.surfaceElevated,
                  borderRadius: BorderRadius.circular(32.r),
                  border: Border.all(color: c.borderSubtle, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: c.textPrimary.withValues(alpha: 0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Avatar — DiceBear with loading/error fallback
                    Container(
                      width: 100.w,
                      height: 100.w,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.background,
                        border: Border.all(
                          color: c.accent.withValues(alpha: 0.2),
                          width: 2,
                        ),
                      ),
                      child: ClipOval(
                        child: Image.network(
                          'https://api.dicebear.com/9.x/micah/png?seed=$avatarSeed',
                          width: 100.w,
                          height: 100.w,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Center(
                              child: Icon(
                                PhosphorIconsBold.user,
                                size: 36.sp,
                                color: c.textTertiary,
                              ),
                            );
                          },
                          errorBuilder: (context, error, stack) {
                            return Center(
                              child: Icon(
                                PhosphorIconsBold.user,
                                size: 36.sp,
                                color: c.textTertiary,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: 16.h),

                    // Name — domain or address
                    Text(
                      domainName ?? shortAddr,
                      style: text.headlineMedium?.copyWith(
                        fontSize: 24.sp,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    if (domainName != null) ...[
                      SizedBox(height: 2.h),
                      Text(
                        shortAddr,
                        style: text.labelSmall?.copyWith(
                          color: c.textTertiary,
                          fontSize: 11.sp,
                        ),
                      ),
                    ],
                    SizedBox(height: 4.h),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10.w,
                        vertical: 4.h,
                      ),
                      decoration: BoxDecoration(
                        color: c.background,
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: c.borderSubtle.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6.w,
                            height: 6.w,
                            decoration: BoxDecoration(
                              color: runningBots > 0
                                  ? c.profit
                                  : c.textTertiary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: 6.w),
                          Text(
                            runningBots > 0 ? '$runningBots Active' : 'Idle',
                            style: text.labelSmall?.copyWith(
                              color: runningBots > 0
                                  ? c.profit
                                  : c.textTertiary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 24.h),

                    // Stats Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        StatItem(
                          label: 'Bots',
                          value: '$totalBots',
                          icon: PhosphorIconsFill.lightning,
                          color: c.accent,
                        ),
                        Container(
                          width: 1,
                          height: 32.h,
                          color: c.borderSubtle,
                        ),
                        StatItem(
                          label: 'Win Rate',
                          value: '${avgWinRate.toStringAsFixed(0)}%',
                          icon: PhosphorIconsFill.trendUp,
                          color: c.profit,
                        ),
                        Container(
                          width: 1,
                          height: 32.h,
                          color: c.borderSubtle,
                        ),
                        StatItem(
                          label: 'Trades',
                          value: '$totalTrades',
                          icon: PhosphorIconsFill.cpu,
                          color: Colors.orangeAccent,
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),

              SizedBox(height: 32.h),

              // ── Compact Portfolio ──
              Text(
                'PORTFOLIO',
                style: text.labelMedium?.copyWith(
                  letterSpacing: 1.2,
                  color: c.textTertiary,
                ),
              ).animate().fadeIn(delay: 200.ms),
              SizedBox(height: 16.h),

              // Portfolio Summary Card with integrated actions
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24.r),
                  color: c.surface,
                  border: Border.all(color: c.borderSubtle, width: 1),
                ),
                child: Column(
                  children: [
                    // ── Top: Value + Breakdown ──
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Left: Total Net Worth
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                20.w,
                                20.w,
                                12.w,
                                20.w,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Total Value',
                                    style: text.labelSmall?.copyWith(
                                      color: c.textTertiary,
                                    ),
                                  ),
                                  SizedBox(height: 4.h),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '${totalDeployed.toStringAsFixed(1)} SOL',
                                      style: text.displaySmall?.copyWith(
                                        fontSize: 26.sp,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -1,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 8.h),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8.w,
                                      vertical: 4.h,
                                    ),
                                    decoration: BoxDecoration(
                                      color: (totalPnl >= 0 ? c.profit : c.loss).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8.r),
                                    ),
                                    child: Text(
                                      '${totalPnl >= 0 ? "+" : ""}${totalPnl.toStringAsFixed(2)} SOL P&L',
                                      style: text.labelSmall?.copyWith(
                                        color: totalPnl >= 0
                                            ? c.profit
                                            : c.loss,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(width: 1, color: c.borderSubtle),
                          // Right: Deployed + Idle stacked compactly
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 14.w,
                                vertical: 16.h,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Live Balance
                                  Row(
                                    children: [
                                      Icon(
                                        PhosphorIconsFill.pulse,
                                        size: 12.sp,
                                        color: c.accent,
                                      ),
                                      SizedBox(width: 5.w),
                                      Text(
                                        'Live',
                                        style: text.labelSmall?.copyWith(
                                          color: c.textTertiary,
                                          fontSize: 10.sp,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 2.h),
                                  Text(
                                    '${liveBalance.toStringAsFixed(2)} SOL',
                                    style: text.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 12.h),
                                  // Simulation Balance
                                  Row(
                                    children: [
                                      Icon(
                                        PhosphorIconsFill.flask,
                                        size: 12.sp,
                                        color: c.textTertiary,
                                      ),
                                      SizedBox(width: 5.w),
                                      Text(
                                        'Simulation',
                                        style: text.labelSmall?.copyWith(
                                          color: c.textTertiary,
                                          fontSize: 10.sp,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 2.h),
                                  Text(
                                    '${simBalance.toStringAsFixed(2)} SOL',
                                    style: text.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── Bottom: Deposit / Withdraw buttons ──
                    if (kLiveTradingEnabled)
                      Container(
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: c.borderSubtle, width: 1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: MWAButtonTapEffect(
                                onTap: () =>
                                    _showDepositSheet(context, ref, c, text),
                                child: Container(
                                  padding: EdgeInsets.symmetric(vertical: 14.h),
                                  decoration: BoxDecoration(
                                    color: c.accent.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.only(
                                      bottomLeft: Radius.circular(24.r),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        PhosphorIconsBold.arrowDown,
                                        size: 16.sp,
                                        color: c.accent,
                                      ),
                                      SizedBox(width: 6.w),
                                      Text(
                                        'Deposit',
                                        style: text.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: c.accent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 44.h,
                              color: c.borderSubtle,
                            ),
                            Expanded(
                              child: MWAButtonTapEffect(
                                onTap: () => _showWithdrawSheet(
                                  context,
                                  ref,
                                  0.0,
                                  c,
                                  text,
                                ),
                                child: Container(
                                  padding: EdgeInsets.symmetric(vertical: 14.h),
                                  decoration: BoxDecoration(
                                    color: c.accent.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.only(
                                      bottomRight: Radius.circular(24.r),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        PhosphorIconsBold.arrowUp,
                                        size: 16.sp,
                                        color: c.accent,
                                      ),
                                      SizedBox(width: 6.w),
                                      Text(
                                        'Withdraw',
                                        style: text.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: c.accent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(16.w),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: c.borderSubtle, width: 1),
                          ),
                        ),
                        child: Text(
                          kLiveTradingDisabledReason,
                          style: text.bodySmall?.copyWith(
                            color: c.textSecondary,
                            fontSize: 12.sp,
                            height: 1.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0),

              SizedBox(height: 24.h),

              // ── Live Bot Wallets ──
              Builder(builder: (_) {
                final liveBots =
                    bots.where((b) => b.mode == BotMode.live).toList();
                if (liveBots.isEmpty) {
                  return Text(
                    'No live bots yet. Create a live bot to see wallet details here.',
                    style: text.bodySmall?.copyWith(
                      color: c.textSecondary,
                      fontSize: 12.sp,
                      height: 1.5,
                    ),
                  ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.1, end: 0);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LIVE WALLETS',
                      style: text.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        color: c.textTertiary,
                        fontSize: 10.sp,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    ...liveBots.map((bot) {
                      final addr = bot.walletAddress ?? '';
                      final shortBotAddr = addr.length > 8
                          ? '${addr.substring(0, 4)}...${addr.substring(addr.length - 4)}'
                          : addr;
                      return Padding(
                        padding: EdgeInsets.only(bottom: 6.h),
                        child: Row(
                          children: [
                            Icon(
                              PhosphorIconsBold.wallet,
                              size: 18.sp,
                              color: c.textTertiary,
                            ),
                            SizedBox(width: 10.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bot.name,
                                    style: text.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (addr.isNotEmpty)
                                    GestureDetector(
                                      onTap: () {
                                        Clipboard.setData(
                                          ClipboardData(text: addr),
                                        );
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Wallet address copied',
                                            ),
                                          ),
                                        );
                                      },
                                      child: Row(
                                        children: [
                                          Text(
                                            shortBotAddr,
                                            style: text.bodySmall?.copyWith(
                                              color: c.textTertiary,
                                              fontSize: 11.sp,
                                            ),
                                          ),
                                          SizedBox(width: 4.w),
                                          Icon(
                                            PhosphorIconsBold.copy,
                                            size: 12.sp,
                                            color: c.textTertiary,
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              '${bot.currentBalanceSol.toStringAsFixed(4)} SOL',
                              style: text.bodySmall?.copyWith(
                                color: c.textSecondary,
                                fontSize: 11.sp,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.1, end: 0);
              }),
            ],
          ),
        ),
        // ── Settings Overlay ──
        _SettingsOverlay(
          animation: _settingsAnim,
          onClose: _toggleSettings,
        ),
      ],
    ),
  ),
);
  }
}

// ─────────────────────────────────────────────────────────
// Settings Overlay
// ─────────────────────────────────────────────────────────

class _SettingsOverlay extends ConsumerWidget {
  final Animation<double> animation;
  final VoidCallback onClose;

  const _SettingsOverlay({required this.animation, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sage;
    final text = context.sageText;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        if (animation.value == 0) return const SizedBox.shrink();

        return Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: Container(
              color: Colors.black.withValues(alpha: 0.3 * animation.value),
              child: Align(
                alignment: Alignment.centerRight,
                child: FractionalTranslation(
                  translation: Offset(1 - animation.value, 0),
                  child: GestureDetector(
                    onTap: () {}, // absorb taps on sheet
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      padding: EdgeInsets.fromLTRB(
                        20.w,
                        topPad + 12.h,
                        20.w,
                        bottomPad + 32.h,
                      ),
                      decoration: BoxDecoration(
                        color: c.background,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header with close button
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'SETTINGS',
                                style: text.labelMedium?.copyWith(
                                  letterSpacing: 1.2,
                                  color: c.textTertiary,
                                ),
                              ),
                              GestureDetector(
                                onTap: onClose,
                                child: Container(
                                  padding: EdgeInsets.all(8.w),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: c.surface,
                                    border: Border.all(
                                      color: c.borderSubtle,
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    PhosphorIconsBold.x,
                                    size: 20.sp,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 24.h),
                          SettingTile(
                            icon: PhosphorIconsBold.shieldCheck,
                            title: 'Security & Privacy',
                            subtitle: 'Biometrics, auto-lock',
                            onTap: () =>
                                _showSecuritySheet(context, c, text),
                          ),
                          SettingTile(
                            icon: PhosphorIconsBold.bell,
                            title: 'Notifications',
                            subtitle: 'Execution alerts, price moves',
                            onTap: () =>
                                _showNotificationsSheet(context, c, text),
                          ),
                          SettingTile(
                            icon: PhosphorIconsBold.globe,
                            title: 'Network',
                            subtitle: 'RPC endpoints, priority fees',
                            onTap: () =>
                                _showNetworkSheet(context, c, text),
                          ),
                          SettingTile(
                            icon: PhosphorIconsBold.question,
                            title: 'Support',
                            subtitle: 'Docs, community, help',
                            onTap: () =>
                                _showSupportSheet(context, c, text),
                            isLast: true,
                          ),
                          const Spacer(),
                          // Disconnect Wallet
                          Center(
                            child: TextButton(
                              onPressed: () async {
                                onClose();
                                await ref
                                    .read(authStateProvider.notifier)
                                    .signOut();
                                if (context.mounted) {
                                  context.go('/connect-wallet');
                                }
                              },
                              child: Text(
                                'Disconnect Wallet',
                                style: text.titleSmall?.copyWith(
                                  color: c.loss,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────
// Deposit Sheet Launcher
// ─────────────────────────────────────────────────────────

void _showDepositSheet(
  BuildContext context,
  WidgetRef ref,
  SageColors c,
  TextTheme text,
) {
  final bots = ref.read(botListProvider).value ?? [];
  final liveBots = bots.where((b) => b.mode == BotMode.live).toList();
  if (liveBots.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Create a live bot first')),
    );
    return;
  }
  if (liveBots.length == 1) {
    _depositForBot(context, ref, liveBots.first);
  } else {
    _showBotPicker(context, ref, liveBots, deposit: true);
  }
}

void _depositForBot(BuildContext context, WidgetRef ref, Bot bot) async {
  // Include rent+fees overhead per position (~0.07 SOL) in recommendation
  final recommended = (bot.positionSizeSOL + 0.07) * bot.maxConcurrentPositions;
  final success = await SageBottomSheet.show<bool>(
    context: context,
    title: 'Fund Wallet',
    builder: (c, text) => DepositSheet(
      botId: bot.botId,
      recommendedSol: recommended,
      minSol: bot.positionSizeSOL + 0.07,
      c: c,
      text: text,
    ),
  );
  if (success == true) {
    ref.invalidate(walletBalanceProvider(bot.botId));
    ref.invalidate(botDetailProvider(bot.botId));
  }
}

// ─────────────────────────────────────────────────────────
// Withdraw Sheet Launcher
// ─────────────────────────────────────────────────────────

void _showWithdrawSheet(
  BuildContext context,
  WidgetRef ref,
  double balance,
  SageColors c,
  TextTheme text,
) {
  final bots = ref.read(botListProvider).value ?? [];
  final liveBots = bots.where((b) => b.mode == BotMode.live).toList();
  if (liveBots.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Create a live bot first')),
    );
    return;
  }
  if (liveBots.length == 1) {
    _withdrawForBot(context, ref, liveBots.first);
  } else {
    // Smart withdraw — multi-wallet picker
    _showSmartWithdraw(context, ref);
  }
}

void _showSmartWithdraw(BuildContext context, WidgetRef ref) async {
  final success = await SageBottomSheet.show<bool>(
    context: context,
    title: 'Smart Withdraw',
    builder: (c, text) => SmartWithdrawSheet(c: c, text: text),
  );
  if (success == true) {
    ref.invalidate(botListProvider);
  }
}

void _withdrawForBot(BuildContext context, WidgetRef ref, Bot bot) async {
  final walletRepo = ref.read(walletRepositoryProvider);
  double bal;
  try {
    final wb = await walletRepo.getBalance(bot.botId);
    bal = wb.balanceSOL;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load wallet balance')),
      );
    }
    return;
  }
  if (bal <= 0.003) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No funds available to withdraw')),
      );
    }
    return;
  }
  if (!context.mounted) return;
  final success = await SageBottomSheet.show<bool>(
    context: context,
    title: 'Withdraw',
    builder: (c, text) => WithdrawSheet(
      botId: bot.botId,
      availableBalanceSol: bal,
      c: c,
      text: text,
    ),
  );
  if (success == true) {
    ref.invalidate(walletBalanceProvider(bot.botId));
    ref.invalidate(botDetailProvider(bot.botId));
  }
}

void _showBotPicker(
  BuildContext context,
  WidgetRef ref,
  List<Bot> liveBots, {
  required bool deposit,
}) {
  final c = context.sage;
  final text = context.sageText;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 32.h),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        border: Border(top: BorderSide(color: c.borderSubtle)),
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
                color: c.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            deposit ? 'Select Bot to Fund' : 'Select Bot to Withdraw',
            style: text.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          SizedBox(height: 16.h),
          ...liveBots.map((bot) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  PhosphorIconsBold.wallet,
                  color: c.accent,
                  size: 20.sp,
                ),
                title: Text(bot.name, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${bot.currentBalanceSol.toStringAsFixed(4)} SOL',
                  style: text.bodySmall?.copyWith(color: c.textSecondary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  if (deposit) {
                    _depositForBot(context, ref, bot);
                  } else {
                    _withdrawForBot(context, ref, bot);
                  }
                },
              )),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────
// Settings Sheet Helpers
// ─────────────────────────────────────────────────────────

void _showSecuritySheet(BuildContext context, SageColors c, TextTheme text) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 32.h),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        border: Border(top: BorderSide(color: c.borderSubtle)),
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
                color: c.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Security & Privacy',
            style: text.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          SizedBox(height: 20.h),
          SettingsInfoRow(
            label: 'Wallet Auth',
            value: 'SIWS (Sign-In With Solana)',
            c: c,
            text: text,
          ),
          Divider(height: 1, color: c.borderSubtle),
          SettingsInfoRow(
            label: 'Session',
            value: 'JWT (HS256), 7-day expiry',
            c: c,
            text: text,
          ),
          Divider(height: 1, color: c.borderSubtle),
          SettingsInfoRow(
            label: 'Key Storage',
            value: 'Secure Enclave / Keychain',
            c: c,
            text: text,
          ),
          Divider(height: 1, color: c.borderSubtle),
          SettingsInfoRow(
            label: 'Network',
            value: 'TLS 1.3 encrypted',
            c: c,
            text: text,
          ),
        ],
      ),
    ),
  );
}

void _showNotificationsSheet(
  BuildContext context,
  SageColors c,
  TextTheme text,
) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => const _NotificationsSheetBody(),
  );
}

/// Notification settings sheet — backed by real [NotificationService] prefs.
///
/// Uses [Consumer] to read / write per-event-type toggles stored in
/// [SharedPreferences]. Changes take effect immediately (no save button).
class _NotificationsSheetBody extends ConsumerStatefulWidget {
  const _NotificationsSheetBody();

  @override
  ConsumerState<_NotificationsSheetBody> createState() =>
      _NotificationsSheetBodyState();
}

class _NotificationsSheetBodyState
    extends ConsumerState<_NotificationsSheetBody> {
  /// Local copy of toggle states — seeded from SharedPreferences,
  /// mutated on tap, and persisted asynchronously.
  Map<String, bool> _toggles = {};
  bool _permissionGranted = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final service = ref.read(notificationServiceProvider);
    final prefs = await service.loadAllPreferences();
    final granted = await service.arePermissionsGranted();
    if (!mounted) return;
    setState(() {
      _toggles = prefs;
      _permissionGranted = granted;
      _loaded = true;
    });
  }

  Future<void> _requestPermission() async {
    final service = ref.read(notificationServiceProvider);
    final granted = await service.requestPermission();
    if (!mounted) return;
    setState(() => _permissionGranted = granted);
  }

  Future<void> _toggle(String key, bool value) async {
    setState(() => _toggles[key] = value);
    final service = ref.read(notificationServiceProvider);
    await service.setEnabled(key, value);
    // Invalidate the cached provider so other consumers see the change
    ref.invalidate(notificationPrefsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sage;
    final text = context.sageText;
    final eventService = ref.watch(eventServiceProvider);

    return Container(
      padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 32.h),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        border: Border(top: BorderSide(color: c.borderSubtle)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: c.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
          ),
          SizedBox(height: 16.h),

          // Title
          Text(
            'Notifications',
            style: text.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          SizedBox(height: 8.h),

          // SSE connection status
          Row(
            children: [
              Container(
                width: 8.w,
                height: 8.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: eventService.isConnected ? c.profit : c.loss,
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                eventService.isConnected
                    ? 'Real-time stream connected'
                    : 'Stream disconnected',
                style: text.bodySmall?.copyWith(
                  color: eventService.isConnected ? c.profit : c.loss,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),

          // Permission banner
          if (_loaded && !_permissionGranted) ...[
            GestureDetector(
              onTap: _requestPermission,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: c.accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      PhosphorIconsBold.bellRinging,
                      size: 20.sp,
                      color: c.accent,
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Text(
                        'Tap to enable notification permissions',
                        style: text.bodySmall?.copyWith(
                          color: c.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      PhosphorIconsBold.caretRight,
                      size: 14.sp,
                      color: c.accent,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16.h),
          ],

          // Toggle list
          if (!_loaded)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24.h),
              child: Center(
                child: SizedBox(
                  width: 24.w,
                  height: 24.w,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.textTertiary,
                  ),
                ),
              ),
            )
          else
            ...NotificationPrefKeys.allKeys
                .expand(
                  (key) => [
                    _NotificationToggleRow(
                      label: NotificationPrefKeys.label(key),
                      description: NotificationPrefKeys.description(key),
                      enabled: _toggles[key] ?? true,
                      onChanged: (val) => _toggle(key, val),
                      c: c,
                      text: text,
                    ),
                    Divider(height: 1, color: c.borderSubtle),
                  ],
                )
                .toList()
              ..removeLast(), // Remove trailing divider

          SizedBox(height: 16.h),

          // Push notifications note
          Row(
            children: [
              Icon(
                PhosphorIconsBold.cloudArrowDown,
                size: 16.sp,
                color: c.textTertiary,
              ),
              SizedBox(width: 8.w),
              Text(
                'Push notifications — coming soon',
                style: text.bodySmall?.copyWith(
                  color: c.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single notification toggle row with label, description, and switch.
class _NotificationToggleRow extends StatelessWidget {
  final String label;
  final String description;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final SageColors c;
  final TextTheme text;

  const _NotificationToggleRow({
    required this.label,
    required this.description,
    required this.enabled,
    required this.onChanged,
    required this.c,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: text.bodyMedium?.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  description,
                  style: text.bodySmall?.copyWith(
                    color: c.textTertiary,
                    fontSize: 11.sp,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          SizedBox(
            height: 28.h,
            child: Switch.adaptive(
              value: enabled,
              onChanged: onChanged,
              activeColor: c.accent,
              activeTrackColor: c.accent.withValues(alpha: 0.3),
              inactiveThumbColor: c.textTertiary,
              inactiveTrackColor: c.surface,
            ),
          ),
        ],
      ),
    );
  }
}

void _showNetworkSheet(BuildContext context, SageColors c, TextTheme text) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 32.h),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        border: Border(top: BorderSide(color: c.borderSubtle)),
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
                color: c.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Network Configuration',
            style: text.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          SizedBox(height: 20.h),
          SettingsInfoRow(
            label: 'Environment',
            value: EnvConfig.environmentLabel,
            c: c,
            text: text,
          ),
          Divider(height: 1, color: c.borderSubtle),
          SettingsInfoRow(
            label: 'Network',
            value: EnvConfig.solanaNetwork,
            c: c,
            text: text,
          ),
          Divider(height: 1, color: c.borderSubtle),
          SettingsInfoRow(
            label: 'Backend',
            value: Uri.parse(EnvConfig.apiBaseUrl).host,
            c: c,
            text: text,
          ),
          Divider(height: 1, color: c.borderSubtle),
          SettingsInfoRow(
            label: 'ML Server',
            value: Uri.parse(EnvConfig.mlBaseUrl).host,
            c: c,
            text: text,
          ),
          Divider(height: 1, color: c.borderSubtle),
          SettingsInfoRow(
            label: 'Priority Fee',
            value: 'Dynamic (auto-scale)',
            c: c,
            text: text,
          ),
          Divider(height: 1, color: c.borderSubtle),
          SettingsInfoRow(
            label: 'Confirmation',
            value: 'confirmed commitment',
            c: c,
            text: text,
          ),
        ],
      ),
    ),
  );
}

void _showSupportSheet(BuildContext context, SageColors c, TextTheme text) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 32.h),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        border: Border(top: BorderSide(color: c.borderSubtle)),
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
                color: c.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Support & Docs',
            style: text.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          SizedBox(height: 20.h),
          SupportLink(
            icon: PhosphorIconsBold.bookOpen,
            label: 'Meteora DLMM Docs',
            url: 'https://docs.meteora.ag/dlmm/about-dlmm',
            c: c,
            text: text,
          ),
          SupportLink(
            icon: PhosphorIconsBold.githubLogo,
            label: 'Source Code',
            url: 'https://github.com/niccolosottile/meteora-sage',
            c: c,
            text: text,
          ),
          SupportLink(
            icon: PhosphorIconsBold.chatCircle,
            label: 'Meteora Discord',
            url: 'https://discord.gg/meteora',
            c: c,
            text: text,
          ),
          SupportLink(
            icon: PhosphorIconsBold.twitterLogo,
            label: 'Meteora on X',
            url: 'https://x.com/MeteoraAG',
            c: c,
            text: text,
          ),
        ],
      ),
    ),
  );
}
