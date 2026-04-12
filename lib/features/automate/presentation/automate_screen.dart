import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:sage/core/models/bot.dart';
import 'package:sage/core/models/bot_event.dart';
import 'package:sage/core/repositories/bot_repository.dart';
import 'package:sage/core/services/event_service.dart';
import 'package:sage/core/theme/app_colors.dart';
import 'package:sage/core/theme/app_theme.dart';
import 'package:sage/shared/widgets/sage_components.dart';

import 'package:sage/features/automate/models/strategy_state.dart';
import 'package:sage/features/automate/presentation/widgets/strategy_card.dart';
import 'package:sage/features/automate/presentation/widgets/stat_chip.dart';
import 'package:sage/features/automate/presentation/widgets/pulsing_dot.dart';

/// Mode 2 — Automate
///
/// Layer 1: Dominant metric (net PnL) + quick stats strip — pinned at top.
/// Layer 2: Bots as individual surface-cards — scrollable with pull-to-refresh.
///
/// Deliberately different from Home — no white panel lift.
/// Everything lives on the same dark plane. Bots are objects, not rows.
class AutomateScreen extends ConsumerWidget {
  const AutomateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sage;
    final text = context.sageText;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    final botsAsync = ref.watch(botListProvider);

    // Listen to SSE events — auto-refresh bot list AND invalidate detail cache
    ref.listen<AsyncValue<BotEvent>>(botEventStreamProvider, (_, next) {
      next.whenData((event) {
        if (event.isPositionOpened ||
            event.isPositionClosed ||
            event.isBotStarted ||
            event.isBotStopped ||
            event.isBotError ||
            event.isScanCompleted) {
          ref.read(botListProvider.notifier).refresh();
          ref.invalidate(botDetailProvider(event.botId));
        }
      });
    });

