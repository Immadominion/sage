import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:sage/core/models/bot.dart';
import 'package:sage/core/models/bot_event.dart';
import 'package:sage/core/repositories/bot_repository.dart';
import 'package:sage/core/repositories/position_repository.dart';
import 'package:sage/core/services/event_service.dart';
import 'package:sage/core/theme/app_colors.dart';
import 'package:sage/core/theme/app_theme.dart';
import 'package:sage/shared/widgets/sage_components.dart';

import 'package:sage/features/home/presentation/widgets/empty_state.dart';
import 'package:sage/features/home/presentation/widgets/bot_row.dart';
import 'package:sage/features/home/presentation/widgets/positions_section.dart';

/// Status Mode — Deployed capital across Meteora DLMM pools.
///
/// Dark hero: total SOL deployed + P&L.
/// Light panel: active bots, positions, engine stats.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// Format error messages for display (truncate long DioExceptions).
  static String _friendlyError(Object error) {
    final msg = error.toString();

    if (msg.contains('DioException') || msg.contains('Connection refused')) {
      return 'Backend unavailable. Check your connection.';
    }
    if (msg.contains('SocketException')) {
      return 'Network error. Check your internet.';
    }
    if (msg.contains('401') || msg.contains('Unauthorized')) {
      return 'Authentication failed. Please sign in again.';
    }

    // Truncate long errors
    if (msg.length > 60) {
      return '${msg.substring(0, 57)}…';
    }
    return msg;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sage;
    final text = context.sageText;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    final botsAsync = ref.watch(botListProvider);

    // Listen to SSE events — auto-refresh on position and engine state changes
    ref.listen<AsyncValue<BotEvent>>(botEventStreamProvider, (_, next) {
      next.whenData((event) {
        if (event.isPositionOpened || event.isPositionClosed) {
          ref.read(botListProvider.notifier).refresh();
          ref.invalidate(activePositionsProvider);
        } else if (event.isBotStarted ||
            event.isBotStopped ||
            event.isBotError) {
          ref.read(botListProvider.notifier).refresh();
        }
      });
    });

    return Scaffold(
      backgroundColor: c.background,
      body: botsAsync.when(
        skipLoadingOnReload: true,
        loading: () => _buildShell(
          context,
          ref,
          c,
          text,
          topPad,
          bottomPad,
          isLoading: true,
        ),
        error: (err, _) => _buildShell(
          context,
          ref,
          c,
          text,
          topPad,
          bottomPad,
          errorMessage: _friendlyError(err),
        ),
        data: (bots) {
          // Sort: running bots first, then by most recent activity
          final sorted = List<Bot>.from(bots)
            ..sort((a, b) {
              // Running beats non-running
              if (a.engineRunning && !b.engineRunning) return -1;
              if (!a.engineRunning && b.engineRunning) return 1;
              // Among same state, most recently active first
              final aTime = a.lastActivityAt ?? DateTime(2000);
              final bTime = b.lastActivityAt ?? DateTime(2000);
              return bTime.compareTo(aTime);
            });
          return _buildBody(context, ref, c, text, topPad, bottomPad, sorted);
        },
      ),
    );
  }

  /// Main body once bot data is loaded.
  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    SageColors c,
    TextTheme text,
    double topPad,
    double bottomPad,
    List<Bot> bots,
  ) {
    // Aggregate data across all bots.
    final runningBots = bots.where((b) => b.engineRunning).toList();
    final allPositions = bots.expand((b) => b.livePositions).toList();
    // Only count live bot balances — simulation bots use virtual money
    // that should not inflate the real portfolio figure.
    final liveBots = bots.where((b) => b.mode == BotMode.live).toList();
    final totalDeployed = liveBots.fold<double>(
      0,
      (sum, b) => sum + b.currentBalanceSol,
    );
    final totalPnl = bots.fold<double>(
      0,
      (sum, b) => sum + (b.performanceSummary?.totalPnlSol ?? b.totalPnlSOL),
    );
    final avgWinRate = runningBots.isEmpty
        ? 0.0
        : runningBots.fold<double>(
                0,
                (s, b) => s + (b.engineStats?.winRate ?? 0),
              ) /
              runningBots.length;

    // Hero: sum of all bot balances (simulation + live)
    final heroBalance = totalDeployed;

    final wholePart = heroBalance.toStringAsFixed(1).split('.')[0];
    final decimalPart = '.${heroBalance.toStringAsFixed(1).split('.')[1]} SOL';
    final pnlStr = totalPnl >= 0
        ? '+${totalPnl.toStringAsFixed(2)} SOL'
        : '${totalPnl.toStringAsFixed(2)} SOL';

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(botListProvider.notifier).refresh();
        ref.invalidate(activePositionsProvider);
      },
      color: c.accent,
      backgroundColor: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ════════════════════════════════════════
          // DARK HERO — Total Deployed
          // ════════════════════════════════════════
          Expanded(
            flex: 3,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 28.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: topPad + 56.h),

                  const SageLabel(
                    'HOME',
                  ).animate().fadeIn(duration: 500.ms, delay: 200.ms),

                  SizedBox(height: 10.h),

                  // Total SOL in LP positions (real data)
                  SageMetric(wholePart, decimal: decimalPart)
                      .animate()
                      .fadeIn(duration: 600.ms, delay: 350.ms)
                      .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),

                  SizedBox(height: 10.h),

                  // P&L
                  Row(
                    children: [
                      Text(
                        '$pnlStr earned',
                        style: text.titleMedium?.copyWith(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w700,
                          color: totalPnl >= 0 ? c.profit : c.loss,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      SizedBox(width: 6.w),
                      Text(
                        '${runningBots.length} active',
                        style: text.titleMedium?.copyWith(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: c.textTertiary,
                        ),
                      ),
                    ],
                  ).animate().fadeIn(duration: 400.ms, delay: 600.ms),
                ],
              ),
            ),
          ),

          // ════════════════════════════════════════
          // LIGHT PANEL — Bots & Positions
          // ════════════════════════════════════════
          Expanded(
            flex: 6,
            child:
                Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: c.panelBackground,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24.r),
                        ),
                      ),
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          28.w,
                          24.h,
                          28.w,
                          bottomPad + 80.h,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Aggregate stats
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: EdgeInsets.all(14.w),
                                    decoration: BoxDecoration(
                                      color: c.panelBorder.withValues(
                                        alpha: 0.4,
                                      ),
                                      borderRadius: BorderRadius.circular(12.r),
                                    ),
                                    child: SageStatBox(
                                      label: 'Positions',
                                      value: '${allPositions.length}',
                                    ),
                                  ),
                                ),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: Container(
                                    padding: EdgeInsets.all(14.w),
                                    decoration: BoxDecoration(
                                      color: c.panelBorder.withValues(
                                        alpha: 0.4,
                                      ),
                                      borderRadius: BorderRadius.circular(12.r),
                                    ),
                                    child: SageStatBox(
                                      label: 'Win Rate',
                                      value:
                                          '${avgWinRate.toStringAsFixed(0)}%',
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            SizedBox(height: 24.h),

                            Text(
                              'YOUR BOTS',
                              style: text.titleSmall?.copyWith(
                                color: c.panelTextSecondary,
                              ),
                            ),

                            SizedBox(height: 8.h),

                            // Bot rows — show up to 3 most recent, tappable
                            if (bots.isEmpty)
                              EmptyState(c: c, text: text)
                            else ...[
                              ...bots.take(2).toList().asMap().entries.map((
                                entry,
                              ) {
                                final i = entry.key;
                                final bot = entry.value;
                                final statusColor = bot.engineRunning
                                    ? c.profit
                                    : (bot.status == BotStatus.error
                                          ? c.loss
                                          : c.panelTextSecondary);
                                final neverStarted =
                                    bot.status == BotStatus.stopped &&
                                    bot.totalTrades == 0 &&
                                    bot.lastActivityAt == null;
                                final statusText = bot.engineRunning
                                    ? 'Running · ${bot.engineStats?.totalScans ?? 0} scans'
                                    : neverStarted
                                    ? 'Not Started'
                                    : bot.status == BotStatus.error
                                    ? 'Error'
                                    : 'Stopped';

                                return Column(
                                  children: [
                                    if (i > 0)
                                      Divider(height: 1, color: c.panelBorder),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => context.push(
                                        '/strategy/${bot.botId}',
                                      ),
                                      child: BotRow(
                                        name: bot.name,
                                        balance:
                                            '${bot.currentBalanceSol.toStringAsFixed(1)} SOL',
                                        status: statusText,
                                        statusColor: statusColor,
                                      ),
                                    ),
                                  ],
                                );
                              }),

                              // "See All" link → navigates to Automate tab
                              if (bots.length > 2) ...[
                                SizedBox(height: 4.h),
                                GestureDetector(
                                  onTap: () => context.go('/control'),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        'See All ${bots.length} Bots',
                                        style: text.labelMedium?.copyWith(
                                          color: c.accent,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(width: 4.w),
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        size: 12.sp,
                                        color: c.accent,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],

                            SizedBox(height: 20.h),

                            // ── Active Positions ──
                            PositionsSection(),

                            // ── View History link ──
                            GestureDetector(
                              onTap: () => context.push('/history'),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    'Trade History',
                                    style: text.labelMedium?.copyWith(
                                      color: c.accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(width: 4.w),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 12.sp,
                                    color: c.accent,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 400.ms)
                    .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
          ),
        ],
      ),
    );
  }

  /// Skeleton shell for loading / error states.
  Widget _buildShell(
    BuildContext context,
    WidgetRef ref,
    SageColors c,
    TextTheme text,
    double topPad,
    double bottomPad, {
    bool isLoading = false,
    String? errorMessage,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 28.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: topPad + 56.h),
                const SageLabel('Deployed'),
                SizedBox(height: 10.h),
                if (isLoading)
                  SizedBox(
                    width: 24.w,
                    height: 24.w,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.textSecondary,
                    ),
                  )
                else ...[
                  Text(
                    errorMessage ?? '—',
                    style: text.bodyMedium?.copyWith(color: c.loss),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 8.h),
                  TextButton.icon(
                    onPressed: () => ref
                        .read(botListProvider.notifier)
                        .refresh(showLoading: true),
                    icon: Icon(Icons.refresh, size: 16.sp, color: c.accent),
                    label: Text(
                      'Retry',
                      style: TextStyle(color: c.accent, fontSize: 13.sp),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12.w,
                        vertical: 4.h,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          flex: 6,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: c.panelBackground,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
            ),
          ),
        ),
      ],
    );
  }
}