    return Scaffold(
      backgroundColor: c.background,
      body: botsAsync.when(
        skipLoadingOnReload: true,
        loading: () =>
            Center(child: CircularProgressIndicator(color: c.accent)),
        error: (err, _) => _buildErrorState(ref, c, text, err),
        data: (bots) {
          // Sort: running bots first, then by most recent activity
          final sorted = List<Bot>.from(bots)
            ..sort((a, b) {
              if (a.engineRunning && !b.engineRunning) return -1;
              if (!a.engineRunning && b.engineRunning) return 1;
              final aTime = a.lastActivityAt ?? DateTime(2000);
              final bTime = b.lastActivityAt ?? DateTime(2000);
              return bTime.compareTo(aTime);
            });
          return _buildBody(context, ref, c, text, topPad, bottomPad, sorted);
        },
      ),
    );
  }

  Widget _buildErrorState(
    WidgetRef ref,
    SageColors c,
    TextTheme text,
    Object err,
  ) {
    final msg = err.toString();
    String friendly;
    if (msg.contains('DioException') ||
        msg.contains('Connection refused') ||
        msg.contains('connection timeout')) {
      friendly = 'Backend unavailable.\nCheck your connection.';
    } else if (msg.contains('SocketException')) {
      friendly = 'Network error.\nCheck your internet.';
    } else if (msg.contains('401') || msg.contains('Unauthorized')) {
      friendly = 'Authentication failed.\nPlease sign in again.';
    } else {
      friendly = 'Failed to load bots.';
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, color: c.textSecondary, size: 40.sp),
          SizedBox(height: 12.h),
          Text(
            friendly,
            style: text.bodyMedium?.copyWith(color: c.textSecondary),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16.h),
          TextButton.icon(
            onPressed: () => ref.read(botListProvider.notifier).refresh(),
            icon: Icon(Icons.refresh, size: 18.sp, color: c.accent),
            label: Text('Retry', style: TextStyle(color: c.accent)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    SageColors c,
    TextTheme text,
    double topPad,
    double bottomPad,
    List<Bot> bots,
  ) {
    // Aggregated stats
    final runningBots = bots.where((b) => b.engineRunning).toList();
    final totalPnl = bots.fold<double>(
      0,
      (s, b) => s + (b.performanceSummary?.totalPnlSol ?? b.totalPnlSOL),
    );
    final totalTrades = bots.fold<int>(
      0,
      (s, b) => s + (b.engineStats?.positionsOpened ?? b.totalTrades),
    );
    final avgWinRate = bots.isEmpty
        ? 0.0
        : bots.fold<double>(0, (s, b) => s + b.winRate) / bots.length;

    final pnlWhole = totalPnl.abs().toStringAsFixed(2).split('.')[0];
    final pnlDecimal =
        '.${totalPnl.abs().toStringAsFixed(2).split('.')[1]} SOL';
    final pnlPrefix = totalPnl >= 0 ? '+' : '-';

    // RefreshIndicator wraps the full Column so the spinner always
    // appears at the very top of the screen, not below the pinned header.
    return RefreshIndicator(
      onRefresh: () => ref.read(botListProvider.notifier).refresh(),
      color: c.accent,
      backgroundColor: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ════════════════════════════════════════
          // PINNED HEADER — never scrolls
          // ════════════════════════════════════════
          Padding(
            padding: EdgeInsets.fromLTRB(28.w, topPad + 48.h, 28.w, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Label ──
                const SageLabel('Automate'),

                SizedBox(height: 20.h),

                // ── Dominant metric — net PnL ──
                SageMetric('$pnlPrefix$pnlWhole', decimal: pnlDecimal),

                SizedBox(height: 12.h),

                // ── Intelligence line ──
                Row(
                  children: [
                    if (runningBots.isNotEmpty) PulsingDot(color: c.profit),
                    if (runningBots.isNotEmpty) SizedBox(width: 8.w),
                    Text(
                      '${runningBots.length} running · $totalTrades trades total',
                      style: text.bodySmall?.copyWith(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 28.h),

                // ── Quick stats strip ──
                Row(
                  children: [
                    StatChip(
                      label: 'Trades',
                      value: '$totalTrades',
                      c: c,
                      text: text,
                    ),
                    SizedBox(width: 10.w),
                    StatChip(
                      label: 'Win Rate',
                      value: '${avgWinRate.toStringAsFixed(0)}%',
                      c: c,
                      text: text,
                    ),
                    SizedBox(width: 10.w),
                    StatChip(
                      label: 'Bots',
                      value: '${bots.length}',
                      c: c,
                      text: text,
                    ),
                  ],
                ),

                SizedBox(height: 28.h),

                // ── Fleet leaderboard CTA — banner style ──
                GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    context.push('/fleet');
                  },
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(20.r),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20.r),
                      child: Stack(
                        children: [
                          Positioned(
                            top: 20,
                            right: -15,
                            child: Container(
                              width: 120.w,
                              height: 120.w,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.07),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 16,
                            right: 16,
                            child: Image.asset(
                              'assets/images/rocket.png',
                              width: 150.w,
                              height: 150.w,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(20.w),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Fleet Leaderboard',
                                  style: text.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    height: 1.15,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                SizedBox(height: 6.h),
                                Text(
                                  'See how your bots rank against\nthe platform.',
                                  style: text.bodySmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 36.h),

                // ── Section label ──
                Text(
                  'BOTS',
                  style: text.titleSmall?.copyWith(
                    color: c.textTertiary,
                    letterSpacing: 1.5,
                  ),
                ),

                if (bots.isNotEmpty) ...[
                  SizedBox(height: 4.h),
                  Text(
                    'Long-press to rename',
                    style: text.bodySmall?.copyWith(
                      color: c.textTertiary.withValues(alpha: 0.5),
                      fontSize: 11.sp,
                    ),
                  ),
                ],

                SizedBox(height: 16.h),
              ],
            ),
          ),

          // ════════════════════════════════════════
          // SCROLLABLE BOT CARDS — only cards scroll
          // ════════════════════════════════════════
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(28.w, 0, 28.w, bottomPad + 80.h),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (bots.isEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 48.h),
                    child: Center(
                      child: Text(
                        'No bots configured yet.\nCreate one to start automating.',
                        style: text.bodySmall?.copyWith(color: c.textTertiary),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  ...bots.asMap().entries.map((entry) {
                    final i = entry.key;
                    final bot = entry.value;

                    final StrategyState state;
                    if (bot.engineRunning) {
                      state = StrategyState.running;
                    } else if (bot.status == BotStatus.error) {
                      state = StrategyState.paused;
                    } else if (bot.status == BotStatus.stopped &&
                        bot.totalTrades == 0 &&
                        bot.lastActivityAt == null) {
                      state = StrategyState.notStarted;
                    } else {
                      // Bot is stopped (with prior trade history)
                      state = StrategyState.paused;
                    }

                    final pnl =
                        bot.performanceSummary?.totalPnlSol ?? bot.totalPnlSOL;
                    final pnlStr = pnl > 0
                        ? '+${pnl.toStringAsFixed(2)} SOL'
                        : pnl < 0
                        ? '${pnl.toStringAsFixed(2)} SOL'
                        : '0.00 SOL';

                    final waitingForMlEntry =
                        bot.engineRunning &&
                        bot.strategyMode == StrategyMode.sageAi &&
                        (bot.engineStats?.positionsOpened ?? 0) == 0 &&
                        (bot.engineStats?.totalScans ?? 0) > 0;

                    final lastActivity = bot.lastActivityAt != null
                        ? _relativeTime(bot.lastActivityAt!)
                        : 'No activity';

                    return Column(
                      children: [
                        if (i > 0)
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            color: c.borderSubtle,
                          ),
                        GestureDetector(
                          onLongPress: () =>
                              _showRenameDialog(context, ref, bot),
                          child: StrategyCard(
                            botId: bot.botId,
                            name: bot.name,
                            trigger:
                                'Score ≥ ${bot.entryScoreThreshold.toStringAsFixed(0)}% · ${bot.positionSizeSOL.toStringAsFixed(1)} SOL',
                            lastAction: waitingForMlEntry
                                ? '$lastActivity · awaiting ML entry'
                                : '$lastActivity · ${bot.engineStats?.totalScans ?? 0} scans',
                            pnl: pnlStr,
                            state: state,
                          ),
                        ),
                      ],
                    );
                  }),

                SizedBox(height: 36.h),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, Bot bot) {
    final c = context.sage;
    final controller = TextEditingController(text: bot.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          'Rename Strategy',
          style: TextStyle(color: c.textPrimary, fontSize: 16.sp),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 64,
          style: TextStyle(color: c.textPrimary),
          cursorColor: c.accent,
          decoration: InputDecoration(
            hintText: 'Strategy name',
            hintStyle: TextStyle(color: c.textTertiary),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: c.borderSubtle),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: c.accent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await ref
                  .read(botListProvider.notifier)
                  .renameBot(bot.botId, name);
            },
            child: Text('Save', style: TextStyle(color: c.accent)),
          ),
        ],
      ),
    );
  }
}
